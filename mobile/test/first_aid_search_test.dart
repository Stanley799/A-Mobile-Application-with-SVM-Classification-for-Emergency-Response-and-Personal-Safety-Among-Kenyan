import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/first_aid/first_aid_search.dart';
import 'package:mobile/features/resident/first_aid/first_aid_screen.dart';

import 'first_aid_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalog = approvedFirstAidCatalog();
  final search = FirstAidSearch.keywordsOnly();

  group('keyword finder', () {
    test('English keywords find CPR and flag the threat', () async {
      final result = await search.find('he is not breathing', catalog.visibleGuides);
      expect(result.immediateThreat, isTrue);
      expect(result.suggestions.first.id, 'cpr_adult');
      expect(result.suggestions.length, lessThanOrEqualTo(3));
    });

    test('Kiswahili keywords find the bleeding guide in Swahili', () async {
      final result = await search.find('ana damu nyingi', catalog.visibleGuides);
      expect(result.immediateThreat, isTrue);
      expect(result.suggestions.first.id, 'bleeding_severe');
    });

    test('Kiswahili suicide words flag the threat and find emotional support', () async {
      final result = await search.find('nataka kufa', catalog.visibleGuides);
      expect(result.immediateThreat, isTrue);
      expect(result.suggestions.first.id, 'emotional_support');
    });

    test('a Kiswahili/Sheng phrase taken from the existing lexicon finds the choking guide', () async {
      // "chakula kimekwama kooni" is a term in ml/schema/lexicon_user.json (read-only).
      final result = await search.find('chakula kimekwama kooni', catalog.visibleGuides);
      expect(result.suggestions.first.id, 'choking_adult');
    });

    test('an ordinary description is not an immediate threat', () async {
      final result = await search.find('my child has a small burn', catalog.visibleGuides);
      expect(result.immediateThreat, isFalse);
      expect(result.suggestions.first.id, 'burns');
    });

    test('no match returns nothing instead of a guess', () async {
      final result = await search.find('banana', catalog.visibleGuides);
      expect(result.immediateThreat, isFalse);
      expect(result.suggestions, isEmpty);
    });

    test('never returns more than three suggestions', () async {
      final guides = [for (var i = 0; i < 5; i++) catalog.guideById('cpr_adult')!];
      final result = await search.find('not breathing', guides);
      expect(result.suggestions.length, 3);
    });

    test('punctuation and case do not change the match', () async {
      final result = await search.find('NOT BREATHING!!', catalog.visibleGuides);
      expect(result.immediateThreat, isTrue);
      expect(result.suggestions.first.id, 'cpr_adult');
    });

    test('the default engine loader does not throw', () async {
      final defaultSearch = FirstAidSearch();
      final result = await defaultSearch.find('damu nyingi', catalog.visibleGuides);
      expect(result.immediateThreat, isTrue);
      expect(result.suggestions, isNotEmpty);
    });
  });

  Widget host() => MaterialApp(
    home: FirstAidScreen(
      catalog: approvedFirstAidCatalog(),
      search: FirstAidSearch.keywordsOnly(),
    ),
  );

  testWidgets('an immediate threat puts the call panel above the suggestions', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('first_aid_search')), 'not breathing');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Is this what you mean?'), findsOneWidget);
    expect(find.text('Adult not breathing (CPR)'), findsOneWidget);
    expect(find.byKey(const ValueKey('first_aid_emergency_call_panel')), findsOneWidget);

    final panelTop = tester.getTopLeft(find.byKey(const ValueKey('first_aid_emergency_call_panel'))).dy;
    final guideTop = tester.getTopLeft(find.text('Adult not breathing (CPR)')).dy;
    expect(panelTop, lessThan(guideTop));
  });

  testWidgets('no match keeps the category picker and says so', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('first_aid_search')), 'banana');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('What is the emergency?'), findsOneWidget);
    expect(
      find.text('We could not find a guide for that. Choose what is happening from the list.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('first_aid_category_Medical Emergency')), findsOneWidget);
    expect(find.text('Is this what you mean?'), findsNothing);
  });

  testWidgets('a Swahili search finds a guide in Swahili', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('first_aid_language_sw')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('first_aid_search')), 'damu nyingi');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Je, unamaanisha hii?'), findsOneWidget);
    expect(find.text('Kutoka damu nyingi'), findsOneWidget);
    expect(find.byKey(const ValueKey('first_aid_emergency_call_panel')), findsOneWidget);
  });
}
