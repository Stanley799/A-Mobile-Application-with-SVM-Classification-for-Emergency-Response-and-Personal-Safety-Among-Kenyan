import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/first_aid/first_aid_category_map.dart';
import 'package:mobile/features/resident/first_aid/first_aid_models.dart';
import 'package:mobile/features/resident/first_aid/first_aid_screen.dart';

import 'first_aid_fixture.dart';

Widget _screen(FirstAidScreen screen) => MaterialApp(home: screen);

List<String> _ids(List<FirstAidGuide> guides) => [for (final g in guides) g.id];

void main() {
  group('alert matching ranks the best guide first', () {
    final catalog = approvedFirstAidCatalog();

    test('a cardiac arrest suggests CPR first', () {
      final guides = firstAidGuidesForIncident(
        catalog.visibleGuides,
        category: 'Medical Emergency',
        subtype: 'cardiac',
      );
      expect(guides.first.id, 'cpr_adult');
    });

    test('a road crash suggests the road-crash guide before general bleeding', () {
      final guides = firstAidGuidesForIncident(
        catalog.visibleGuides,
        category: 'Road Accident',
        subtype: 'crash',
      );
      expect(guides.first.id, 'road_crash');
    });

    test('a building fire suggests fire escape first', () {
      final guides = firstAidGuidesForIncident(
        catalog.visibleGuides,
        category: 'Fire & Rescue',
        subtype: 'building_fire',
      );
      expect(guides.first.id, 'fire_escape');
    });

    test('a security incident with no subtype never suggests the sensitive guides', () {
      final guides = firstAidGuidesForIncident(
        catalog.visibleGuides,
        category: 'Security Threat',
      );
      expect(_ids(guides), contains('violence_safety'));
      for (final id in kFirstAidSensitiveGuideIds) {
        expect(_ids(guides), isNot(contains(id)));
      }
    });

    test('a sexual-violence subtype does reach the sensitive support guide', () {
      final guides = firstAidGuidesForIncident(
        catalog.visibleGuides,
        category: 'Security Threat',
        subtype: 'sexual_violence',
      );
      expect(guides.first.id, 'sexual_violence_support');
    });

    test('an emotional crisis subtype reaches the emotional support guide', () {
      final guides = firstAidGuidesForIncident(
        catalog.visibleGuides,
        category: 'Other / General',
        subtype: 'mental_health_crisis',
      );
      expect(guides.first.id, 'emotional_support');
    });

    test('Abduction has no guide and the matcher never invents one', () {
      expect(
        firstAidGuidesForIncident(catalog.visibleGuides, category: 'Abduction', subtype: 'kidnapping'),
        isEmpty,
      );
    });
  });

  testWidgets('an emergency medical alert asks the yes/no flow and reaches CPR', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Medical Emergency',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();
    expect(
      find.text('Is the person responding when you tap their shoulders and shout?'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('first_aid_flow_no')));
    await tester.pumpAndSettle();
    expect(find.text('Are they breathing normally?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first_aid_flow_no')));
    await tester.pumpAndSettle();
    expect(find.text('Adult not breathing (CPR)'), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsOneWidget);
  });

  testWidgets('the choking branch opens the choking guide, No shows all medical guides', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Medical Emergency',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('first_aid_flow_yes')));
    await tester.pumpAndSettle();
    expect(find.text('Is the person choking or unable to speak?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first_aid_flow_no')));
    await tester.pumpAndSettle();
    expect(find.text('Medical Emergency'), findsOneWidget);
    expect(find.text('Adult not breathing (CPR)'), findsOneWidget);
    expect(find.text('Adult or older child choking'), findsOneWidget);
    expect(find.byKey(const ValueKey('first_aid_choose_different')), findsOneWidget);
  });

  testWidgets('the choking branch Yes opens the choking guide', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Medical Emergency',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first_aid_flow_yes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first_aid_flow_yes')));
    await tester.pumpAndSettle();

    expect(find.text('Adult or older child choking'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
  });

  testWidgets('switching language keeps the step and the flow question', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Medical Emergency',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();
    expect(
      find.text('Is the person responding when you tap their shoulders and shout?'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('first_aid_lang_SW')));
    await tester.pumpAndSettle();
    expect(find.text('Je, mtu anaitikia ukimgusa mabegani na kupiga kelele?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first_aid_lang_EN')));
    await tester.pumpAndSettle();
    expect(
      find.text('Is the person responding when you tap their shoulders and shout?'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('first_aid_flow_no')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first_aid_flow_no')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 6'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first_aid_lang_SW')));
    await tester.pumpAndSettle();
    expect(find.text('Hatua 1 ya 6'), findsOneWidget);
    expect(find.text('Hakikisha mahali ni salama'), findsOneWidget);

    await tester.tap(find.text('Endelea'));
    await tester.pumpAndSettle();
    expect(find.text('Hatua 2 ya 6'), findsOneWidget);

    await tester.tap(find.text('Rudi'));
    await tester.pumpAndSettle();
    expect(find.text('Hatua 1 ya 6'), findsOneWidget);
    expect(find.text('Hakikisha mahali ni salama'), findsOneWidget);
  });

  testWidgets('an alert for another category lists its matches and a different-emergency button', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Road Accident',
      subtype: 'crash',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();

    expect(find.text('First aid for this emergency'), findsOneWidget);
    expect(find.text('Road crash'), findsOneWidget);
    expect(find.byKey(const ValueKey('first_aid_choose_different')), findsOneWidget);
  });

  testWidgets('Abduction says there is no guide and shows the call panel', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Abduction',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();

    expect(find.text('First aid for this emergency'), findsOneWidget);
    expect(
      find.text('There is no guide for this yet. Call 999 or 112 now if someone is in danger.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('first_aid_emergency_call_panel')), findsOneWidget);
  });

  testWidgets('leaving the player returns to the list that opened it', (tester) async {
    await tester.pumpWidget(_screen(FirstAidScreen(
      category: 'Road Accident',
      subtype: 'crash',
      catalog: approvedFirstAidCatalog(),
    )));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Road crash'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first_aid_choose_different')));
    await tester.pumpAndSettle();
    expect(find.text('What is the emergency?'), findsOneWidget);
  });
}
