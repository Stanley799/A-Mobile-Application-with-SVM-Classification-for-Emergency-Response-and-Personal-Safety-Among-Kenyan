import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/admin_repository.dart';

void main() {
  test('AdminAccount.fromMap tolerates missing fields', () {
    final a = AdminAccount.fromMap({'uid': 'u1', 'email': 'a@b.org', 'lastSignInAt': 1700000000000});
    expect(a.uid, 'u1');
    expect(a.disabled, false);
    expect(a.lastSignInAt, isNotNull);
    final b = AdminAccount.fromMap({});
    expect(b.email, '');
    expect(b.lastSignInAt, isNull);
  });
}
