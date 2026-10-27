import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/app_button.dart';
import 'package:mobile/core/ui/feedback.dart';

void main() {
  test('friendlyError never leaks codes or class names', () {
    for (final c in ['invalid-credential', 'weak-password', 'network-request-failed', 'permission-denied', 'some-new-code']) {
      final m = friendlyError(FirebaseException(plugin: 'x', code: c, message: 'raw internal'));
      expect(m, isNot(contains(c)));
      expect(m, isNot(contains('Exception')));
      expect(m.isNotEmpty, isTrue);
    }
    expect(friendlyError(StateError('boom')), 'Something went wrong. Please try again.');
    expect(friendlyError(TimeoutException('x')), contains('too long'));
  });

  testWidgets('AppButton shows a spinner and ignores extra taps while the work runs', (t) async {
    final c = Completer<void>();
    var taps = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AppButton(label: 'Save', onPressed: () { taps++; return c.future; }))));
    await t.tap(find.text('Save'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.byType(AppButton));
    await t.pump();
    expect(taps, 1);
    c.complete();
    await t.pump();
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
