// Pure rules for the staff console: queue order, required roles, contact masking,
// shortcuts, role visibility, candidate ranking and the analytics maths.
// No widgets and no Firebase here, so every rule can be tested directly.
import 'dart:math' as math;

import '../../core/models/dispatch_models.dart';

/// What the two staff roles may open. Hiding is not security: rules and callables enforce the same split.
enum OpsSection { controlRoom, incidents, units, passOnNotes, approvals, directory, analytics, audit }

const Set<OpsSection> kAdminOnlySections = {
  OpsSection.approvals,
  OpsSection.directory,
  OpsSection.analytics,
  OpsSection.audit,
};

List<OpsSection> sectionsFor({required bool isAdmin}) => [
  for (final s in OpsSection.values)
    if (isAdmin || !kAdminOnlySections.contains(s)) s,
];

bool canUseSection(OpsSection s, {required bool isAdmin}) => isAdmin || !kAdminOnlySections.contains(s);

String sectionTitle(OpsSection s) => switch (s) {
  OpsSection.controlRoom => 'Control room',
  OpsSection.incidents => 'Incidents',
  OpsSection.units => 'Units',
  OpsSection.passOnNotes => 'Pass-on notes',
  OpsSection.approvals => 'Approvals',
  OpsSection.directory => 'Directory',
  OpsSection.analytics => 'Analytics',
  OpsSection.audit => 'Audit',
};

// ---------------------------------------------------------------------------------------------
// Roles a category needs (a mirror of routing.base + routing.conditional in triage_schema.json,
// used for display only: the server still decides the plan).
// ---------------------------------------------------------------------------------------------
const Map<String, List<String>> kBaseRequiredRoles = {
  'Medical Emergency': ['medical_transport'],
  'Road Accident': ['medical_transport'],
  'Fire & Rescue': ['fire_suppression'],
  'Security Threat': ['law_enforcement'],
  'Abduction': ['law_enforcement'],
  'Other / General': <String>[],
};

/// Support-only subtypes get no responder at all (dispatch_responder = false on the server).
const Set<String> kSupportOnlySubtypes = {'emotional_distress'};

List<String> requiredRolesFor({required String category, String? subtype, Map<String, String> answers = const {}}) {
  if (subtype != null && kSupportOnlySubtypes.contains(subtype)) return const [];
  var required = [...(kBaseRequiredRoles[category] ?? const <String>[])];
  if (answers['trapped'] == 'Yes' && !required.contains('extrication')) required.add('extrication');
  if (answers['hazard'] == 'Yes' && !required.contains('fire_suppression')) required.add('fire_suppression');
  final needsMedical = answers['severe_bleeding'] == 'Yes' || answers['conscious'] == 'No' || answers['breathing'] == 'No';
  if (needsMedical && (category == 'Security Threat' || category == 'Fire & Rescue') && !required.contains('medical_transport')) {
    required.add('medical_transport');
  }
  if (subtype == 'sexual_violence' || subtype == 'mental_health_crisis') required = ['medical_transport'];
  return required;
}

const Set<String> kHeldStatuses = {'accepted', 'enroute', 'arrived', 'completed'};

/// How many of the required roles already have a unit holding them. An empty requirement means
/// "any responder", which counts as one role.
int filledRoleCount(List<String> required, Iterable<DispatchUnit> units) {
  final held = [for (final u in units) if (kHeldStatuses.contains(u.status)) u.role];
  if (required.isEmpty) return held.isEmpty ? 0 : 1;
  var n = 0;
  for (final role in required) {
    if (held.any((r) => r == role || r == 'any_responder')) n++;
  }
  return n;
}

// ---------------------------------------------------------------------------------------------
// Pending queue
// ---------------------------------------------------------------------------------------------
const Map<String, int> kPriorityRank = {'High': 0, 'Medium': 1, 'Low': 2};

/// Dispatch states that are finished or fully staffed: they never sit in the pending queue.
const Set<String> kSettledStates = {
  'assigned',
  'enroute',
  'arrived',
  'completed',
  'cancelled',
  'support_only',
};

class QueueRow {
  QueueRow({required this.incident, required this.requiredRoles, required this.filledRoles, required this.supportOnly});

  final IncidentRecord incident;
  final List<String> requiredRoles;
  final int filledRoles;

  /// Support-only alerts get no responder, so they are never waiting for staff.
  final bool supportOnly;

  int get rolesNeeded => requiredRoles.isEmpty ? 1 : requiredRoles.length;
  String get rolesLabel => '$filledRoles of $rolesNeeded';
  bool get fullyStaffed => supportOnly || filledRoles >= rolesNeeded;
  bool get pinned => incident.needsAttention;

