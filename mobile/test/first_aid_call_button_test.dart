import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/first_aid/first_aid_constants.dart';
import 'package:mobile/features/resident/first_aid/first_aid_player.dart';
import 'package:mobile/features/resident/first_aid/first_aid_widgets.dart';

import 'first_aid_fixture.dart';

Widget _player({required void Function(String) onCall, bool quiet = false, bool reduceMotion = false}) {
  final catalog = approvedFirstAidCatalog();
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(
      body: FirstAidPlayer(
        guide: catalog.guideById('cpr_adult')!,
        catalog: catalog,
        language: FirstAidLanguage.en,
        onChooseDifferent: () {},
        onDone: () {},
        quiet: quiet,
        onCall: onCall,
      ),
    ),
  );
}

void main() {
  testWidgets('Call 999 is pinned on every step and reports 999', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_player(onCall: calls.add));

    for (var step = 1; step <= 6; step++) {
      expect(find.text('Step $step of 6'), findsOneWidget);
      final call = find.byKey(const ValueKey('first_aid_call_999'));
      expect(call, findsOneWidget);
      expect(find.text('Call 999'), findsOneWidget);

      await tester.tap(call);
      await tester.pump();
      expect(calls.length, step);
      expect(calls.last, '999');
      // Calling never advances the step.
      expect(find.text('Step $step of 6'), findsOneWidget);

      if (step < 6) {
        await tester.tap(find.text('Next'));
        await tester.pump();
      }
    }
  });

  testWidgets('a pulse step shows the counted rate and the vibration switch', (tester) async {
    await tester.pumpWidget(_player(onCall: (_) {}));

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }

    expect(find.text('Step 5 of 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('first_aid_pulse')), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
    expect(find.text('110 per minute'), findsOneWidget);

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged, isNotNull);
  });

  testWidgets('quiet mode turns the vibration switch off', (tester) async {
    await tester.pumpWidget(_player(onCall: (_) {}, quiet: true));

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }

    expect(find.text('Off in quiet mode'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged, isNull);
    expect(toggle.value, isFalse);
  });

  testWidgets('reduced motion shows the static counter at the same rate', (tester) async {
    await tester.pumpWidget(_player(onCall: (_) {}, reduceMotion: true));

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }

    expect(find.byKey(const ValueKey('first_aid_pulse_static')), findsOneWidget);
    expect(find.byKey(const ValueKey('first_aid_pulse')), findsNothing);
    expect(find.text('110 per minute'), findsOneWidget);
  });

  testWidgets('the call panel offers 999 and 112', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FirstAidCallPanel(language: FirstAidLanguage.en)),
    ));
    expect(find.text('Call 999'), findsOneWidget);
    expect(find.text('Call 112'), findsOneWidget);
  });

  testWidgets('on the web the dial copies the number and says so', (tester) async {
    final copied = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => firstAidDial(
              context,
              '999',
              language: FirstAidLanguage.en,
              webOverride: true,
              copy: (number) async => copied.add(number),
            ),
            child: const Text('dial'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('dial'));
    await tester.pumpAndSettle();

    expect(copied, ['999']);
    expect(
      find.text('A computer cannot dial. 999 was copied; call it from your phone.'),
      findsOneWidget,
    );
  });
}
