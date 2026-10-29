// The 6.8 report is printed on purpose: mapping table, category gaps and unmapped subtypes.
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/first_aid/first_aid_category_map.dart';
import 'package:mobile/features/resident/first_aid/first_aid_models.dart';

import 'first_aid_fixture.dart';

Iterable<String> _strings(Object? value) sync* {
  if (value is String) {
    yield value;
  } else if (value is List) {
    for (final item in value) {
      yield* _strings(item);
    }
  } else if (value is Map) {
    for (final item in value.values) {
      yield* _strings(item);
    }
  }
}

void main() {
  test('the real pack parses into typed models', () {
    final catalog = realFirstAidCatalog();
    expect(catalog.schemaVersion, 1);
    expect(catalog.contentVersion, isNotEmpty);
    expect(catalog.emergencyNumbers.emergency, containsAll(['999', '112']));
    expect(catalog.guides, hasLength(19));
    expect(catalog.guides.where((g) => g.status == FirstAidGuide.statusDraft), hasLength(13));
    expect(catalog.guides.where((g) => g.status == FirstAidGuide.statusNeedsContent), hasLength(6));

    final ids = catalog.guides.map((g) => g.id).toSet();
    expect(ids, hasLength(catalog.guides.length), reason: 'guide ids are unique');
    for (final guide in catalog.guides) {
      expect(FirstAidGuide.statuses, contains(guide.status));
      expect(guide.id.trim(), isNotEmpty);
      expect(guide.title.isComplete, isTrue, reason: '${guide.id} needs a title in both languages');
    }
  });

  test('every written guide has steps, sources and a banner', () {
    final catalog = realFirstAidCatalog();
    for (final guide in catalog.guides.where((g) => g.status != FirstAidGuide.statusNeedsContent)) {
      expect(guide.steps, isNotEmpty, reason: '${guide.id} has no steps');
      expect(guide.sources, isNotEmpty, reason: '${guide.id} has no source');
      expect(guide.banner, isNotNull, reason: '${guide.id} has no banner');
    }
  });

  test('every step has non-empty English and Kiswahili title and body', () {
    final catalog = realFirstAidCatalog();
    for (final guide in catalog.guides) {
      for (var i = 0; i < guide.steps.length; i++) {
        final step = guide.steps[i];
        expect(step.title.isComplete, isTrue, reason: '${guide.id} step ${i + 1} title');
        expect(step.body.isComplete, isTrue, reason: '${guide.id} step ${i + 1} body');
      }
    }
  });

  test('approved guides carry reviewer metadata', () {
    final catalog = realFirstAidCatalog();
    final approved = catalog.guides.where((g) => g.isApproved).toList();
    for (final guide in approved) {
      expect(guide.reviewedBy, isNotNull, reason: '${guide.id} reviewedBy');
      expect(guide.reviewedAt, isNotNull, reason: '${guide.id} reviewedAt');
      expect(guide.sourceVersion, isNotNull, reason: '${guide.id} sourceVersion');
    }
    // Content-integrity check only: this stays true before and after clinician approval.
    print('FIRST AID CONTENT counts: approved ${approved.length}, '
        'draft ${catalog.guides.where((g) => g.isDraft).length}, '
        'needs_content ${catalog.guides.where((g) => g.status == FirstAidGuide.statusNeedsContent).length}');
  });

  test('every appliesTo value maps to a real triage category', () {
    final catalog = realFirstAidCatalog();
    final used = <String>{};
    for (final guide in catalog.guides) {
      for (final intent in guide.appliesTo) {
        expect(kFirstAidIntentToCategory, contains(intent), reason: '${guide.id} uses $intent');
        used.add(intent);
      }
      for (final subtype in guide.subtypes) {
        expect(kFirstAidSubtypeToRealSubtypes, contains(subtype), reason: '${guide.id} uses $subtype');
      }
    }
    expect(used, kFirstAidIntentToCategory.keys.toSet(), reason: 'the mapping has no dead intent');

    // Printed so the mapping can be checked against the real schema in the report.
    print('FIRST AID MAP intents -> categories');
    for (final entry in kFirstAidIntentToCategory.entries) {
      print('  ${entry.key} -> ${entry.value}');
    }
    print('FIRST AID MAP guide subtypes -> real subtypes');
    for (final entry in kFirstAidSubtypeToRealSubtypes.entries) {
      print('  ${entry.key} -> ${entry.value}');
    }
  });

  test('every flow target exists', () {
    final catalog = realFirstAidCatalog();
    final guideIds = catalog.guides.map((g) => g.id).toSet();
    expect(catalog.flows, contains('medical_start'));
    for (final flow in catalog.flows.values) {
      for (final node in flow.nodes) {
        for (final target in [node.yes, node.no]) {
          if (target == 'pick_topic') continue;
          if (target.startsWith('guide:')) {
            expect(guideIds, contains(target.substring(6)), reason: '${flow.id}/${node.id} -> $target');
          } else {
            expect(flow.node(target), isNotNull, reason: '${flow.id}/${node.id} -> $target');
          }
        }
      }
    }
  });

  test('every real triage category has a guide; gaps are reported', () {
    final catalog = realFirstAidCatalog();
    final gaps = firstAidCategoriesWithoutGuide(catalog.guides);
    final subtypeGaps = firstAidUnmappedRealSubtypes();
    print('FIRST AID CONTENT GAP categories without a guide: $gaps');
    print('FIRST AID CONTENT GAP real subtypes without a direct guide: $subtypeGaps');
    expect(gaps, ['Abduction'], reason: 'Abduction is the known content gap; do not invent a guide');
  });

  test('no guide tells the reader to calm someone down', () {
    // Naming the phrase in a "do not say" instruction is allowed; giving it as advice is not.
    final offenders = <String>[];
    for (final sentence in _strings(realFirstAidJson())) {
      final lower = sentence.toLowerCase();
      if (!lower.contains('calm down')) continue;
      final negated = lower.contains('do not') ||
          lower.contains("don't") ||
          lower.contains('never') ||
          lower.contains('usiseme') ||
          lower.contains('usimwambie');
      if (!negated) offenders.add(sentence);
    }
    expect(offenders, isEmpty);
  });

  test('pulse rates stay between 100 and 120', () {
    final catalog = realFirstAidCatalog();
    var pulses = 0;
    for (final guide in catalog.guides) {
      for (final step in guide.steps) {
        final pulse = step.pulse;
        if (pulse == null) continue;
        pulses++;
        expect(pulse.bpm, inInclusiveRange(100, 120), reason: '${guide.id} pulse');
      }
    }
    expect(pulses, greaterThan(0), reason: 'the CPR guide carries the compression pace');
  });
}
