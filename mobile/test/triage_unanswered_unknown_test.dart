import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/triage/triage_lookup.dart';
import 'package:mobile/features/resident/widgets/activity_record.dart';

void main() {
  group('unanswered questions count as Unknown (same reading as the server)', () {
    test('quick answers only: Road Accident finds its table entry instead of falling back to High', () {
      final lookup = TriageLookup.fromEntriesForTest({
        // age_group, breathing, severe_bleeding and pregnant were not answered, so they read as Unknown.
        'Road Accident|Unknown|Yes|Unknown|Unknown|NotAsked|Unknown|No|No|NotAsked|NotAsked|1': {'p': 'Medium', 'c': 0.809, 'r': 1},
      });
      String? fallback;
      final r = lookup.lookupSafe(
        'Road Accident',
        {'conscious': 'Yes', 'trapped': 'No', 'hazard': 'No'},
        onFallback: (why) => fallback = why,
      );
      expect(fallback, isNull);
      expect(r.priority, 'Medium');
      expect(r.confidence, closeTo(0.809, 1e-9));
    });

    test('a child is not asked the pregnancy question, so it stays NotAsked', () {
      final lookup = TriageLookup.fromEntriesForTest({
        'Road Accident|Child|Yes|Unknown|Unknown|NotAsked|NotAsked|No|No|NotAsked|NotAsked|1': {'p': 'Low', 'c': 0.9, 'r': 0},
      });
      final r = lookup.lookupSafe('Road Accident', {'age_group': 'Child', 'conscious': 'Yes', 'trapped': 'No', 'hazard': 'No'});
      expect(r.priority, 'Low');
    });

    test('people_count is read from the answers', () {
      final lookup = TriageLookup.fromEntriesForTest({
        'Fire & Rescue|Unknown|Unknown|Unknown|NotAsked|NotAsked|NotAsked|Unknown|Unknown|NotAsked|NotAsked|3': {'p': 'High', 'c': 1.0, 'r': 0},
      });
      final r = lookup.lookupSafe('Fire & Rescue', {'people_count': '3'});
      expect(r.priority, 'High');
      expect(r.confidence, 1.0);
    });

    test('a combination that really is missing still fails SAFE to High', () {
      final lookup = TriageLookup.fromEntriesForTest({});
      String? fallback;
      final r = lookup.lookupSafe('Road Accident', {'conscious': 'Yes'}, onFallback: (why) => fallback = why);
      expect(r.priority, 'High');
      expect(r.confidence, 0.0);
      expect(r.needsHumanReview, isTrue);
      expect(fallback, isNotNull);
    });

    test('an unknown category fails SAFE to High', () {
      final lookup = TriageLookup.fromEntriesForTest({});
      expect(lookup.lookupSafe('Nonsense', {}).priority, 'High');
    });
  });

  group('resident history shows the server decision', () {
    Map<String, dynamic> incident({Object? dispatch}) => {
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, 2, 10, 34)),
          'category': 'Road Accident',
          'status': 'Active',
          'priority': 'High',
          'triageStatus': 'complete',
          'dispatch': ?dispatch,
        };

    test('dispatch.priority wins over the phone value', () {
      final r = ActivityRecord.fromIncident('20261102-103408-RTA-ABCD', incident(dispatch: {'priority': 'Medium'}));
      expect(r.priority, 'Medium');
    });

    test('without a dispatch decision the phone value is used', () {
      final r = ActivityRecord.fromIncident('20261102-103408-RTA-ABCD', incident());
      expect(r.priority, 'High');
    });
  });
}
