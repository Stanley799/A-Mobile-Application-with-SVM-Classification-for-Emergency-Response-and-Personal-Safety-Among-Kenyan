// The numbers on the Overview page. Pure functions, unit-tested.
import '../../core/models/dispatch_models.dart';

const _attentionStates = {'unfilled', 'no_location', 'needs_review'};

class AdminStats {
  const AdminStats({required this.open, required this.attention, required this.today, required this.byCategory, required this.byPriority, required this.avgFirstAcceptSeconds, required this.available, required this.busy, required this.pendingVerification, required this.verified});

  final List<IncidentRecord> open;
  final List<IncidentRecord> attention;
  final int today;
  final Map<String, int> byCategory;
  final Map<String, int> byPriority;

  /// Average seconds from the first offer to the first acceptance, over incidents that had one. Null when none.
  final double? avgFirstAcceptSeconds;
  final int available;
  final int busy;
  final int pendingVerification;
  final int verified;

  /// An incident needs a human when dispatch failed, or the engine asked for 922, or triage wants review.
  static bool needsAttention(IncidentRecord i) => i.isOpen && (_attentionStates.contains(i.dispatchState) || i.escalate922 || (i.needsHumanReview && i.triageStatus == 'complete'));

  static AdminStats compute(List<IncidentRecord> incidents, List<Offer> offers, List<ResponderRecord> responders, DateTime now) {
    final open = [for (final i in incidents) if (i.isOpen) i];
    final startOfDay = DateTime(now.year, now.month, now.day);
    final byCat = <String, int>{};
    final byPri = <String, int>{};
    var today = 0;
    for (final i in incidents) {
      if (i.createdAt != null && !i.createdAt!.isBefore(startOfDay)) {
        today++;
        byCat[i.category] = (byCat[i.category] ?? 0) + 1;
        byPri[i.priority] = (byPri[i.priority] ?? 0) + 1;
      }
    }
    final firstOffer = <String, DateTime>{};
    final firstAccept = <String, DateTime>{};
    for (final o in offers) {
      final c = o.createdAt;
      if (c != null && (firstOffer[o.incidentId] == null || c.isBefore(firstOffer[o.incidentId]!))) firstOffer[o.incidentId] = c;
      final r = o.respondedAt;
      if (r != null && const ['accepted', 'enroute', 'arrived', 'completed'].contains(o.status) && (firstAccept[o.incidentId] == null || r.isBefore(firstAccept[o.incidentId]!))) {
        firstAccept[o.incidentId] = r;
      }
    }
    final gaps = <int>[
      for (final e in firstAccept.entries)
        if (firstOffer[e.key] != null && !e.value.isBefore(firstOffer[e.key]!)) e.value.difference(firstOffer[e.key]!).inSeconds,
    ];
    final verified = [for (final r in responders) if (r.verificationStatus == 'Verified') r];
    return AdminStats(
      open: open,
      attention: [for (final i in open) if (needsAttention(i)) i],
      today: today,
      byCategory: byCat,
      byPriority: byPri,
      avgFirstAcceptSeconds: gaps.isEmpty ? null : gaps.reduce((a, b) => a + b) / gaps.length,
      available: verified.where((r) => r.availabilityStatus == 'Available').length,
      busy: verified.where((r) => r.availabilityStatus == 'Busy').length,
      pendingVerification: responders.where((r) => r.verificationStatus == 'Pending').length,
      verified: verified.length,
    );
  }
}
