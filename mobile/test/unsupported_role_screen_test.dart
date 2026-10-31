import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/screens/unsupported_role_screen.dart';

void main() {
  testWidgets('shows a clear message and a Sign Out button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UnsupportedRoleScreen()));

    expect(find.text('This account type is not available'), findsOneWidget);
    expect(find.text('Please contact the system administrator.'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });
}
