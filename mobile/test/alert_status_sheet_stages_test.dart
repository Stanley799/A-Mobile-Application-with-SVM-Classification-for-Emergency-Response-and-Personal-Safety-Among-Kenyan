import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/core/triage/triage_schema.dart';
import 'package:mobile/features/resident/map/help_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/widgets/alert_status_sheet.dart';

class _Repo extends HelpRepository {
  _Repo(String category)
    : _category = category,
      super(db: FakeFirebaseFirestore());

  final String _category;

  @override
  Stream<IncidentInfo> watchIncident(String incidentId) =>
      Stream<IncidentInfo>.value(IncidentInfo(category: _category, status: 'Active'));

  @override
  Stream<HelpState> watchOptions(String incidentId) =>
      Stream<HelpState>.value(const HelpState(loaded: true));
}

Future<void> _pumpSheet(WidgetTester tester, String category) async {
  final db = FakeFirebaseFirestore();
  final ref = db.collection('incidents').doc('INC-1');
  await ref.set({'userId': 'u1', 'category': category, 'status': 'Active'});
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AlertStatusSheet(
          incidentRef: ref,
          repo: _Repo(category),
          dispatch: Stream<DispatchInfo>.value(DispatchInfo.empty),
          createFuture: Future<void>.value(),
          retryCreate: () async {},
          category: category,
          locationShared: false,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('a confirmed Road Accident alert shows the 3 quick questions', (tester) async {
    await _pumpSheet(tester, 'Road Accident');
    final first = kQuestions[kQuickQuestions['Road Accident']!.first]!.prompt;
    expect(find.text('3 QUICK TAPS'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text(first), findsOneWidget);
    await _close(tester);
  });

  testWidgets('answering moves 1 of 3 to 2 of 3 to 3 of 3', (tester) async {
    await _pumpSheet(tester, 'Medical Emergency');
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Yes'));
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Yes'));
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('Skip hides the questions and keeps the alert on screen', (tester) async {
    await _pumpSheet(tester, 'Fire & Rescue');
    await tester.tap(find.text('Skip, help is already coming'));
    await tester.pump();
    expect(find.text('3 QUICK TAPS'), findsNothing);
    expect(find.text('EMERGENCY'), findsOneWidget);
    await _close(tester);
  });
}
