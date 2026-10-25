import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';

void main() {
  test('Offer parses a server offer and counts down', () {
    final now = DateTime(2026, 10, 21, 12, 0, 0);
    final o = Offer.fromMap('I1_R1', {
      'incidentId': 'I1',
      'responderId': 'R1',
      'role': 'fire_suppression',
      'status': 'offered',
      'priority': 'High',
      'category': 'Fire & Rescue',
      'subtype': 'building_fire',
      'distanceKm': 2.1,
      'location': const GeoPoint(-1.2921, 36.8219),
      'flags': ['Person trapped'],
      'needs': ['fire_suppression', 'extrication'],
      'peopleCount': 2,
      'summary': 'x',
      'expiresAt': Timestamp.fromDate(now.add(const Duration(seconds: 38))),
    });
    expect(o.isOpen, isTrue);
    expect(o.secondsLeft(now), 38);
    expect(o.secondsLeft(now.add(const Duration(seconds: 60))), 0);
    expect(o.latitude, closeTo(-1.2921, 1e-9));
    expect(o.subtypeLabel, 'building fire');
    expect(roleLabel('extrication'), 'Extrication');
    expect(o.residentPhone, isNull);
  });

  test('confidential offers never show a subtype', () {
    final o = Offer.fromMap('a', {'status': 'offered', 'subtype': 'sexual_violence', 'confidential': true});
    expect(o.subtypeLabel, '');
  });

  test('DispatchInfo wording', () {
    expect(DispatchInfo.fromMap(null).state, 'none');
    final d = DispatchInfo.fromMap({
      'state': 'unfilled',
      'escalate922': true,
      'reason': 'Call 922.',
      'units': [
        {'role': 'medical_transport', 'name': 'A1', 'phone': '+254', 'status': 'offered', 'distanceKm': 3.4},
      ],
    });
    expect(d.showCallBlock, isTrue);
    expect(d.units.single.statusLabel, 'Alerted');
    expect(DispatchInfo.fromMap({'state': 'enroute'}).headline, 'A responder is on the way');
  });

  test('Responder default capabilities', () {
    final r = ResponderRecord.fromMap('x', {'organizationType': 'Fire'});
    expect(r.effectiveCapabilities, ['fire_suppression', 'extrication']);
    final c = ResponderRecord.fromMap('x', {'organizationType': 'Fire', 'capabilities': ['extrication']});
    expect(c.effectiveCapabilities, ['extrication']);
  });
}
