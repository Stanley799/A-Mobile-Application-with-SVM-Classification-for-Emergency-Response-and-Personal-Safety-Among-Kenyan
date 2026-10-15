"""Phase 1 patch for the ML project. Run ONCE from the ml folder:  py apply_phase1_ml.py
It edits 3 files by exact text replacement and stops with a clear message if anything does not match."""
import io, json, os, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
if "quick_questions" in io.open(os.path.join(ROOT, "schema", "triage_schema.json"), encoding="utf-8").read():
    sys.exit("Already applied: schema/triage_schema.json already has quick_questions. Nothing was changed.")

def edit(rel, pairs):
    path = os.path.join(ROOT, rel)
    text = io.open(path, encoding="utf-8", newline="").read()
    crlf = "\r\n" in text
    text = text.replace("\r\n", "\n")
    for old, new in pairs:
        n = text.count(old)
        if n != 1:
            sys.exit(f"STOP: in {rel} expected exactly 1 match but found {n} for:\n{old[:120]}")
        text = text.replace(old, new)
    if crlf:
        text = text.replace("\n", "\r\n")
    io.open(path, "w", encoding="utf-8", newline="").write(text)
    print("patched", rel)

QUICK = {
    "medical":   ["conscious", "breathing", "severe_bleeding"],
    "road":      ["trapped", "hazard", "conscious"],
    "fire":      ["conscious", "trapped", "breathing"],
    "security":  ["conscious", "breathing", "severe_bleeding"],
    "abduction": ["immediate_danger", "weapon_involved", "age_group"],
    "other":     ["conscious", "breathing", "severe_bleeding"],
}
schema_pairs = [(f'"code": "{code}",', f'"code": "{code}",\n   "quick_questions": {json.dumps(qs)},') for code, qs in QUICK.items()]
schema_pairs += [
    ('''   "id": "999",
   "number": "999",
   "name": "General emergency number",
   "show_when": "none_until_verified",
   "verified": false,
   "source": "NOT VERIFIED in this study. Confirm before enabling."''',
     '''   "id": "999",
   "number": "999",
   "name": "Police and general emergency number (112 also works)",
   "show_when": "always",
   "verified": true,
   "source": "Kenya National Police Service Customer Service Charter (Jan 2025): Hotline 999/112/911. Checked Oct 2026."'''),
    ('''   "id": "112",
   "number": "112",
   "name": "General emergency number",
   "show_when": "none_until_verified",
   "verified": false,
   "source": "NOT VERIFIED in this study. Confirm before enabling."''',
     '''   "id": "112",
   "number": "112",
   "name": "General emergency number",
   "show_when": "never",
   "verified": true,
   "source": "Same charter as 999. Not shown separately because the 999 card already says 112 also works."'''),
    ('''   "id": "116",
   "number": "116",
   "name": "Child helpline",
   "show_when": "none_until_verified",
   "verified": false,
   "source": "NOT VERIFIED in this study. Confirm before enabling."''',
     '''   "id": "116",
   "number": "116",
   "name": "National Child Helpline (free, 24 hours)",
   "show_when": "kidnapping,missing_child",
   "verified": true,
   "source": "Government of Kenya, State Department for Children Services (migecah.go.ke/child-helpline). Checked Oct 2026."'''),
]
edit(os.path.join("schema", "triage_schema.json"), schema_pairs)
json.load(io.open(os.path.join(ROOT, "schema", "triage_schema.json"), encoding="utf-8"))   # must still be valid JSON

edit(os.path.join("scripts", "generate_dart.py"), [(
'''+ ["};", "",
      "class SubtypeRule { final bool confidential;''',
'''+ ["};", "", "/// The 3 questions asked before the alert is refined, in this order (measured: every required responder type is covered).",
      "const Map<String, List<String>> kQuickQuestions = {"] + [f"  {q(c)}: {lst(v['quick_questions'])}," for c, v in S["categories"].items()] + ["};", "",
      "class SubtypeRule { final bool confidential;''')])

edit(os.path.join("scripts", "test_dispatch_logic.py"), [(
'print("\\nALL DISPATCH TESTS PASSED")',
'''# 16. quick questions: at most 3, valid for their category, and EVERY required responder type is still found when only they are answered
for cat, spec in t.SCHEMA["categories"].items():
    qq = spec["quick_questions"]
    assert 1 <= len(qq) <= 3 and len(set(qq)) == len(qq), (cat, qq)
    assert all(q in spec["questions"] and "ask_if" not in t.QUESTIONS[q] for q in qq), (cat, qq)
    enums = {q: "Unknown" for q in spec["questions"] if t.QUESTIONS[q]["type"] == "enum"}
    missed = total = 0
    for full in t.all_combinations(cat):
        part = {"category": cat, **enums, "people_count": 1}
        for q in qq:
            if full[q] != t.NOT_ASKED:
                part[q] = full[q]
        total += 1
        if not set(t.required_capabilities(full)[0]) <= set(t.required_capabilities(t.normalize(part))[0]):
            missed += 1
    print(f"16 quick questions {cat}: {qq} -> first dispatch misses a required responder type in {missed} of {total} combinations")
    assert missed == 0, (cat, missed)
assert [h["number"] for h in t.SCHEMA["hotlines"] if h["verified"] and h["show_when"] == "always"] == ["922", "999"]
print("\\nALL DISPATCH TESTS PASSED")''')])
