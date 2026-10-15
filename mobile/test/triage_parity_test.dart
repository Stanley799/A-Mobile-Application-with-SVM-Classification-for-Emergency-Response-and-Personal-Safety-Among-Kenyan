// The app's lookup must give the SAME priority as the Python system for every stored case.
// Needs test/assets/decision_table.json and test/assets/test_vectors.json (see README). Run:  flutter test
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/triage/triage_lookup.dart';
import 'package:mobile/core/triage/triage_schema.dart';

void main() {
  test('Dart lookup equals Python for every stored case', () {
    final table =
        jsonDecode(File('test/assets/decision_table.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(table['schema_version'], kTriageSchemaVersion);
    final lookup = TriageLookup.fromEntriesForTest(
      table['entries'] as Map<String, dynamic>,
    );
    final vectors =
        (jsonDecode(File('test/assets/test_vectors.json').readAsStringSync())
                as Map<String, dynamic>)['vectors']
            as List;
    var bad = 0;
    for (final v in vectors) {
      final r = lookup.lookupSafe(
        v['category'] as String,
        Map<String, String>.from(v['answers'] as Map),
        subtype: v['subtype'] as String?,
      );
      if (r.priority != v['expected_priority'] ||
          r.needsHumanReview != v['expected_review']) {
        bad++;
      }
    }
    expect(bad, 0, reason: '$bad of ${vectors.length} cases differ from Python');
  });

  test('bad input fails safe to High + human review', () {
    final lookup = TriageLookup.fromEntriesForTest({});
    final r = lookup.lookupSafe('Nonsense', {});
    expect(r.priority, 'High');
    expect(r.needsHumanReview, true);
  });

  test('subtype floors are applied by the app', () {
    // Sexual violence is never below Medium, mental health crisis is always High.
    expect(kSubtypeFloors['sexual_violence'], 'Medium');
    expect(kSubtypeFloors['mental_health_crisis'], 'High');
  });
}
