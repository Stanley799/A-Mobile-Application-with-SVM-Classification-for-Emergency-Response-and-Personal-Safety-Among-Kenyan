// Plain data classes for the dispatch system. No UI. Mirrors what functions/dispatch writes to Firestore.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Capability codes (same strings as functions/dispatch/config.py) with the words a person reads.
const Map<String, String> kRoleLabels = {
  'medical_transport': 'Ambulance / medical transport',
  'fire_suppression': 'Fire suppression',
  'extrication': 'Extrication',
  'law_enforcement': 'Police',
  'maternal_care': 'Maternal care',
  'gbv_care': 'GBV care',
  'antivenom': 'Antivenom',
  'any_responder': 'Any responder',
};

String roleLabel(String code) => kRoleLabels[code] ?? code.replaceAll('_', ' ');

DateTime? _dt(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
List<String> _strs(Object? v) => [for (final x in (v as List? ?? const [])) x.toString()];

/// The hospital a unit chose after arriving at the scene (offers/{id}.transport, written by the unit once).
class TransportLeg {
  const TransportLeg({required this.destinationId, required this.destinationName, this.startedAt, this.arrivedAt});
  final String destinationId;
  final String destinationName;
  final DateTime? startedAt;
  final DateTime? arrivedAt;

  bool get hasArrived => arrivedAt != null;

  /// "1 min 20 s" style travel time; null when a timestamp is missing.
  Duration? get travelTime {
    final s = startedAt;
    if (s == null || arrivedAt == null) return null;
    return arrivedAt!.difference(s);
  }

  factory TransportLeg.fromMap(Map m) => TransportLeg(
    destinationId: (m['destinationId'] ?? '').toString(),
    destinationName: (m['destinationName'] ?? '').toString(),
    startedAt: _dt(m['startedAt']),
    arrivedAt: _dt(m['arrivedAt']),
  );
}

/// A unit's request for extra resources (offers/{id}.moreUnits, written by the unit once).
class MoreUnitsRequest {
  const MoreUnitsRequest({required this.role, required this.count, this.note = '', this.requestedAt});
  final String role;
  final int count;
  final String note;
  final DateTime? requestedAt;

  factory MoreUnitsRequest.fromMap(Map m) => MoreUnitsRequest(
    role: (m['role'] ?? '').toString(),
    count: ((m['count'] ?? 1) as num).toInt(),
    note: (m['note'] ?? '').toString(),
    requestedAt: _dt(m['requestedAt']),
  );
}

/// One request sent to one responder (collection `offers`).
class Offer {
  const Offer({
    required this.id,
    required this.incidentId,
    required this.incidentCode,
    required this.responderId,
    required this.role,
    required this.status,
    required this.priority,
    required this.category,
    required this.subtype,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    required this.flags,
    required this.needs,
    required this.peopleCount,
    required this.wave,
    required this.summary,
    required this.confidential,
    required this.freeText,
    required this.expiresAt,
    required this.createdAt,
    required this.respondedAt,
    required this.residentFirstName,
    required this.residentPhone,
    required this.withdrawReason,
    this.seenAt,
    this.transport,
    this.moreUnits,
    this.note = '',
    this.offerTimes = const {},
    this.callerFeedbackSafe,
    this.landmark = '',
    this.accuracyM,
  });

  final String id;
  final String incidentId;
  final String incidentCode;
  final String responderId;
  final String role;

  /// offered | accepted | declined | enroute | arrived | completed | expired | withdrawn
  final String status;
  final String priority;
  final String category;
  final String? subtype;
  final double distanceKm;
  final double? latitude;
  final double? longitude;
  final List<String> flags;
  final List<String> needs;
  final int peopleCount;
  final int wave;
  final String summary;
  final bool confidential;
  final String freeText;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? respondedAt;
  final String? residentFirstName;
  final String? residentPhone;
  final String? withdrawReason;

  /// First time this unit displayed the offer (set once by the phone; the server records it as an event).
  final DateTime? seenAt;
  final TransportLeg? transport;
  final MoreUnitsRequest? moreUnits;

  /// The unit's own notes for this job (never shown to the caller).
  final String note;

  /// Server-stamped status times ({accepted, enroute, arrived, completed}) for the completion summary.
  final Map<String, DateTime> offerTimes;

  /// The caller's answer to "Are you safe now?" once it arrives; null until then.
  final bool? callerFeedbackSafe;

  /// The caller's words for the place ("opposite Westgate gate B") and how precise the GPS fix was.
  final String landmark;
  final double? accuracyM;

  bool get hasSeen => seenAt != null;

  DateTime? timeFor(String key) {
    final t = offerTimes[key];
    if (t != null) return t;
    // Older offers only carry the last response time, which is still correct for the current status.
    return key == status ? respondedAt : null;
  }

  bool get isOpen => status == 'offered';
  bool get isActiveJob => status == 'accepted' || status == 'enroute' || status == 'arrived';
  bool get isFinished => const ['completed', 'declined', 'expired', 'withdrawn'].contains(status);

  /// Seconds left to answer; 0 when expired. [now] is injectable for tests.
  int secondsLeft([DateTime? now]) {
    final e = expiresAt;
    if (e == null) return 0;
    final s = e.difference(now ?? DateTime.now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  String get subtypeLabel => (subtype == null || confidential) ? '' : subtype!.replaceAll('_', ' ');

  factory Offer.fromMap(String id, Map<String, dynamic> m) {
    final loc = m['location'];
    final res = m['resident'];
    return Offer(
      id: id,
      incidentId: (m['incidentId'] ?? '') as String,
      incidentCode: (m['incidentCode'] ?? m['incidentId'] ?? '') as String,
      responderId: (m['responderId'] ?? '') as String,
      role: (m['role'] ?? 'any_responder') as String,
      status: (m['status'] ?? 'offered') as String,
      priority: (m['priority'] ?? 'High') as String,
      category: (m['category'] ?? '') as String,
      subtype: m['subtype'] as String?,
      distanceKm: ((m['distanceKm'] ?? 0) as num).toDouble(),
      latitude: loc is GeoPoint ? loc.latitude : null,
      longitude: loc is GeoPoint ? loc.longitude : null,
      flags: _strs(m['flags']),
      needs: _strs(m['needs']),
      peopleCount: ((m['peopleCount'] ?? 1) as num).toInt(),
      wave: ((m['wave'] ?? 1) as num).toInt(),
      summary: (m['summary'] ?? '') as String,
      confidential: m['confidential'] == true,
      freeText: (m['freeText'] ?? '') as String,
      expiresAt: _dt(m['expiresAt']),
      createdAt: _dt(m['createdAt']),
      respondedAt: _dt(m['respondedAt']),
      residentFirstName: res is Map ? res['firstName'] as String? : null,
      residentPhone: res is Map ? res['phone'] as String? : null,
      withdrawReason: m['withdrawReason'] as String?,
      seenAt: _dt(m['seenAt']),
      transport: m['transport'] is Map ? TransportLeg.fromMap(m['transport'] as Map) : null,
      moreUnits: m['moreUnits'] is Map ? MoreUnitsRequest.fromMap(m['moreUnits'] as Map) : null,
      note: (m['note'] ?? '').toString(),
      offerTimes: {
        for (final e in (m['offerTimes'] is Map ? m['offerTimes'] as Map : const {}).entries)
          if (_dt(e.value) != null) e.key.toString(): _dt(e.value)!,
      },
      callerFeedbackSafe: m['callerFeedback'] is Map ? (m['callerFeedback'] as Map)['safe'] == true : null,
      landmark: (m['landmark'] ?? '').toString(),
      accuracyM: (m['locationAccuracyM'] as num?)?.toDouble(),
    );
  }
}

/// One responder unit as the RESIDENT sees it (inside incident.dispatch.units).
class DispatchUnit {
  const DispatchUnit({required this.role, required this.name, required this.orgType, required this.phone, required this.status, required this.distanceKm});

  final String role;
  final String name;
  final String orgType;
  final String phone;
  final String status; // offered | accepted | enroute | arrived | completed
  final double? distanceKm;

  /// Words for the resident. "offered" means the unit has been alerted and has not answered yet.
  String get statusLabel => switch (status) {
    'offered' => 'Alerted',
    'accepted' => 'Accepted',
    'enroute' => 'On the way',
    'arrived' => 'Arrived',
    'completed' => 'Done',
    _ => status,
  };

  factory DispatchUnit.fromMap(Map m) => DispatchUnit(
    role: (m['role'] ?? '') as String,
    name: (m['name'] ?? 'Responder') as String,
    orgType: (m['orgType'] ?? '') as String,
    phone: (m['phone'] ?? '') as String,
    status: (m['status'] ?? 'offered') as String,
    distanceKm: (m['distanceKm'] as num?)?.toDouble(),
  );
}

/// incident.dispatch as the RESIDENT sees it.
class DispatchInfo {
  const DispatchInfo({required this.state, required this.escalate922, required this.reason, required this.units});

  /// awaiting_details | waiting_location | dispatching | partially_assigned | assigned | enroute | arrived | completed
  /// | unfilled | no_location | support_only | needs_review | cancelled
  final String state;
  final bool escalate922;
  final String reason;
  final List<DispatchUnit> units;

  static const empty = DispatchInfo(state: 'none', escalate922: false, reason: '', units: []);

  bool get hasUnits => units.isNotEmpty;

  /// The big line at the top of the resident's screen.
  String get headline => switch (state) {
    'assigned' => 'A responder is coming',
    'enroute' => 'A responder is on the way',
    'arrived' => 'A responder has arrived',
    'completed' => 'Help has been completed',
    'partially_assigned' => 'Help is coming. More units are being alerted',
    'unfilled' => 'No responder has accepted yet',
    'no_location' => 'We need your location to find help',
    'support_only' => 'Support is available now',
    'needs_review' => 'A dispatcher will review your alert',
    'cancelled' => 'Alert cancelled',
    'waiting_location' || 'awaiting_details' || 'dispatching' => 'Alerting the nearest responders',
    _ => 'Your alert is recorded',
  };

  String get subline => switch (state) {
    'dispatching' || 'waiting_location' || 'awaiting_details' => 'Keep your phone with you and stay safe.',
    'unfilled' || 'no_location' => reason.isNotEmpty ? reason : 'Please call 922 or 999 now.',
    'needs_review' => 'If someone is in danger, call 922 or 999 now.',
    _ => 'Keep your phone with you and stay safe.',
  };

  /// Show the big call-922/999 block: either the engine asked for it or nobody has accepted yet.
  bool get showCallBlock => escalate922 || state == 'unfilled' || state == 'no_location' || state == 'needs_review';

  factory DispatchInfo.fromMap(Object? raw) {
    if (raw is! Map) return empty;
    return DispatchInfo(
      state: (raw['state'] ?? 'none') as String,
      escalate922: raw['escalate922'] == true,
      reason: (raw['reason'] ?? '') as String,
      units: [for (final u in (raw['units'] as List? ?? const [])) if (u is Map) DispatchUnit.fromMap(u)],
    );
  }
}

/// A responder record as the ADMIN sees it.
class ResponderRecord {
  const ResponderRecord({required this.id, required this.organizationName, required this.organizationType, required this.registrationNumber, required this.verificationStatus, required this.availabilityStatus, required this.serviceArea, required this.capabilities, required this.latitude, required this.longitude, required this.lastSeenAt, required this.isDemo});

  final String id;
  final String organizationName;
  final String organizationType;
  final String registrationNumber;
  final String verificationStatus; // Pending | Verified | Rejected | Suspended
  final String availabilityStatus; // Available | Busy | Offline
  final String serviceArea;
  final List<String> capabilities;
  final double? latitude;
  final double? longitude;
  final DateTime? lastSeenAt;
  final bool isDemo;

  /// Default abilities when the admin has not set any (must match CAPS_BY_TYPE in functions/dispatch/config.py).
  static const Map<String, List<String>> defaultCaps = {
    'Ambulance': ['medical_transport'],
    'Fire': ['fire_suppression', 'extrication'],
    'Police': ['law_enforcement'],
    'Hospital': ['medical_transport', 'maternal_care', 'gbv_care'],
  };

  List<String> get effectiveCapabilities => capabilities.isNotEmpty ? capabilities : (defaultCaps[organizationType] ?? const []);

  factory ResponderRecord.fromMap(String id, Map<String, dynamic> m) => ResponderRecord(
    id: id,
    organizationName: (m['organizationName'] ?? id) as String,
    organizationType: (m['organizationType'] ?? 'Other') as String,
    registrationNumber: (m['registrationNumber'] ?? '') as String,
    verificationStatus: (m['verificationStatus'] ?? 'Pending') as String,
    availabilityStatus: (m['availabilityStatus'] ?? 'Offline') as String,
    serviceArea: (m['serviceArea'] ?? '') as String,
    capabilities: _strs(m['capabilities']),
    latitude: (m['currentLatitude'] as num?)?.toDouble(),
    longitude: (m['currentLongitude'] as num?)?.toDouble(),
    lastSeenAt: _dt(m['lastSeenAt']),
    isDemo: m['isDemo'] == true,
  );
}

/// The five response-time numbers written once when an incident closes.
/// Any step that never happened is null ("Not recorded").
class IncidentMetrics {
  const IncidentMetrics({
    this.secondsToClassify,
    this.secondsToFirstOffer,
    this.secondsToFirstAccept,
    this.secondsToFirstArrival,
    this.secondsTotal,
  });

  final int? secondsToClassify;
  final int? secondsToFirstOffer;
  final int? secondsToFirstAccept;
  final int? secondsToFirstArrival;
  final int? secondsTotal;

  factory IncidentMetrics.fromMap(Map m) => IncidentMetrics(
    secondsToClassify: (m['secondsToClassify'] as num?)?.toInt(),
    secondsToFirstOffer: (m['secondsToFirstOffer'] as num?)?.toInt(),
    secondsToFirstAccept: (m['secondsToFirstAccept'] as num?)?.toInt(),
    secondsToFirstArrival: (m['secondsToFirstArrival'] as num?)?.toInt(),
    secondsTotal: (m['secondsTotal'] as num?)?.toInt(),
  );
}

/// An incident as the ADMIN sees it.
class IncidentRecord {
  const IncidentRecord({required this.id, required this.userId, required this.category, required this.subtype, required this.status, required this.priority, required this.prioritySource, required this.triageStatus, required this.needsHumanReview, required this.createdAt, required this.latitude, required this.longitude, required this.dispatchState, required this.escalate922, required this.priorityReasons, required this.units, required this.answers, required this.description, this.needsAttention = false, this.attentionReason = 'none', this.landmark = '', this.locationAccuracyM, this.locationSource = 'gps', this.dangerFlags = const [], this.metrics, this.resolvedAt, this.cancelledAt, this.callerFeedbackSafe, this.callerRating});

  final String id;
  final String userId;
  final String category;
  final String? subtype;
  final String status;
  final String priority;
  final String prioritySource;
  final String triageStatus;
  final bool needsHumanReview;
  final DateTime? createdAt;
  final double? latitude;
  final double? longitude;
  final String dispatchState;
  final bool escalate922;
  final List<String> priorityReasons;
  final List<DispatchUnit> units;
  final Map<String, String> answers;
  final String description;

  /// Set by the server when a human has to look (SLA, extra units, SOS, imprecise location).
  final bool needsAttention;
  final String attentionReason; // no_accept_in_time | extra_resources | responder_sos | low_accuracy | none
  final String landmark;
  final double? locationAccuracyM;
  final String locationSource; // gps | manual_pin
  final List<String> dangerFlags;
  final IncidentMetrics? metrics;
  final DateTime? resolvedAt;
  final DateTime? cancelledAt;
  final bool? callerFeedbackSafe;
  final int? callerRating;

  bool get isOpen => status == 'Active' || status == 'SupportOnly';

  /// People reported at the scene (from the triage answers; the engine defaults to 1).
  int get peopleCount => int.tryParse(answers['people_count'] ?? '') ?? 1;

  /// The priority the SERVER decided (falls back to what the phone stored).
  factory IncidentRecord.fromMap(String id, Map<String, dynamic> m) {
    final d = m['dispatch'] is Map ? m['dispatch'] as Map : const {};
    final triage = m['triage'] is Map ? m['triage'] as Map : const {};
    final loc = m['location'];
    final ans = triage['answers'] is Map ? triage['answers'] as Map : const {};
    final flags = _strs(m['flags']);
    return IncidentRecord(
      id: id,
      userId: (m['userId'] ?? '') as String,
      category: (m['category'] ?? '') as String,
      subtype: m['subtype'] as String?,
      status: (m['status'] ?? 'Active') as String,
      priority: ((d['priority'] ?? m['priority']) ?? 'High') as String,
      prioritySource: ((d['prioritySource'] ?? m['prioritySource']) ?? '') as String,
      triageStatus: (m['triageStatus'] ?? 'pending') as String,
      needsHumanReview: m['needsHumanReview'] == true,
      createdAt: _dt(m['createdAt']),
      latitude: loc is GeoPoint ? loc.latitude : null,
      longitude: loc is GeoPoint ? loc.longitude : null,
      dispatchState: (d['state'] ?? 'none') as String,
      escalate922: d['escalate922'] == true,
      priorityReasons: _strs(d['priorityReasons']),
      units: [for (final u in (d['units'] as List? ?? const [])) if (u is Map) DispatchUnit.fromMap(u)],
      answers: {for (final e in ans.entries) e.key.toString(): e.value.toString()},
      description: (m['description'] ?? '') as String,
      needsAttention: m['needsAttention'] == true,
      attentionReason: (m['attentionReason'] ?? 'none') as String,
      landmark: (m['landmark'] ?? '') as String,
      locationAccuracyM: (m['locationAccuracyM'] as num?)?.toDouble(),
      locationSource: (m['locationSource'] ?? 'gps') as String,
      dangerFlags: flags.isNotEmpty ? flags : _strs(d['flags']),
      metrics: m['metrics'] is Map ? IncidentMetrics.fromMap(m['metrics'] as Map) : null,
      resolvedAt: _dt(m['resolvedAt']),
      cancelledAt: _dt(m['cancelledAt']),
      callerFeedbackSafe: (m['residentFeedback'] is Map) ? (m['residentFeedback'] as Map)['safe'] == true : null,
      callerRating: (m['residentFeedback'] is Map) ? ((m['residentFeedback'] as Map)['rating'] as num?)?.toInt() : null,
    );
  }
}
