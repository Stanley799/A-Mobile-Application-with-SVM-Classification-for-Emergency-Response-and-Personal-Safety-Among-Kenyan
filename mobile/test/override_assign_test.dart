import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/ops/ops_logic.dart';

void main() {
  test('only an administrator can override and assign a unit', () {
    expect(staffCanAssign(isAdmin: true), isTrue);
    expect(staffCanAssign(isAdmin: false), isFalse);
  });

  test('an override needs a real reason before the confirm step', () {
    expect(assignReasonError(''), isNotNull);
    expect(assignReasonError('  '), isNotNull);
    expect(assignReasonError('ab'), isNotNull);
    expect(assignReasonError('abc'), isNull);
    expect(assignReasonError('x' * 140), isNull);
    expect(assignReasonError('x' * 141), isNotNull);
  });
}
