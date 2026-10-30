import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/resident/map/help_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/status/alert_status_body.dart';

class _FakeRepo extends HelpRepository {
  _FakeRepo({required this.incident, required this.checkins, required this.help, required this.replies}) : super(db: FakeFirebaseFirestore());

  final IncidentInfo incident;
  final Stream<CheckinQuestion?> checkins;
  final HelpState help;
  final List<(String, String)> replies;

  @override
  Stream<IncidentInfo> watchIncident(String incidentId) => Stream<IncidentInfo>.value(incident);

  @override
  Stream<HelpState> watchOptions(String incidentId) => Stream<HelpState>.value(help);

  @override
  Stream<CheckinQuestion?> watchCheckin(String incidentId) => checkins;

  @override
  Future<bool> replyCheckin(String incidentId, String checkinId, String reply) async {
    replies.add((checkinId, reply));
    return true;
  }
}

Widget _host(HelpRepository repo, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
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
        dispatch: Stream<DispatchInfo>.value(const DispatchInfo(state: 'dispatching', escalate922: false, reason: '', units: [])),
      ),
    ),
  ),
);

void main() {
  testWidgets('a dispatcher question shows, is answered once, then disappears', (tester) async {
    final replies = <(String, String)>[];
    final controller = StreamController<CheckinQuestion?>();
    final repo = _FakeRepo(
      incident: const IncidentInfo(category: 'Medical Emergency', status: 'Active'),
      checkins: controller.stream,
      help: const HelpState(loaded: true),
      replies: replies,
    );
    controller.add(const CheckinQuestion(id: 'c1', text: 'Are you somewhere safe?'));

    await tester.pumpWidget(_host(repo));
    await tester.pump();

    expect(find.text('FROM DISPATCH'), findsOneWidget);
    expect(find.text('Are you somewhere safe?'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Not sure'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(replies, [('c1', 'yes')]);

    controller.add(null);
    await tester.pump();
    expect(find.text('Are you somewhere safe?'), findsNothing);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the check-in card survives 1.3x text', (tester) async {
    final controller = StreamController<CheckinQuestion?>();
    final repo = _FakeRepo(
      incident: const IncidentInfo(category: 'Medical Emergency', status: 'Active'),
      checkins: controller.stream,
      help: const HelpState(loaded: true),
      replies: [],
    );
    controller.add(const CheckinQuestion(id: 'c1', text: 'Are you somewhere safe?'));

    await tester.pumpWidget(_host(repo, scale: 1.3));
    await tester.pump();

    expect(find.text('Are you somewhere safe?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });
}
