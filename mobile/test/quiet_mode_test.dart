import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/resident/map/help_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/quiet_mode.dart';
import 'package:mobile/features/resident/status/alert_status_body.dart';

class _FakeRepo extends HelpRepository {
  _FakeRepo() : super(db: FakeFirebaseFirestore());

  @override
  Stream<IncidentInfo> watchIncident(String incidentId) => Stream<IncidentInfo>.value(const IncidentInfo(category: 'Medical Emergency', status: 'Active'));

  @override
  Stream<HelpState> watchOptions(String incidentId) => Stream<HelpState>.value(const HelpState(loaded: true));
}

Widget _host(QuietMode quiet, HelpRepository repo) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AlertStatusBody(
        incidentId: 'INC-1',
        categoryLabel: 'Medical Emergency',
        priorityLabel: 'High',
        reference: 'INC-1',
        receivedAt: DateTime(2026, 10, 29, 10),
        repo: repo,
        quiet: quiet,
        dispatch: Stream<DispatchInfo>.value(const DispatchInfo(state: 'dispatching', escalate922: false, reason: '', units: [])),
      ),
    ),
  ),
);

void main() {
  testWidgets('the quiet switch is on the alert screen and changes the mode', (tester) async {
    final quiet = QuietMode();
    await tester.pumpWidget(_host(quiet, _FakeRepo()));
    await tester.pump();

    expect(find.text("I can't speak or make noise"), findsOneWidget);
    expect(quiet.on, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(quiet.on, isTrue);
    expect(tester.takeException(), isNull);
  });
}
