// 2.5: the SOS needs a deliberate 2-second hold; a shorter press sends nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/responder/sos_sheet.dart';

Future<List<int>> _pump(WidgetTester tester) async {
  final calls = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SosHoldButton(
            onSend: () async {
              calls.add(1);
            },
          ),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  testWidgets('a short press sends nothing', (tester) async {
    final calls = await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosHoldButton)),
    );
    await tester.pump(const Duration(milliseconds: 150)); // tap-down deadline
    await tester.pump(const Duration(milliseconds: 1200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('Hold 2 seconds to send'), findsOneWidget);
  });

  testWidgets('holding for two seconds sends exactly once', (tester) async {
    final calls = await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosHoldButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(calls.length, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    expect(find.text('Sent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the progress ring fills while the finger is down', (tester) async {
    await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosHoldButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 900));
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, greaterThan(0));
    expect(ring.value, lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
