import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/ops/ops_logic.dart';

ResponderRecord responder({
  required String id,
  String type = 'Ambulance',
  String verification = 'Verified',
  String availability = 'Available',
  DateTime? lastSeen,
  double? lat,
  double? lng,
  List<String> capabilities = const [],
}) => ResponderRecord.fromMap(id, {
  'organizationName': 'Unit $id',
  'organizationType': type,
  'verificationStatus': verification,
  'availabilityStatus': availability,
  'capabilities': capabilities,
  'currentLatitude': lat,
  'currentLongitude': lng,
  if (lastSeen != null) 'lastSeenAt': Timestamp.fromDate(lastSeen),
});

void main() {
  test('a reason is required and both staff roles may assign', () {
    expect(staffCanAssign(isAdmin: true, isDispatcher: false), isTrue);
    expect(staffCanAssign(isAdmin: false, isDispatcher: true), isTrue);
    expect(staffCanAssign(isAdmin: false, isDispatcher: false), isFalse);

    expect(assignReasonError(''), isNotNull);
    expect(assignReasonError('ab'), isNotNull);
    expect(assignReasonError('  ab  '), isNotNull);
    expect(assignReasonError('Flooding reported by caller'), isNull);
    expect(assignReasonError('x' * 141), isNotNull);
  });

  test('candidates are verified, available, capable and fresh, nearest first', () {
    final now = DateTime(2026, 10, 29, 12);
    final list = [
      responder(id: 'far', lat: -1.31, lng: 36.83, lastSeen: now),
      responder(id: 'near', lat: -1.293, lng: 36.822, lastSeen: now),
      responder(id: 'busy', availability: 'Busy', lat: -1.2925, lng: 36.822, lastSeen: now),
      responder(id: 'pending', verification: 'Pending', lat: -1.2925, lng: 36.822, lastSeen: now),
      responder(id: 'stale', lat: -1.2925, lng: 36.822, lastSeen: now.subtract(const Duration(minutes: 10))),
      responder(id: 'wrongcap', type: 'Police', lat: -1.2925, lng: 36.822, lastSeen: now),
      responder(id: 'asked', lat: -1.2925, lng: 36.822, lastSeen: now),
    ];
    final out = rankCandidates(lat: -1.2921, lng: 36.8219, role: 'medical_transport', responders: list, alreadyAsked: {'asked'}, now: now);
    expect([for (final c in out) c.responder.id], ['near', 'far']);
    expect(out.first.distanceKm, isNotNull);
    expect(out.first.distanceKm! < out[1].distanceKm!, isTrue);
    expect(out.first.etaMinutes, greaterThanOrEqualTo(1));
  });

  test('assigning needs a role the unit actually has', () {
    expect(rankCandidates(lat: null, lng: null, role: 'fire_suppression', responders: [responder(id: 'a', lat: -1.29, lng: 36.82)], now: DateTime(2026, 10, 29)), isEmpty);
  });

  test('unit statistics use the last offers and count only answered ones', () {
    final now = DateTime(2026, 10, 29, 12);
    Offer offer(String id, String status, int sentMinutesAgo, int? respondedSeconds) => Offer.fromMap(id, {
      'responderId': 'R1',
      'status': status,
      'createdAt': Timestamp.fromDate(now.subtract(Duration(minutes: sentMinutesAgo))),
      if (respondedSeconds != null) 'respondedAt': Timestamp.fromDate(now.subtract(Duration(minutes: sentMinutesAgo)).add(Duration(seconds: respondedSeconds))),
    });
    final stats = unitStats([
      offer('a', 'accepted', 10, 30),
      offer('b', 'declined', 20, null),
      offer('c', 'accepted', 30, 50),
      offer('d', 'offered', 40, null),
    ], 'R1', now: now);
    expect(stats.offers, 4);
    expect(stats.acceptanceRate, closeTo(0.5, 1e-9));
    expect(stats.sample, 2);
    expect(stats.medianSecondsToAccept, 40);
    expect(stats.averageSecondsToAccept, 40);
  });
}
