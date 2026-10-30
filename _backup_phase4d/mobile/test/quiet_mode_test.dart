import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/resident/map/help_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/quiet_mode.dart';
import 'package:mobile/features/resident/status/alert_status_body.dart';

class _FakeRepo extends HelpRepository {
  _FakeRepo({required this.checkins}) : super(db: FakeFirebaseFirestore());

  final Stream<CheckinQuestion?> checkins;
  final List<(String, String)> replies = [];

  @override
  Stream<IncidentInfo> watchIncident(String incidentId) => Stream<IncidentInfo>.value(const IncidentInfo(category: 'Medical Emergency', status: 'Active'));

  @override
  Stream<HelpState> watchOptions(String incidentId) => Stream<HelpState>.value(const HelpState(loaded: true));

  @override
  Stream<CheckinQuestion?> watchCheckin(String incidentId) => checkins;

  @override
  Future<bool> replyCheckin(String incidentId, String checkinId, String reply) async {
    replies.add((checkinId, reply));
    return true;
  }
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
  testWidgets('quiet mode hides "Not sure" and answers without a haptic tick', (tester) async {
    final platform = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platform.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final controller = StreamController<CheckinQuestion?>();
    final quiet = QuietMode();
    final repo = _FakeRepo(checkins: controller.stream);
    controller.add(const CheckinQuestion(id: 'c1', text: 'Are you somewhere safe?'));

    await tester.pumpWidget(_host(quiet, repo));
    await tester.pump();

    expect(find.text('Not sure'), findsOneWidget, reason: 'a speaking user can still choose it');

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(quiet.on, isTrue);
    expect(find.text('Not sure'), findsNothing, reason: 'quiet mode offers Yes and No only');
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(repo.replies, [('c1', 'yes')]);
    expect(
      platform.where((c) => c.method == 'HapticFeedback.vibrate'),
      isEmpty,
      reason: 'quiet mode must not buzz the phone',
    );

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a normal answer gives the small haptic tick', (tester) async {
    final platform = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platform.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final controller = StreamController<CheckinQuestion?>();
    final repo = _FakeRepo(checkins: controller.stream);
    controller.add(const CheckinQuestion(id: 'c1', text: 'Are you somewhere safe?'));

    await tester.pumpWidget(_host(QuietMode(), repo));
    await tester.pump();

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(platform.where((c) => c.method == 'HapticFeedback.vibrate'), hasLength(1));

    await controller.close();
    await tester.pumpWidget(const SizedBox());
  });
}
