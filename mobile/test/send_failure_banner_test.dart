import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/widgets/alert_status_sheet.dart';

void main() {
  testWidgets('a failed send shows the exact sentence, a big Call 999, and retries every 5 s', (tester) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('incidents').doc('INC-1');
    final create = Completer<void>();
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertStatusSheet(
            incidentRef: ref,
            repo: HelpRepository(db: db),
            dispatch: Stream<DispatchInfo>.value(DispatchInfo.empty),
            createFuture: create.future,
            retryCreate: () async {
              retries++;
              throw StateError('still offline');
            },
            category: 'SOS',
            locationShared: false,
          ),
        ),
      ),
    );
    create.completeError(StateError('offline'));
    await tester.pump();

    expect(find.text('Your alert has not been sent yet. Call 999 now.'), findsOneWidget);
    expect(find.text('Call 999'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Call 999')).height,
      greaterThanOrEqualTo(48),
      reason: 'the call button must be easy to hit in a panic',
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump();

    expect(retries, 1, reason: 'the screen keeps trying while it is open');
    expect(find.text('Your alert has not been sent yet. Call 999 now.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Try again now retries immediately', (tester) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('incidents').doc('INC-1');
    final create = Completer<void>();
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertStatusSheet(
            incidentRef: ref,
            repo: HelpRepository(db: db),
            dispatch: Stream<DispatchInfo>.value(DispatchInfo.empty),
            createFuture: create.future,
            retryCreate: () async {
              retries++;
              throw StateError('still offline');
            },
            category: 'SOS',
            locationShared: false,
          ),
        ),
      ),
    );
    create.completeError(StateError('offline'));
    await tester.pump();

    await tester.tap(find.text('Try again now'));
    await tester.pump();
    await tester.pump();

    expect(retries, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