  String get attentionText => switch (incident.attentionReason) {
    'no_accept_in_time' => 'No unit accepted within the target time',
    'extra_resources' => 'More units were requested',
    'responder_sos' => 'A responder raised an SOS',
    'low_accuracy' => 'Caller location is imprecise',
    _ => incident.needsAttention ? 'Flagged for a human' : '',
  };
}

QueueRow queueRow(IncidentRecord incident) {
  final required = requiredRolesFor(category: incident.category, subtype: incident.subtype, answers: incident.answers);
  return QueueRow(
    incident: incident,
    requiredRoles: required,
    filledRoles: filledRoleCount(required, incident.units),
    supportOnly: incident.subtype != null && kSupportOnlySubtypes.contains(incident.subtype),
  );
}

/// Open incidents that are not fully staffed, SLA breaches pinned first, then priority, then oldest first.
List<QueueRow> buildQueue(Iterable<IncidentRecord> incidents) {
  final rows = <QueueRow>[];
  for (final i in incidents) {
    if (!i.isOpen || kSettledStates.contains(i.dispatchState)) continue;
    final row = queueRow(i);
    if (!row.fullyStaffed) rows.add(row);
  }
  final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
  indexed.sort((a, b) {
    final pa = a.$2.pinned ? 0 : 1;
    final pb = b.$2.pinned ? 0 : 1;
    if (pa != pb) return pa - pb;
    final ra = kPriorityRank[a.$2.incident.priority] ?? 3;
    final rb = kPriorityRank[b.$2.incident.priority] ?? 3;
    if (ra != rb) return ra - rb;
    final ca = a.$2.incident.createdAt?.millisecondsSinceEpoch ?? 0;
    final cb = b.$2.incident.createdAt?.millisecondsSinceEpoch ?? 0;
    if (ca != cb) return ca - cb;
    return a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

// ---------------------------------------------------------------------------------------------
// Contact masking and manual assignment
// ---------------------------------------------------------------------------------------------
/// '0712 345 123' -> '07•• ••• 123'. Other shapes keep only the last three digits.
String maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.length == 10 && digits.startsWith('07')) {
    return '${digits.substring(0, 2)}•• ••• ${digits.substring(7)}';
  }
  final tail = digits.length <= 3 ? digits : digits.substring(digits.length - 3);
  return '${'•' * math.max(0, digits.length - 3)}$tail';
}

/// Both staff roles may assign; the reason is required by the callable too.
bool staffCanAssign({required bool isAdmin, required bool isDispatcher}) => isAdmin || isDispatcher;

String? assignReasonError(String raw) {
  final t = raw.trim();
  if (t.length < 3) return 'Give a reason for the manual assignment (at least 3 characters).';
  if (t.length > 140) return 'Keep the reason to 140 characters.';
  return null;
}

// ---------------------------------------------------------------------------------------------
// Candidates: a presentation-only ranking. The server still owns the plan and re-checks the assign.
// ---------------------------------------------------------------------------------------------
class Candidate {
  Candidate({required this.responder, required this.distanceKm, required this.etaMinutes});

  final ResponderRecord responder;
  final double? distanceKm;
  final int? etaMinutes;

  String get name => responder.organizationName;
}

const double _earthRadiusKm = 6371.0;

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dp = rad(lat2 - lat1);
  final dl = rad(lng2 - lng1);
  final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * _earthRadiusKm * math.asin(math.sqrt(h));
}

/// Verified, fresh, available responders that hold [role] (null = any ability), nearest first.
/// Already-asked units are skipped.
List<Candidate> rankCandidates({
  required double? lat,
  required double? lng,
  required String? role,
  required Iterable<ResponderRecord> responders,
  Set<String> alreadyAsked = const {},
  DateTime? now,
  int limit = 5,
}) {
  final at = now ?? DateTime.now();
  final out = <Candidate>[];
  for (final r in responders) {
    if (alreadyAsked.contains(r.id)) continue;
    if (r.verificationStatus != 'Verified' || r.availabilityStatus != 'Available') continue;
    if (role != null && !r.effectiveCapabilities.contains(role)) continue;
    final seen = r.lastSeenAt;
    if (seen != null && at.difference(seen).inSeconds > 120) continue;
    double? d;
    if (lat != null && lng != null && r.latitude != null && r.longitude != null) {
      d = haversineKm(lat, lng, r.latitude!, r.longitude!);
    }
    out.add(Candidate(responder: r, distanceKm: d, etaMinutes: d == null ? null : math.max(1, (d / 35 * 60).round())));
  }
  out.sort((a, b) {
    final da = a.distanceKm ?? double.infinity;
    final db = b.distanceKm ?? double.infinity;
    if (da != db) return da.compareTo(db);
    return a.responder.id.compareTo(b.responder.id);
  });
  return out.take(limit).toList();
}

