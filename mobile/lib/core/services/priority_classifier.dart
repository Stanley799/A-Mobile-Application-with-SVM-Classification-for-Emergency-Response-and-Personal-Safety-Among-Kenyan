import '../models/emergency_enums.dart';

/// DTO returned by the classifier to the UI layer.
class PrioritySuggestion {
  final PriorityLevel priority;
  final double confidence;
  final String reason;

  const PrioritySuggestion({
    required this.priority,
    required this.confidence,
    required this.reason,
  });
}

/// Contract every priority classifier must satisfy.
/// The real SVM/RF model can replace the implementation later without changing
/// the UI-facing contract.
abstract class PriorityClassifier {
  Future<PrioritySuggestion> suggestPriority({
    required EmergencyCategory category,
    required ConsciousnessStatus conscious,
    required BreathingStatus breathing,
    required MobilityStatus mobile,
    required bool weaponInvolved,
    required int peopleCount,
    String? freeTextDescription,
  });
}

/// Rule-based stub used until a production ML model is trained.
class RuleBasedPriorityClassifier implements PriorityClassifier {
  @override
  Future<PrioritySuggestion> suggestPriority({
    required EmergencyCategory category,
    required ConsciousnessStatus conscious,
    required BreathingStatus breathing,
    required MobilityStatus mobile,
    required bool weaponInvolved,
    required int peopleCount,
    String? freeTextDescription,
  }) async {
    if (conscious == ConsciousnessStatus.no ||
        breathing == BreathingStatus.no) {
      return const PrioritySuggestion(
        priority: PriorityLevel.high,
        confidence: 0.95,
        reason: 'Unconscious or not breathing',
      );
    }

    if (weaponInvolved) {
      return const PrioritySuggestion(
        priority: PriorityLevel.high,
        confidence: 0.90,
        reason: 'Weapon involved',
      );
    }

    if (mobile == MobilityStatus.trapped &&
        (category == EmergencyCategory.roadAccident ||
            category == EmergencyCategory.fire)) {
      return const PrioritySuggestion(
        priority: PriorityLevel.high,
        confidence: 0.88,
        reason: 'Trapped in accident or fire',
      );
    }

    if (peopleCount >= 3) {
      return const PrioritySuggestion(
        priority: PriorityLevel.medium,
        confidence: 0.75,
        reason: 'Multiple people affected',
      );
    }

    if (category == EmergencyCategory.medical ||
        category == EmergencyCategory.fire) {
      return const PrioritySuggestion(
        priority: PriorityLevel.medium,
        confidence: 0.70,
        reason: 'Category requires attention',
      );
    }

    return const PrioritySuggestion(
      priority: PriorityLevel.low,
      confidence: 0.65,
      reason: 'No immediate life threat detected',
    );
  }
}
