import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/responder/responder_widgets.dart';

Offer _offer(Map<String, dynamic> extra) =>
    Offer.fromMap('o1', {'status': 'offered', 'category': 'Fire & Rescue', ...extra});

void main() {
  group('Offer priority source', () {
    test('default High is provisional and says so', () {
      final o = _offer({'priority': 'High', 'prioritySource': 'safe_fallback'});
      expect(o.isProvisional, isTrue);
      expect(o.priority, 'High'); // still High for sorting and colour
      expect(o.priorityLabel, contains('awaiting details'));
      expect(o.priorityBanner, 'HIGH PRIORITY \u00b7 AWAITING DETAILS');
    });

    test('assessed High is not provisional', () {
      final o = _offer({'priority': 'High', 'prioritySource': 'rule_floor'});
      expect(o.isProvisional, isFalse);
      expect(o.priorityLabel, 'High');
      expect(o.priorityBanner, 'HIGH PRIORITY');
    });

    test('older offers without a source make no claim', () {
      final o = _offer({'priority': 'High'});
      expect(o.isProvisional, isFalse);
      expect(o.priorityLabel, 'High');
    });

    test('Medium is never provisional', () {
      final o = _offer({'priority': 'Medium', 'prioritySource': 'model_table'});
      expect(o.isProvisional, isFalse);
      expect(o.priorityBanner, 'MEDIUM PRIORITY');
    });
  });

  group('PriorityTag', () {
    Future<void> show(WidgetTester t, Widget w) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));

    testWidgets('provisional High shows awaiting details', (t) async {
      await show(t, const PriorityTag(priority: 'High', provisional: true));
      expect(find.text('HIGH \u00b7 AWAITING DETAILS'), findsOneWidget);
    });

    testWidgets('assessed High shows plain HIGH', (t) async {
      await show(t, const PriorityTag(priority: 'High'));
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.textContaining('AWAITING'), findsNothing);
    });
  });
}
