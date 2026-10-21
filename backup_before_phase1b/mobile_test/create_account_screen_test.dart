import 'package:dlibphonenumber/dlibphonenumber.dart' as libphone;
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart'
    as intl_phone;
import 'package:mobile/features/auth/screens/create_account_screen.dart';
import 'package:mobile/core/constants/kenya_counties.dart';

void main() {
  testWidgets('registration number is only shown for responders', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountScreen()));

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

  testWidgets('registration number validates length and allowed characters', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountScreen()));
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();

    final registrationFieldFinder = find.ancestor(
      of: find.text('Organization Registration Number'),
      matching: find.byType(TextFormField),
    );
    final registrationField = tester.widget<TextFormField>(
      registrationFieldFinder,
    );
    final registrationInput = tester.widget<TextField>(
      find.descendant(
        of: registrationFieldFinder,
        matching: find.byType(TextField),
      ),
    );
    final validator = registrationField.validator!;

    expect(registrationInput.keyboardType, TextInputType.text);
    expect(registrationInput.textCapitalization, TextCapitalization.characters);
    expect(
      registrationField.autovalidateMode,
      AutovalidateMode.onUserInteraction,
    );
    expect(validator(null), 'Organization registration number is required');
    expect(validator('  '), 'Organization registration number is required');
    expect(validator('41469'), isNull);
    expect(validator('218/051/2005/0472'), isNull);
    expect(
      validator('ABC'),
      'Registration number must be at least 5 characters',
    );
    expect(
      validator('ABC@123'),
      'Only letters, numbers, slashes, dots, and hyphens are allowed',
    );
    expect(validator('A' * 31), 'Registration number is too long');
  });

  testWidgets('responder county selector searches, selects, and clears', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountScreen()));

    expect(kenyaCounties, hasLength(47));
    expect(find.text('Service Area (County)'), findsNothing);

    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();

    final countySelector = find.byType(DropdownSearch<String>);
    expect(countySelector, findsOneWidget);
    await tester.ensureVisible(countySelector);
    await tester.tap(countySelector);
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Type to search...',
    );
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'Nai');
    await tester.pumpAndSettle();

    expect(find.text('Nairobi'), findsOneWidget);
    expect(find.text('Nakuru'), findsNothing);
    await tester.tap(
      find.ancestor(of: find.text('Nairobi'), matching: find.byType(ListTile)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nairobi'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    final selector = tester.widget<DropdownSearch<String>>(countySelector);
    expect(selector.selectedItems, ['Nairobi']);
    expect(selector.validator!(null), 'Please select your service area');

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('Nairobi'), findsNothing);
    expect(find.byIcon(Icons.clear), findsNothing);

    final createAccountButton = find.widgetWithText(
      FilledButton,
      'Create Account',
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();
    expect(find.text('Please select your service area'), findsOneWidget);
  });

  testWidgets("phone validation uses the selected country's numbering plan", (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountScreen()));

    final phoneFieldFinder = find.byType(
      intl_phone.InternationalPhoneNumberInput,
    );
    final kenyaField = tester.widget<intl_phone.InternationalPhoneNumberInput>(
      phoneFieldFinder,
    );
    expect(kenyaField.initialValue?.isoCode, 'KE');
    expect(kenyaField.validator!(null), 'Phone number is required');
    expect(kenyaField.validator!('0712345678'), isNull);
    expect(kenyaField.validator!('0112345678'), isNull);
    expect(kenyaField.validator!('0712345'), isNotNull);
    expect(kenyaField.validator!('0999999999'), isNotNull);

    kenyaField.onInputChanged!(intl_phone.PhoneNumber(isoCode: 'US'));
    await tester.pump();
    final usField = tester.widget<intl_phone.InternationalPhoneNumberInput>(
      phoneFieldFinder,
    );
    expect(usField.validator!('4155551234'), isNull);
    expect(usField.validator!('1234567890'), isNotNull);

    usField.onInputChanged!(intl_phone.PhoneNumber(isoCode: 'GB'));
    await tester.pump();
    final ukField = tester.widget<intl_phone.InternationalPhoneNumberInput>(
      phoneFieldFinder,
    );
    expect(ukField.validator!('7911123456'), isNull);
    expect(ukField.validator!('0000000000'), isNotNull);

    final phoneUtil = libphone.PhoneNumberUtil.instance;
    final parsedKenyanNumber = phoneUtil.parse('0712345678', 'KE');
    expect(
      phoneUtil.format(parsedKenyanNumber, libphone.PhoneNumberFormat.e164),
      '+254712345678',
    );
  });
}
