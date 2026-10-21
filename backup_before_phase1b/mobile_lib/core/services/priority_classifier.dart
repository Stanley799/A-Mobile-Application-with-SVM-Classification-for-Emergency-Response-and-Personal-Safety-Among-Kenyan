import 'package:flutter/foundation.dart';

import '../triage/triage_lookup.dart';

/// One priority decision, with where it came from.
class PriorityResult {
  const PriorityResult({
    required this.priority,
    required this.confidence,
    required this.needsHumanReview,
    required this.source,
    this.fallbackReason,
  });

  /// Used whenever anything is missing or broken: High and a human looks at it.
  const PriorityResult.failSafe(String reason)
    : priority = 'High',
      confidence = 0,
      needsHumanReview = true,
      source = 'safe_fallback',
      fallbackReason = reason;

  final String priority;
  final double confidence;
  final bool needsHumanReview;
  final String source;
  final String? fallbackReason;
}

/// Looks up the priority in the compiled decision table (assets/decision_table.json).
/// Works fully offline. Never throws: any problem becomes High + human review.
class PriorityClassifier {
  PriorityClassifier._();
  static final PriorityClassifier instance = PriorityClassifier._();

  TriageLookup? _lookup;
  String? _loadError;
  Future<void>? _loading;

  /// Safe to call many times; loads the table once.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _lookup = await TriageLookup.load();
    } catch (e) {
      _loadError = e.toString();
      debugPrint('Triage decision table failed to load: $e');
    }
  }

  PriorityResult classify({
    required String category,
    required Map<String, String> answers,
    String? subtype,
  }) {
    final lookup = _lookup;
    if (lookup == null) {
      return PriorityResult.failSafe(_loadError ?? 'decision table not loaded');
    }
    String? reason;
    final result = lookup.lookupSafe(
      category,
      answers,
      subtype: subtype,
      onFallback: (why) => reason = why,
    );
    return PriorityResult(
      priority: result.priority,
      confidence: result.confidence,
      needsHumanReview: result.needsHumanReview,
      source: reason == null ? 'decision_table' : 'safe_fallback',
      fallbackReason: reason,
    );
  }
}
