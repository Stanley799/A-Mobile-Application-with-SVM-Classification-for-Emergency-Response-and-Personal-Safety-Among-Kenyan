import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/diagnostics/firebase_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('never throws, even when Firebase has not started', () {
    expect(logFirebaseDiagnostics, returnsNormally);
  });
}