// ---------------------------------------------------------------------------------------------
// Keyboard shortcuts (web). They never fire while a text field has focus.
// ---------------------------------------------------------------------------------------------
enum OpsShortcut { nextIncident, previousIncident, openIncident, candidates, message, search, closePanel, help }

OpsShortcut? shortcutFor(String key, {required bool typing}) {
  if (typing) return null;
  return switch (key) {
    'j' || 'J' => OpsShortcut.nextIncident,
    'k' || 'K' => OpsShortcut.previousIncident,
    'Enter' => OpsShortcut.openIncident,
    'a' || 'A' => OpsShortcut.candidates,
    'm' || 'M' => OpsShortcut.message,
    '/' => OpsShortcut.search,
    'Escape' => OpsShortcut.closePanel,
    '?' => OpsShortcut.help,
    _ => null,
  };
}

const Map<OpsShortcut, String> kShortcutHelp = {
  OpsShortcut.nextIncident: 'J — next incident',
  OpsShortcut.previousIncident: 'K — previous incident',
  OpsShortcut.openIncident: 'Enter — open the incident',
  OpsShortcut.candidates: 'A — Candidates tab',
  OpsShortcut.message: 'M — message box',
  OpsShortcut.search: '/ — search',
  OpsShortcut.closePanel: 'Esc — close the panel',
  OpsShortcut.help: '? — this list',
};

// ---------------------------------------------------------------------------------------------
// Caller check-in: the five fixed questions the server knows (functions/phase4d_core.py).
// ---------------------------------------------------------------------------------------------
const Map<String, String> kCheckinTemplates = {
  'can_you_talk': 'Can you talk safely right now?',
  'person_breathing': 'Is the person breathing normally?',
  'still_in_danger': 'Are you still in danger?',
  'location_ok': 'Is the street shown on your screen correct?',
  'stay_put': 'Stay where you are. Help is being arranged. Tap OK.',
};

// ---------------------------------------------------------------------------------------------
// Analytics maths
// ---------------------------------------------------------------------------------------------
class SampleStats {
  const SampleStats({required this.sample, required this.median, required this.p90});

  final int sample;
  final int? median;
  final int? p90;

  static const empty = SampleStats(sample: 0, median: null, p90: null);
}

/// Median (rounded mean of the middle pair) and 90th percentile (nearest rank) of the numbers that exist.
/// Nulls are skipped; the sample tells the reader how many numbers were used.
SampleStats sampleStats(Iterable<int?> values) {
  final xs = [for (final v in values) if (v != null) v]..sort();
  if (xs.isEmpty) return SampleStats.empty;
  final mid = xs.length ~/ 2;
  final median = xs.length.isOdd ? xs[mid] : ((xs[mid - 1] + xs[mid]) / 2).round();
  final rank = math.max(1, (0.9 * xs.length).ceil());
  return SampleStats(sample: xs.length, median: median, p90: xs[rank - 1]);
}

/// mm:ss for the elapsed timer and the timeline offsets.
String mmss(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------------------------
// Unit statistics for the units board (computed only when a unit is expanded).
// ---------------------------------------------------------------------------------------------
class UnitStats {
  const UnitStats({required this.offers, required this.acceptanceRate, required this.sample, required this.medianSecondsToAccept, required this.averageSecondsToAccept});

  final int offers;
  final double? acceptanceRate;
  final int sample;
  final int? medianSecondsToAccept;
  final int? averageSecondsToAccept;

  static const empty = UnitStats(offers: 0, acceptanceRate: null, sample: 0, medianSecondsToAccept: null, averageSecondsToAccept: null);
}

/// The last 100 offers for one responder: how many were accepted, and how long acceptance took.
UnitStats unitStats(Iterable<Offer> offers, String responderId, {DateTime? now, int windowDays = 30, int maxOffers = 100}) {
  final at = now ?? DateTime.now();
  final mine = [
    for (final o in offers)
      if (o.responderId == responderId && (o.createdAt == null || at.difference(o.createdAt!).inDays <= windowDays)) o,
  ]..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
  final last = mine.take(maxOffers).toList();
  if (last.isEmpty) return UnitStats.empty;
  final accepted = [for (final o in last) if (o.status == 'accepted' || kHeldStatuses.contains(o.status) && o.respondedAt != null) o];
  final gaps = [
    for (final o in accepted)
      if (o.createdAt != null && o.respondedAt != null) o.respondedAt!.difference(o.createdAt!).inSeconds,
  ];
  return UnitStats(
    offers: last.length,
    acceptanceRate: accepted.length / last.length,
    sample: gaps.length,
    medianSecondsToAccept: sampleStats(gaps).median,
    averageSecondsToAccept: gaps.isEmpty ? null : (gaps.reduce((a, b) => a + b) / gaps.length).round(),
  );
}
