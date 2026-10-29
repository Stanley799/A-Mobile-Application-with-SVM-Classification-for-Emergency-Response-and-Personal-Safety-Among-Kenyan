// 2.3: the request sheet offers four roles in human words, 1 to 3 units, and a short note.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/responder/more_units_sheet.dart';

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(String role, int count, String note) onSubmit,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showMoreUnitsSheet(context, onSubmit: onSubmit),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('role chips are in human words and the count stays between 1 and 3', (
    tester,
  ) async {
    await _open(tester, (role, count, note) async {});

    for (final label in ['Ambulance', 'Fire', 'Police', 'Medical support']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    // At three the control is disabled, so a fourth tap cannot exceed the cap.
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed,
      isNull,
    );
  });

  testWidgets('the note is capped at 140 characters', (tester) async {
    await _open(tester, (role, count, note) async {});
    final field = find.byType(TextField);
    await tester.enterText(field, 'a' * 200);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text.length, 140);
  });

  testWidgets('Request sends the chosen role, count and note', (tester) async {
    String? role;
    int? count;
    String? note;
    await _open(tester, (r, c, n) async {
      role = r;
      count = c;
      note = n;
    });

    await tester.tap(find.text('Police'));
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Crowd at the gate');
    await tester.pump();

    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();

    expect(role, 'law_enforcement');
    expect(count, 2);
    expect(note, 'Crowd at the gate');
    expect(find.text('Request more units'), findsNothing); // sheet closed
  });

  testWidgets('a failed request stays open and offers a retry', (tester) async {
    await _open(tester, (role, count, note) async {
      throw Exception('offline');
    });
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not send the request. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Request'), findsOneWidget);
  });
}
