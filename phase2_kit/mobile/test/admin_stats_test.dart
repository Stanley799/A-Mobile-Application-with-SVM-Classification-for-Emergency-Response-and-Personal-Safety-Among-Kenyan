import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/admin/admin_stats.dart';

IncidentRecord inc(String id, {String state = 'dispatching', String status = 'Active', String cat = 'Medical Emergency', String pri = 'High', bool esc = false, DateTime? at}) =>
    IncidentRecord.fromMap(id, {
      'userId': 'u',
      'category': cat,
      'status': status,
      'priority': pri,
      'triageStatus': 'pending',
      'createdAt': null,
      'dispatch': {'state': state, 'escalate922': esc, 'priority': pri},
    });

void main() {
  test('attention rule', () {
    expect(AdminStats.needsAttention(inc('a', state: 'unfilled')), isTrue);
    expect(AdminStats.needsAttention(inc('a', state: 'dispatching')), isFalse);
    expect(AdminStats.needsAttention(inc('a', state: 'unfilled', status: 'Resolved')), isFalse);
    expect(AdminStats.needsAttention(inc('a', esc: true)), isTrue);
  });

  test('counts', () {
    final s = AdminStats.compute([inc('a'), inc('b', state: 'no_location'), inc('c', status: 'Cancelled')], const [], const [], DateTime.now());
    expect(s.open.length, 2);
    expect(s.attention.length, 1);
    expect(s.avgFirstAcceptSeconds, isNull);
  });

  test('responder counts', () {
    final r = [
      ResponderRecord.fromMap('1', {'verificationStatus': 'Verified', 'availabilityStatus': 'Available'}),
      ResponderRecord.fromMap('2', {'verificationStatus': 'Verified', 'availabilityStatus': 'Busy'}),
      ResponderRecord.fromMap('3', {'verificationStatus': 'Pending'}),
    ];
    final s = AdminStats.compute(const [], const [], r, DateTime.now());
    expect((s.available, s.busy, s.pendingVerification, s.verified), (1, 1, 1, 2));
  });
}
