"""Generates Flutter/Dart constants from schema/triage_schema.json so the app and the model can never drift apart.
Run:  py scripts\\generate_dart.py     Output: dart/triage_schema.dart and dart/triage_lookup.dart  (copy both into lib/core/)"""
import os, json
import triage_core as t
S = t.SCHEMA

def q(s):  # Dart double-quoted string literal
    return json.dumps(s, ensure_ascii=False).replace("$", "\\$")
def lst(xs): return "[" + ", ".join(q(x) for x in xs) + "]"
def mp(d): return "{" + ", ".join(f"{q(k)}: {q(v)}" for k, v in d.items()) + "}"

L = [f"// GENERATED FILE - DO NOT EDIT BY HAND. Source: schema/triage_schema.json (version {S['version']}).",
     "// Regenerate with: py scripts\\generate_dart.py", "",
     f"const String kTriageSchemaVersion = {q(S['version'])};", f"const String kNotAsked = {q(S['not_asked'])};",
     f"const List<String> kPriorities = {lst(S['priorities'])};", f"const List<String> kModelFeatureOrder = {lst(S['model_features'])};",
     f"const List<String> kCategories = {lst(t.CATEGORIES)};", "",
     "class TriageQuestion {", "  final String id; final String type; final String prompt; final List<String> values;",
     "  final Map<String, String> labels; final int min; final int max; final Map<String, List<String>> askIf;",
     "  const TriageQuestion(this.id, this.type, this.prompt, this.values, this.labels, this.min, this.max, this.askIf);", "}", "",
     "const Map<String, TriageQuestion> kQuestions = {"]
for k, v in S["questions"].items():
    ask = "{" + ", ".join(f"{q(a)}: {lst(b)}" for a, b in v.get("ask_if", {}).items()) + "}"
    L.append(f"  {q(k)}: TriageQuestion({q(k)}, {q(v['type'])}, {q(v['prompt'])}, {lst(v.get('values', []))}, {mp(v.get('labels', {}))}, {v.get('min', 0)}, {v.get('max', 0)}, {ask}),")
L += ["};", "", "/// Questions to show for each category, in order. Check askIf before showing each one.", "const Map<String, List<String>> kCategoryQuestions = {"]
L += [f"  {q(c)}: {lst(v['questions'])}," for c, v in S["categories"].items()] + ["};", "", "const Map<String, List<String>> kCategorySubtypes = {"]
L += [f"  {q(c)}: {lst(v['subtypes'])}," for c, v in S["categories"].items()] + ["};", "",
      "class SubtypeRule { final bool confidential; final bool notifyTrustedContactsByDefault; final bool shareFreeTextWithResponder;",
      "  final bool dispatchResponder; final String safetyQuestion;",
      "  const SubtypeRule(this.confidential, this.notifyTrustedContactsByDefault, this.shareFreeTextWithResponder, this.dispatchResponder, this.safetyQuestion); }", "",
      "const Map<String, SubtypeRule> kSubtypeRules = {"]
L += [f"  {q(k)}: SubtypeRule({str(v['confidential']).lower()}, {str(v['notify_trusted_contacts_by_default']).lower()}, {str(v['share_free_text_with_responder']).lower()}, {str(v.get('dispatch_responder', True)).lower()}, {q(v.get('safety_question', ''))})," for k, v in S["subtype_rules"].items()]
L += ["};", "", "class Hotline { final String number; final String name; final String showWhen; final bool verified;", "  const Hotline(this.number, this.name, this.showWhen, this.verified); }", "",
      "/// Only show hotlines where verified is true.", "const List<Hotline> kHotlines = ["]
L += [f"  Hotline({q(h['number'])}, {q(h['name'])}, {q(h['show_when'])}, {str(h['verified']).lower()})," for h in S["hotlines"]]
L += ["];", "", f"const double kOfferTimeoutSeconds = {S['routing']['offer_timeout_seconds']};", f"const int kMaxCardsShown = {S['routing']['max_cards_shown']};", ""]
os.makedirs(os.path.join(t.ROOT, "dart"), exist_ok=True)
open(os.path.join(t.ROOT, "dart", "triage_schema.dart"), "w", encoding="utf-8").write("\n".join(L))

LOOK = f'''// GENERATED FILE - DO NOT EDIT BY HAND (version {S['version']}). Looks up the priority in models/decision_table.json,
// which you add to the app as an asset (pubspec.yaml: assets: - assets/decision_table.json).
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'triage_schema.dart';

class TriageResult {{
  final String priority; final double confidence; final bool needsHumanReview;
  const TriageResult(this.priority, this.confidence, this.needsHumanReview);
}}

class TriageLookup {{
  final Map<String, dynamic> _entries;
  TriageLookup._(this._entries);

  static Future<TriageLookup> load() async {{
    final raw = jsonDecode(await rootBundle.loadString('assets/decision_table.json')) as Map<String, dynamic>;
    if (raw['schema_version'] != kTriageSchemaVersion) {{
      throw StateError('decision_table.json (${{raw['schema_version']}}) does not match the app schema ($kTriageSchemaVersion).');
    }}
    return TriageLookup._(raw['entries'] as Map<String, dynamic>);
  }}

  /// answers: question id -> value as text (people_count as '1'..'5'). Questions not asked for the category are filled with NotAsked.
  TriageResult lookup(String category, Map<String, String> answers) {{
    final parts = <String>[];
    for (final f in kModelFeatureOrder) {{
      if (f == 'category') {{ parts.add(category); continue; }}
      parts.add(answers[f] ?? (f == 'people_count' ? '1' : kNotAsked));
    }}
    final e = _entries[parts.join('|')];
    if (e == null) {{ throw ArgumentError('Unknown answer combination: ${{parts.join('|')}}'); }}
    return TriageResult(e['p'] as String, (e['c'] as num).toDouble(), (e['r'] as num) == 1);
  }}

  /// PRODUCTION entry point. Never throws. On ANY problem (unknown combination, bad input) it fails SAFE:
  /// High priority, flagged for human review. Log [fallbackReason] to Crashlytics/Firestore so it can be investigated.
  /// Over-alerting one case costs seconds; silently under-alerting can cost a life.
  TriageResult lookupSafe(String category, Map<String, String> answers, {{void Function(String reason)? onFallback}}) {{
    try {{
      return lookup(category, answers);
    }} catch (e) {{
      if (onFallback != null) onFallback(e.toString());
      return TriageResult('High', 0.0, true);
    }}
  }}
}}
'''
open(os.path.join(t.ROOT, "dart", "triage_lookup.dart"), "w", encoding="utf-8").write(LOOK)
print("wrote dart/triage_schema.dart and dart/triage_lookup.dart")
