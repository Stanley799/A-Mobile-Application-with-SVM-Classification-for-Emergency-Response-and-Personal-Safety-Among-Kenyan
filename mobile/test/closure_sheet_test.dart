import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/widgets/closure_sheet.dart';

Widget _host(Future<bool> Function(bool safe, int? rating) onSave, {VoidCallback? onRaiseAlert}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => showClosureSheet(context, onSave: onSave, onRaiseAlert: onRaiseAlert),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('answers once and saves the optional rating', (tester) async {
    final calls = <(bool, int?)>[];
    await tester.pumpWidget(_host((safe, rating) async {
      calls.add((safe, rating));
      return true;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Are you safe now?'), findsOneWidget);
    expect(find.text("Yes, I'm safe"), findsOneWidget);
    expect(find.text('No, I still need help'), findsOneWidget);

    await tester.tap(find.text("Yes, I'm safe"));
    await tester.pump();
    await tester.tap(find.byTooltip('4 of 5'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(calls, [(true, 4)]);
    expect(find.text('Are you safe now?'), findsNothing);
  });

  testWidgets('a double tap on Send still saves only once', (tester) async {
    final gate = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(_host((safe, rating) {
      calls++;
      return gate.future;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Yes, I'm safe"));
    await tester.pump();

    await tester.tap(find.text('Send'));
    await tester.tap(find.text('Send'), warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
    gate.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('Skip saves without a rating', (tester) async {
    final calls = <(bool, int?)>[];
    await tester.pumpWidget(_host((safe, rating) async {
      calls.add((safe, rating));
      return true;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Yes, I'm safe"));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(calls, [(true, null)]);
  });

  testWidgets('"No, I still need help" offers both numbers and a new alert', (tester) async {
    var raised = 0;
    await tester.pumpWidget(_host((safe, rating) async => true, onRaiseAlert: () => raised++));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, I still need help'));
    await tester.pump();

    expect(find.text('Call 999'), findsOneWidget);
    expect(find.text('Call 922'), findsOneWidget);
    expect(find.text('Raise a new alert'), findsOneWidget);

    await tester.tap(find.text('Raise a new alert'));
    await tester.pumpAndSettle();
    expect(raised, 1);
  });
}
