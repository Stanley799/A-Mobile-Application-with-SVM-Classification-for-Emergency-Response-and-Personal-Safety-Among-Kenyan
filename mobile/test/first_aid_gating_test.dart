import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/first_aid/first_aid_category_map.dart';
import 'package:mobile/features/resident/first_aid/first_aid_constants.dart';
import 'package:mobile/features/resident/first_aid/first_aid_models.dart';
import 'package:mobile/features/resident/first_aid/first_aid_player.dart';
import 'package:mobile/features/resident/first_aid/first_aid_screen.dart';
import 'package:mobile/features/resident/first_aid/first_aid_search.dart';

import 'first_aid_fixture.dart';

void main() {
  test('the compile-time gate is closed in this build', () {
    expect(kAllowDraftFirstAid, isFalse);
  });

  test('needs_content never becomes visible, even with drafts switched on', () {
    final catalog = realFirstAidCatalog();
    final stubs = catalog.guides.where((g) => g.status == FirstAidGuide.statusNeedsContent);
    expect(stubs, isNotEmpty);
    for (final guide in stubs) {
      expect(guide.isVisibleWith(allowDraft: true), isFalse);
      expect(guide.isVisibleWith(allowDraft: false), isFalse);
    }
  });

  test('drafts show only when the gate is open; approved always shows', () {
    final guide = realFirstAidCatalog().guideById('cpr_adult', visibleOnly: false)!;
    expect(guide.isVisibleWith(allowDraft: false), isFalse);
    expect(guide.isVisibleWith(allowDraft: true), isTrue);

    final json = realFirstAidJson();
    for (final item in json['guides'] as List) {
      final map = item as Map<String, dynamic>;
      if (map['id'] == 'cpr_adult') map['status'] = FirstAidGuide.statusApproved;
    }
    final approved = FirstAidCatalog.fromJson(json).guideById('cpr_adult')!;
    expect(approved.isVisibleWith(allowDraft: false), isTrue);
  });

  test('only approved guides are visible while the gate is closed', () {
    final catalog = realFirstAidCatalog();
    final approved = catalog.guides.where((g) => g.isApproved).toList();
    expect(catalog.visibleGuides.length, approved.length);
    expect(catalog.visibleGuides.every((g) => g.isApproved), isTrue);
    expect(catalog.visibleGuides.every((g) => g.status != FirstAidGuide.statusNeedsContent), isTrue);
    if (approved.isEmpty) {
      expect(firstAidGuidesForCategory(catalog.guides, 'Medical Emergency'), isEmpty);
      expect(
        firstAidGuidesForIncident(catalog.guides, category: 'Medical Emergency', subtype: 'cardiac'),
        isEmpty,
      );
    }
  });

  test('with drafts allowed, the incident matcher still ranks CPR first', () {
    final catalog = realFirstAidCatalog();
    final matches = firstAidGuidesForIncident(
      catalog.guides,
      category: 'Medical Emergency',
      subtype: 'cardiac',
      includeDrafts: true,
    );
    expect(matches.first.id, 'cpr_adult');
  });

  testWidgets('the screen keeps draft titles out with the gate closed', (tester) async {
    final catalog = realFirstAidCatalog();
    await tester.pumpWidget(
      MaterialApp(
        home: FirstAidScreen(
          catalog: catalog,
          search: FirstAidSearch.keywordsOnly(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('first_aid_language_en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first_aid_category_Medical Emergency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all medical guides'));
    await tester.pumpAndSettle();

    expect(find.text('Adult not breathing (CPR)'), findsNothing);
    expect(find.text('Heavy bleeding'), findsNothing);
    if (catalog.visibleGuides.isEmpty) {
      expect(find.textContaining('No first-aid guide has been approved'), findsOneWidget);
    }
  });

  testWidgets('a draft player carries the permanent draft notice', (tester) async {
    final catalog = realFirstAidCatalog();
    final guide = catalog.guideById('cpr_adult', visibleOnly: false)!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstAidPlayer(
            guide: guide,
            catalog: catalog,
            language: FirstAidLanguage.en,
            showDraftBanner: true,
            onChooseDifferent: () {},
            onDone: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('first_aid_draft_banner')), findsOneWidget);
    expect(find.text(catalog.draftNoticeFor(FirstAidLanguage.en)), findsOneWidget);
  });
}
