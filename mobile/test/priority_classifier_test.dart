import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/emergency_enums.dart';
import 'package:mobile/core/models/incident.dart';
import 'package:mobile/core/services/priority_classifier.dart';

void main() {
  test(
    'incident serializes triage selections into Firestore-compatible values',
    () {
      final incident = Incident(
        incidentId: 'incident',
        reporterId: 'resident',
        activationPath: ActivationPath.categorySelection.label,
        category: EmergencyCategory.medical,
        priority: PriorityLevel.medium,
        classifierConfidence: 0.7,
        triageAnswers: const {
          'conscious': ConsciousnessStatus.yes,
          'breathing': BreathingStatus.unknown,
          'trapped': MobilityStatus.trapped,
          'severeBleeding': null,
          'chestPain': false,
          'peopleCount': 2,
        },
        status: IncidentStatus.newStatus,
        createdAt: DateTime(2026, 10, 8),
        updatedAt: DateTime(2026, 10, 8),
      );
      expect(incident.toFirestore()['triageAnswers'], {
        'conscious': 'Yes',
        'breathing': 'Unknown',
        'trapped': 'Trapped',
        'severeBleeding': null,
        'chestPain': false,
        'peopleCount': 2,
      });
      expect(incident.triageAnswers['conscious'], ConsciousnessStatus.yes);
    },
  );

  group('RuleBasedPriorityClassifier', () {
    test('returns high priority for unconscious patients', () async {
      final classifier = RuleBasedPriorityClassifier();

      final suggestion = await classifier.suggestPriority(
        category: EmergencyCategory.medical,
        conscious: ConsciousnessStatus.no,
        breathing: BreathingStatus.yes,
        mobile: MobilityStatus.mobile,
        weaponInvolved: false,
        peopleCount: 1,
      );

      expect(suggestion.priority, PriorityLevel.high);
      expect(suggestion.confidence, greaterThanOrEqualTo(0.95));
    });

    test('recognizes trapped road accident as high priority', () async {
      final classifier = RuleBasedPriorityClassifier();

      final suggestion = await classifier.suggestPriority(
        category: EmergencyCategory.roadAccident,
        conscious: ConsciousnessStatus.yes,
        breathing: BreathingStatus.yes,
        mobile: MobilityStatus.trapped,
        weaponInvolved: false,
        peopleCount: 1,
      );

      expect(suggestion.priority, PriorityLevel.high);
      expect(suggestion.reason, contains('Trapped'));
    });
  });
}
