// Guards the 3.3 rule: every sentence is human, and nothing internal leaks to the screen.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/resident/map/help_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/status/alert_status_body.dart';
import 'package:mobile/features/resident/widgets/alert_status_sheet.dart';
import 'package:mobile/features/resident/widgets/closure_sheet.dart';

const _rawKeys = {
  'offered', 'accepted', 'enroute', 'arrived', 'completed', 'expired', 'withdrawn', 'declined',
  'needs_review', 'support_only', 'awaiting_details', 'partially_assigned', 'waiting_location',
  'safe_fallback', 'manual_pin', 'yes', 'no', 'unsure', 'live', 'place', 'hotline',
  'asking', 'available', 'unfilled', 'no_location', 'dispatching', 'assigned', 'cancelled',
};

class _FakeRepo extends HelpRepository {
  _FakeRepo({required this.incident, this.help = const HelpState(loaded: true)}) : super(db: FakeFirebaseFirestore());

  final IncidentInfo incident;
  final HelpState help;

  @override
  Stream<IncidentInfo> watchIncident(String incidentId) => Stream<IncidentInfo>.value(incident);

  @override
  Stream<HelpState> watchOptions(String incidentId) => Stream<HelpState>.value(help);

  @override
  Stream<CheckinQuestion?> watchCheckin(String incidentId) => Stream<CheckinQuestion?>.value(null);
}

Widget _host(HelpRepository repo, {bool sending = false, String dispatchState = 'dispatching'}) => MaterialApp(
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
        sending: sending,
        dispatch: Stream<DispatchInfo>.value(DispatchInfo(state: dispatchState, escalate922: false, reason: '', units: const [])),
      ),
    ),
  ),
);

List<String> _texts(WidgetTester tester) => [
  for (final w in tester.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
];

void _expectHuman(List<String> texts) {
  for (final t in texts) {
    expect(t.toLowerCase().contains('calm down'), isFalse, reason: 'never tell a frightened person to calm down: $t');
    expect(_rawKeys.contains(t), isFalse, reason: 'a raw key reached the screen: $t');
    expect(RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)+$').hasMatch(t), isFalse, reason: 'snake_case reached the screen: $t');
  }
}

void main() {
  testWidgets('the alert screen says each status in plain words', (tester) async {
    final accepted = _FakeRepo(
      incident: const IncidentInfo(category: 'Medical Emergency', status: 'Active'),
      help: const HelpState(
        loaded: true,
        options: [HelpOption(rank: 1, kind: 'live', refId: 'r1', name: 'City Ambulance', orgType: 'Ambulance', status: 'accepted', etaMin: 6)],
      ),
    );

    await tester.pumpWidget(_host(accepted, dispatchState: 'assigned'));
    await tester.pump();
    await tester.pump();
    expect(find.text('City Ambulance is coming. About 6 min away.'), findsOneWidget);
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
    final enroute = _FakeRepo(
      incident: const IncidentInfo(category: 'Medical Emergency', status: 'Active'),
      help: const HelpState(
        loaded: true,
        options: [HelpOption(rank: 1, kind: 'live', refId: 'r1', name: 'City Ambulance', orgType: 'Ambulance', status: 'enroute', etaMin: 4)],
      ),
    );
    await tester.pumpWidget(_host(enroute, dispatchState: 'enroute'));
    await tester.pump();
    await tester.pump();
    expect(find.text('City Ambulance is on the way.'), findsOneWidget);
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
    final arrived = _FakeRepo(
      incident: const IncidentInfo(category: 'Medical Emergency', status: 'Active'),
      help: const HelpState(
        loaded: true,
        options: [HelpOption(rank: 1, kind: 'live', refId: 'r1', name: 'City Ambulance', orgType: 'Ambulance', status: 'arrived')],
      ),
    );
    await tester.pumpWidget(_host(arrived, dispatchState: 'arrived'));
    await tester.pump();
    await tester.pump();
    expect(find.text('City Ambulance has arrived.'), findsOneWidget);
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sending, searching, unfilled and cancelled use the fixed wording', (tester) async {
    final idle = _FakeRepo(incident: const IncidentInfo(category: 'Medical Emergency', status: 'Active'));

    await tester.pumpWidget(_host(idle, sending: true));
    await tester.pump();
    expect(find.text('Sending your alert…'), findsOneWidget);
    expect(find.text('We are finding the nearest help.'), findsOneWidget);
    expect(_texts(tester).any((t) => t.startsWith('Received at')), isFalse, reason: 'nothing is received yet');
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(idle));
    await tester.pump();
    await tester.pump();
    expect(find.text("We have your alert. You don't need to do anything else."), findsOneWidget);
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(idle, dispatchState: 'unfilled'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Still looking. If you are in danger, call 999 or 922 now.'), findsOneWidget);
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
    final cancelled = _FakeRepo(incident: const IncidentInfo(category: 'Medical Emergency', status: 'Cancelled'));
    await tester.pumpWidget(_host(cancelled, dispatchState: 'cancelled'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alert cancelled. No help is being sent. Stay safe.'), findsOneWidget);
    _expectHuman(_texts(tester));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the send-failure banner and the closure sheet are human too', (tester) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('incidents').doc('INC-1');
    final create = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AlertStatusSheet(
          incidentRef: ref,
          repo: HelpRepository(db: db),
          dispatch: Stream<DispatchInfo>.value(DispatchInfo.empty),
          createFuture: create.future,
          retryCreate: () async => throw StateError('offline'),
          category: 'SOS',
          locationShared: false,
        ),
      ),
    ));
    create.completeError(StateError('offline'));
    await tester.pump();
    expect(find.text('Your alert has not been sent yet. Call 999 now.'), findsOneWidget);
    _expectHuman(_texts(tester));
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showClosureSheet(context, onSave: (safe, rating) async => true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Are you safe now?'), findsWidgets);
    _expectHuman(_texts(tester));
    await tester.pumpWidget(const SizedBox());
  });
}
