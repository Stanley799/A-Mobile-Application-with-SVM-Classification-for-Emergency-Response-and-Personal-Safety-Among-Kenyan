import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/ops/ops_widgets.dart';

Map<String, dynamic> _incident({required String triage, Map<String, dynamic>? dispatch}) => {
      'category': 'Fire & Rescue',
      'status': 'Active',
      'priority': 'High',
      'prioritySource': 'safe_fallback',
      'triageStatus': triage,
      'dispatch': ?dispatch,
    };

void main() {
  group('resident: DispatchInfo', () {
    test('nothing from the server yet reads as Awaiting details', () {
      final info = DispatchInfo.fromMap(null);
      expect(info.isProvisional, isTrue);
      expect(info.priorityShown, kAwaitingDetails);
    });

    test('the fail-safe High is not shown as High', () {
      final info = DispatchInfo.fromMap({
        'state': 'unfilled',
        'priority': 'High',
        'prioritySource': 'safe_fallback',
        'priorityReasons': ['Alert just received, details not given yet'],
      });
      expect(info.priority, 'High');
      expect(info.isProvisional, isTrue);
      expect(info.priorityShown, 'Awaiting details');
      expect(info.priorityReasons, ['Alert just received, details not given yet']);
    });

    test('a real assessment is shown as it is', () {
      expect(DispatchInfo.fromMap({'priority': 'Medium', 'prioritySource': 'model_table'}).priorityShown, 'Medium');
      expect(DispatchInfo.fromMap({'priority': 'High', 'prioritySource': 'rule_floor'}).priorityShown, 'High');
      expect(DispatchInfo.fromMap({'priority': 'Low', 'prioritySource': 'model_table'}).priorityShown, 'Low');
    });
  });

  group('staff: IncidentRecord', () {
    test('a pending alert keeps priority High for sorting but shows Awaiting details', () {
      final r = IncidentRecord.fromMap('A1', _incident(triage: 'pending', dispatch: {'priority': 'High', 'prioritySource': 'safe_fallback'}));
      expect(r.isUnassessed, isTrue);
      expect(r.priority, 'High');
      expect(r.priorityShown, 'Awaiting details');
    });

    test('an answered alert shows the server decision', () {
      final r = IncidentRecord.fromMap('A2', _incident(triage: 'complete', dispatch: {'priority': 'Medium', 'prioritySource': 'model_table'}));
      expect(r.isUnassessed, isFalse);
      expect(r.priority, 'Medium');
      expect(r.priorityShown, 'Medium');
    });

    test('quick answers are already an assessment', () {
      final r = IncidentRecord.fromMap('A3', _incident(triage: 'quick', dispatch: {'priority': 'High', 'prioritySource': 'model_table'}));
      expect(r.isUnassessed, isFalse);
      expect(r.priorityShown, 'High');
    });
  });

  group('staff: PriorityTag', () {
    Future<void> show(WidgetTester t, String p) => t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: PriorityTag(p)))));

    testWidgets('Awaiting details is a neutral tag with clear words', (t) async {
      await show(t, kAwaitingDetails);
      expect(find.text('AWAITING DETAILS'), findsOneWidget);
      expect(find.text('HIGH'), findsNothing);
    });

    testWidgets('real priorities keep their words', (t) async {
      await show(t, 'Medium');
      expect(find.text('MEDIUM'), findsOneWidget);
    });
  });
}
