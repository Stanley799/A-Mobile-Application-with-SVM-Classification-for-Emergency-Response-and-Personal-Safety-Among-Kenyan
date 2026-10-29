import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/responder/responder_labels.dart';
import 'package:mobile/features/responder/responder_widgets.dart';

void main() {
  test('every responder capability has a human label', () {
    for (final entry in ResponderLabels.capabilities.entries) {
      final label = ResponderLabels.capability(entry.key);
      expect(label, entry.value);
      expect(label, isNot(contains('_')));
    }
  });

  test('offer statuses and categories are presented in plain words', () {
    expect(ResponderLabels.offerStatus('offered'), 'Waiting for you');
    expect(ResponderLabels.offerStatus('accepted'), 'You accepted');
    expect(ResponderLabels.offerStatus('withdrawn', withdrawReason: 'another_unit_accepted'), 'Taken by another unit');
    expect(ResponderLabels.offerStatus('expired'), 'Expired');
    expect(ResponderLabels.category('Road Accident'), 'Road accident');
    expect(ResponderLabels.offerStatus('unknown_status'), 'Status unavailable');
  });

  testWidgets('priority tag uses a visible word and not an enum key', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PriorityTag(priority: 'High'))));
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('high_priority'), findsNothing);
  });
}
