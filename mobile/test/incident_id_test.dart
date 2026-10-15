import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/incident_id.dart';

void main() {
  group('newIncidentId', () {
    final pattern = RegExp(r'^\d{8}-\d{6}-(MED|ROAD|FIRE|SEC|ABD|SOS)-[A-HJ-NP-Z2-9]{4}$');

    test('format matches regex for all six categories', () {
      final categories = [
        'Medical Emergency',
        'Road Accident',
        'Fire & Rescue',
        'Security Threat',
        'Abduction',
        'Other / General',
        'Unknown / Fallback Category',
      ];

      for (final cat in categories) {
        final id = newIncidentId(category: cat);
        expect(pattern.hasMatch(id), isTrue, reason: 'Failed for category: $cat, id: $id');
      }
    });

    test('deterministic result with fixed DateTime and seeded Random', () {
      final fixedDate = DateTime(2026, 10, 15, 12, 41, 7);
      final rng1 = Random(1);
      final id1 = newIncidentId(category: 'Fire & Rescue', now: fixedDate, random: rng1);

      final rng2 = Random(1);
      final id2 = newIncidentId(category: 'Fire & Rescue', now: fixedDate, random: rng2);

      expect(id1, equals(id2));
      expect(id1, startsWith('20261015-124107-FIRE-'));
    });

    test('1,000 IDs generated in one second are unique', () {
      final now = DateTime(2026, 10, 15, 12, 41, 7);
      final set = <String>{};
      for (var i = 0; i < 1000; i++) {
        set.add(newIncidentId(category: 'Medical Emergency', now: now, random: Random(i)));
      }
      expect(set.length, equals(1000));
    });

    test('incidentReference extracts last 4 characters correctly', () {
      expect(incidentReference('20261015-124107-FIRE-7K3Q'), equals('7K3Q'));
      expect(incidentReference('abcd-efgh-ijkl-1234'), equals('1234'));
      expect(incidentReference('xyz'), equals('XYZ'));
    });
  });
}
