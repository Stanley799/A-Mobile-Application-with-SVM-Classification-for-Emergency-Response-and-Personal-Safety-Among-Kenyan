// 2.4: chat with dispatch — quick replies, the 500-character limit, and a failed send that can be retried.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/responder/job_chat_screen.dart';
import 'package:mobile/features/responder/responder_repository.dart';

class _ChatRepository extends ResponderRepository {
  _ChatRepository()
    : super(
        db: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'responder-1'),
        ),
      );

  final StreamController<List<JobMessage>> messages =
      StreamController<List<JobMessage>>.broadcast();
  final List<String> sent = [];
  bool fail = false;

  @override
  Stream<List<JobMessage>> watchMessages(String incidentId) => messages.stream;

  @override
  Future<void> sendMessage(String incidentId, String text) async {
    if (fail) throw Exception('offline');
    sent.add(text);
  }
}

Future<_ChatRepository> _pump(
  WidgetTester tester, {
  String? systemLine,
}) async {
  final repo = _ChatRepository();
  addTearDown(repo.messages.close);
  await tester.pumpWidget(
    MaterialApp(
      home: JobChatScreen(
        incidentId: 'incident-1',
        repo: repo,
        systemLine: systemLine,
      ),
    ),
  );
  repo.messages.add(const []);
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('quick replies are shown and send their fixed words', (
    tester,
  ) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Scene is safe'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['Scene is safe']);

    final row = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );
    for (final reply in kQuickReplies) {
      await tester.scrollUntilVisible(find.text(reply), 120, scrollable: row);
      expect(find.text(reply), findsOneWidget);
    }
  });

  testWidgets('a message is capped at 500 characters', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'x' * 620);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text.length, 500);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(repo.sent.single.length, 500);
  });

  testWidgets('a failed send shows Retry and the retry goes through', (
    tester,
  ) async {
    final repo = await _pump(tester);
    repo.fail = true;
    await tester.enterText(find.byType(TextField), 'Need directions');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Not sent.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    repo.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['Need directions']);
    expect(find.text('Not sent.'), findsNothing);
  });

  testWidgets('the request-for-units line appears above the thread', (
    tester,
  ) async {
    await _pump(tester, systemLine: 'You asked dispatch for 2 units · Ambulance.');
    expect(
      find.text('You asked dispatch for 2 units · Ambulance.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty thread shows guidance, not another unit name', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.text(
        'No messages yet. Use a quick reply below or write to dispatch.',
      ),
      findsOneWidget,
    );
  });
}
