import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/screens/sos_confirmation_sheet.dart';
import 'package:mobile/features/resident/widgets/sos_button.dart';

void main() {
  testWidgets('SOS button reports a tap', (tester) async {
    var wasPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SosButton(onPressed: () => wasPressed = true),
          ),
        ),
      ),
    );

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Report Emergency'), findsOneWidget);
    await tester.tap(find.text('SOS'));
    await tester.pump();

    expect(wasPressed, isTrue);
  });

  testWidgets('SOS confirmation shows category and can be cancelled', (
    tester,
  ) async {
    bool? confirmationResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmationResult = await showModalBottomSheet<bool>(
                  context: context,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (context) => const SosConfirmationSheet(
                    category: 'Medical Emergency',
                  ),
                );
              },
              child: const Text('Open SOS confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open SOS confirmation'));
    await tester.pumpAndSettle();

    expect(find.text('Sending Medical Emergency alert in...'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(confirmationResult, isFalse);
  });
}