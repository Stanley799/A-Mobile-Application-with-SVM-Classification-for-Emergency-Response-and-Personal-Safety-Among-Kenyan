import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/ops/ops_logic.dart';

Offer offer(
  String id, {
  String incidentId = 'INC1',
  String role = 'medical_transport',
  int wave = 1,
  DateTime? created,
  String status = 'offered',
  String? reason,
}) => Offer.fromMap(id, {
  'incidentId': incidentId,
  'responderId': 'r-$id',
  'role': role,
  'status': status,
  'wave': wave,
  'createdAt': created == null ? null : Timestamp.fromDate(created),
  'withdrawReason': reason,
});

void main() {
  test('offers for one role are oldest first, then by wave', () {
    final offers = [
      offer('third', created: DateTime(2026, 10, 29, 12, 3)),
      offer('first', created: DateTime(2026, 10, 29, 12, 1)),
      offer('second', created: DateTime(2026, 10, 29, 12, 1), wave: 2),
      offer('other-role', role: 'fire_suppression', created: DateTime(2026, 10, 29, 12, 0)),
      offer('other-incident', incidentId: 'INC2', created: DateTime(2026, 10, 29, 12, 0)),
    ];
    expect([for (final o in offersForRole(offers, 'INC1', 'medical_transport')) o.id], ['first', 'second', 'third']);
    expect([for (final o in offersForRole(offers, 'INC1', 'fire_suppression')) o.id], ['other-role']);
    expect(offersForRole(offers, 'INC1', 'extrication'), isEmpty);
  });

  test('the answer says what the backend recorded, never more', () {
    expect(offerAnswerWord(offer('a')), 'No answer yet');
    expect(offerAnswerWord(offer('b', status: 'accepted')), 'Accepted');
    expect(offerAnswerWord(offer('c', status: 'declined')), 'Declined');
    expect(offerAnswerWord(offer('d', status: 'expired')), 'Expired');
    expect(offerAnswerWord(offer('e', status: 'withdrawn')), 'Withdrawn');
  });

  test('a decline or withdrawal reason is shown in words; no reason stays empty', () {
    expect(offerReasonWord(offer('a', status: 'declined')), '');
    expect(offerReasonWord(offer('b', status: 'withdrawn', reason: 'scene_unsafe')), 'Scene unsafe');
    expect(offerReasonWord(offer('c', status: 'withdrawn', reason: 'another_unit_accepted')), 'Another unit accepted');
  });
}
