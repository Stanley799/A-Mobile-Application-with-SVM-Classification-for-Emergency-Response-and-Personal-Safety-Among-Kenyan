import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/screens/create_account_screen.dart';

void main() {
  testWidgets('registration number is only shown for responders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateAccountScreen()),
    );

    expect(find.text('Organization Registration Number'), findsNothing);

    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();

    expect(find.text('Organization Registration Number'), findsOneWidget);
    expect(
      find.text(
        'Enter the official registration number from your Certificate of Incorporation or NGO registration certificate.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('registration number validates length and allowed characters', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateAccountScreen()),
    );
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();

    final registrationFieldFinder = find.ancestor(
      of: find.text('Organization Registration Number'),
      matching: find.byType(TextFormField),
    );
    final registrationField = tester.widget<TextFormField>(registrationFieldFinder);
    final registrationInput = tester.widget<TextField>(
      find.descendant(
        of: registrationFieldFinder,
        matching: find.byType(TextField),
      ),
    );
    final validator = registrationField.validator!;

    expect(registrationInput.keyboardType, TextInputType.text);
    expect(registrationInput.textCapitalization, TextCapitalization.characters);
    expect(registrationField.autovalidateMode, AutovalidateMode.onUserInteraction);
    expect(validator(null), 'Organization registration number is required');
    expect(validator('  '), 'Organization registration number is required');
    expect(validator('41469'), isNull);
    expect(validator('218/051/2005/0472'), isNull);
    expect(validator('ABC'), 'Registration number must be at least 5 characters');
    expect(
      validator('ABC@123'),
      'Only letters, numbers, slashes, dots, and hyphens are allowed',
    );
    expect(validator('A' * 31), 'Registration number is too long');
  });
}