// GENERATED FILE - DO NOT EDIT BY HAND (version 3.1.0). Looks up the priority in models/decision_table.json,
// which you add to the app as an asset (pubspec.yaml: assets: - assets/decision_table.json).
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'triage_schema.dart';

class TriageResult {
  final String priority; final double confidence; final bool needsHumanReview;
  const TriageResult(this.priority, this.confidence, this.needsHumanReview);
}

class TriageLookup {
  final Map<String, dynamic> _entries;
  TriageLookup._(this._entries);

  /// For unit tests only (lets a test supply the table without the Flutter asset bundle).
  factory TriageLookup.fromEntriesForTest(Map<String, dynamic> entries) => TriageLookup._(entries);

  static Future<TriageLookup> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/decision_table.json')) as Map<String, dynamic>;
    if (raw['schema_version'] != kTriageSchemaVersion) {
      throw StateError('decision_table.json (${raw['schema_version']}) does not match the app schema ($kTriageSchemaVersion).');
    }
    return TriageLookup._(raw['entries'] as Map<String, dynamic>);
  }

  /// answers: question id -> value as text (people_count as '1'..'5').
  /// Read exactly like the server (functions/dispatch/core.py filled_answers + triage_core.normalize):
  /// a question that BELONGS to this category but has not been answered yet counts as "Unknown";
  /// only questions this category never asks are NotAsked. (Before: unanswered meant NotAsked, which is not in
  /// the table, so every alert answered with just the 3 quick questions fell back to High.)
  TriageResult lookup(String category, Map<String, String> answers, {String? subtype}) {
    final categoryQuestions = kCategoryQuestions[category];
    if (categoryQuestions == null) { throw ArgumentError('Unknown category: $category'); }
    final byFeature = <String, String>{
      for (final f in kModelFeatureOrder) f: (kQuestions[f]?.type == 'int') ? '1' : kNotAsked,
    };
    for (final q in categoryQuestions) {
      final spec = kQuestions[q]!;
      final given = answers[q];
      if (spec.type == 'int') {
        final n = int.tryParse(given ?? '');
        byFeature[q] = (n == null ? 1 : (n < spec.min ? spec.min : (n > spec.max ? spec.max : n))).toString();
        continue;
      }
      var asked = true;
      for (final c in spec.askIf.entries) {
        if (!c.value.contains(byFeature[c.key])) { asked = false; }
      }
      if (!asked) continue;
      byFeature[q] = (given != null && spec.values.contains(given)) ? given : 'Unknown';
    }
    byFeature['category'] = category;
    final parts = <String>[for (final f in kModelFeatureOrder) byFeature[f]!];
    final e = _entries[parts.join('|')];
    if (e == null) { throw ArgumentError('Unknown answer combination: ${parts.join('|')}'); }
    var priority = e['p'] as String;
    var review = (e['r'] as num) == 1;
    final floor = subtype == null ? null : kSubtypeFloors[subtype];
    if (floor != null && kPriorities.indexOf(floor) > kPriorities.indexOf(priority)) { priority = floor; }
    if (floor == 'High' || priority == 'High') { review = false; }   // same rule as predict_priority.py
    return TriageResult(priority, (e['c'] as num).toDouble(), review);
  }

  /// PRODUCTION entry point. Never throws. On ANY problem (unknown combination, bad input) it fails SAFE:
  /// High priority, flagged for human review. Log [fallbackReason] to Crashlytics/Firestore so it can be investigated.
  /// Over-alerting one case costs seconds; silently under-alerting can cost a life.
  TriageResult lookupSafe(String category, Map<String, String> answers, {String? subtype, void Function(String reason)? onFallback}) {
    try {
      return lookup(category, answers, subtype: subtype);
    } catch (e) {
      if (onFallback != null) onFallback(e.toString());
      return TriageResult('High', 0.0, true);
    }
  }
}
