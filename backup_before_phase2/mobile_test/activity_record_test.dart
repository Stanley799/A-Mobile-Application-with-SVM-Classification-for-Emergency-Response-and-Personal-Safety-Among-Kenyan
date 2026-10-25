import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/widgets/activity_record.dart';

void main() {
  group('ActivityRecord.fromIncident', () {
    test('maps Active status to Alert sent (info)', () {
      final record = ActivityRecord.fromIncident('20261015-124107-FIRE-7K3Q', {
        'category': 'Fire & Rescue',
        'status': 'Active',
        'priority': 'High',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 15, 12, 41, 7)),
      });

      expect(record.statusLabel, equals('Alert sent'));
      expect(record.statusTone, equals(StatusTone.info));
      expect(record.priority, equals('High'));
      expect(record.title, equals('Fire & Rescue'));
    });

    test('maps SupportOnly status to Support offered (support)', () {
      final record = ActivityRecord.fromIncident('20261015-124107-SOS-7K3Q', {
        'category': 'Other / General',
        'subtype': 'emotional_distress',
        'status': 'SupportOnly',
        'priority': 'Low',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 15, 12, 41, 7)),
      });

      expect(record.statusLabel, equals('Support offered'));
      expect(record.statusTone, equals(StatusTone.support));
    });

    test('hides confidential subtype in subtitle', () {
      final record = ActivityRecord.fromIncident('20261015-124107-SEC-7K3Q', {
        'category': 'Security Threat',
        'subtype': 'sexual_violence',
        'status': 'Active',
        'priority': 'High',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 15, 12, 41, 7)),
      });

      expect(record.subtitle, isNot(contains('Sexual violence')));
      expect(record.subtitle, contains('Ref 7K3Q'));
    });

    test('pending (non-Timestamp) createdAt uses DateTime.now() and is not 1970', () {
      final record = ActivityRecord.fromIncident('20261015-124107-MED-7K3Q', {
        'category': 'Medical Emergency',
        'status': 'Active',
        'createdAt': null,
      });

      expect(record.createdAt.year, greaterThanOrEqualTo(2026));
    });
  });

  group('ActivityRecord.fromCheckin', () {
    test('maps Checkin statuses correctly', () {
      final recordActive = ActivityRecord.fromCheckin('chk1', {
        'status': 'Active',
        'durationMinutes': 30,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 15, 12, 41, 7)),
      });
      expect(recordActive.statusLabel, equals('In progress'));
      expect(recordActive.statusTone, equals(StatusTone.warning));

      final recordChecked = ActivityRecord.fromCheckin('chk2', {
        'status': 'CheckedIn',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 15, 12, 41, 7)),
      });
      expect(recordChecked.statusLabel, equals('Checked in'));
      expect(recordChecked.statusTone, equals(StatusTone.success));
    });
  });
}
