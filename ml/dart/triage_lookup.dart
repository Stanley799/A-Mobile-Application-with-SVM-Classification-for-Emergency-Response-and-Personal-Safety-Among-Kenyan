// GENERATED FILE - DO NOT EDIT BY HAND (version 3.0.0). Looks up the priority in models/decision_table.json,
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

  static Future<TriageLookup> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/decision_table.json')) as Map<String, dynamic>;
    if (raw['schema_version'] != kTriageSchemaVersion) {
      throw StateError('decision_table.json (${raw['schema_version']}) does not match the app schema ($kTriageSchemaVersion).');
    }
    return TriageLookup._(raw['entries'] as Map<String, dynamic>);
  }

  /// answers: question id -> value as text (people_count as '1'..'5'). Questions not asked for the category are filled with NotAsked.
  TriageResult lookup(String category, Map<String, String> answers) {
    final parts = <String>[];
    for (final f in kModelFeatureOrder) {
      if (f == 'category') { parts.add(category); continue; }
      parts.add(answers[f] ?? (f == 'people_count' ? '1' : kNotAsked));
    }
    final e = _entries[parts.join('|')];
    if (e == null) { throw ArgumentError('Unknown answer combination: ${parts.join('|')}'); }
    return TriageResult(e['p'] as String, (e['c'] as num).toDouble(), (e['r'] as num) == 1);
  }
}
