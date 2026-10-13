# Safety nets and error handling

Purpose: show, for every way the system can go wrong, how we detect it, what the backup is, and what risk remains.
Honest headline: **no system can promise zero errors.** The design goal is that (1) the dangerous errors are
blocked by rules that do not depend on the model, (2) uncertain cases are handed to a human, and (3) when anything
breaks, the system fails towards *more* help, never less.

## 1. The layers (each one catches what the one before can miss)

| # | Layer | What it protects against | Where |
|---|-------|--------------------------|-------|
| 1 | Strict validation | Typos / impossible answers reaching the model | `triage_core.normalize` |
| 2 | Rule floors F01–F10 | The model being wrong on clear danger signs (e.g. not breathing) | `triage_core.rule_floor` |
| 3 | **Protocol guard** | The SVM *lowering* the protocol's own answer | `build_decision_table.py` |
| 4 | SVM-RBF with safety bias (P(High) ≥ 0.35) | Borderline cases drifting to Medium | `build_decision_table.py` |
| 5 | Monotone repair | A worse answer giving a lower priority | `build_decision_table.py` |
| 6 | Human-review flag | Low-confidence / near-High cases | decision table `r` |
| 7 | Resident confirms | Any text-triage mistake | app flow |
| 8 | 922 always shown, 1195 for GBV | Everything else failing | dispatch logic |
| 9 | **Fail-safe fallback** | Missing/corrupt files, unknown combination, bad input | `suggest_priority_safe`, Dart `lookupSafe` |

## 2. Measured evidence (all 16,740 possible answer combinations, `test_combinations.py`)

| Check | Before guard | After guard |
|-------|--------------|-------------|
| Rule floor broken | 0 | 0 |
| Under-triage versus protocol (any level) | 196 (186 High→Med, 10 Med→Low) | **0** |
| High→Low | 0 | 0 |
| Monotone violations | 0 | 0 |
| Over-triage (table higher than protocol) | 13 | 12 |

Trade-off, stated honestly: with the guard the SVM can only *raise* a priority above the protocol. That is the safe
direction for an emergency app. The SVM's own agreement with the protocol (cross-validated accuracy 0.848, High recall
0.925) is still reported in Chapter 4 as evidence of what it learned, and its value is the extra
escalations and confidence/review signals, not the right to overrule safety rules.

## 3. Failure modes

| Failure | How detected | Backup | Residual risk |
|---------|--------------|--------|---------------|
| Resident gives an invalid answer / unknown category | `normalize` raises | `suggest_priority_safe` → **High + human review** | Over-alert |
| `decision_table.json` missing, corrupt or older than the schema | Load check at start-up | Same fail-safe; reason logged in `fallback_reason` | Over-alert until fixed |
| Answer combination not in table (Dart) | `lookup` throws | `lookupSafe` → High + review + `onFallback` log | Over-alert |
| Model files missing | `_LOAD_ERROR` set (no crash) | Fail-safe | Over-alert |
| Text classifier missing | `CLF is None` | Lexicon + flags still work (tested) | Fewer decided messages; more "please choose" |
| `lexicon_user.json` corrupt | Warning in `LOAD_WARNINGS` | English lexicon and flags still load (tested) | No Swahili until fixed |
| Weird text: empty, huge, emoji, control characters, injection strings | Fuzz test, 1,519 inputs | `triage_text` never raises; asks resident | None found |
| Mistyped safety word (`suicde`, `molestd`) | Typo snap test: 124/129 mistypes caught, 0 false flags | Flag raised | Short words (≤5 letters) and multi-edit typos are missed |
| Idiom hides a real flag (`hakuna wasiwasi … nataka kujiua`) | Test 3 | Flags are read after masking only the idiom span | None found |
| Message mentions fire *and* self-harm | Test 2 | Safety flag wins, ordered self_harm > sexual_violence > domestic_violence | Rare multi-emergency cases rely on resident |
| No responder available | Test 10 | 922 escalation shown | Real-world response time |
| Lexicon names a category/subtype not in schema | Test 5 + `check_lexicon.py` | Build fails visibly | None |
| Text triage misreads a message | Not detectable automatically | Resident **must confirm**; `needs_clarification` when unsure | Resident may confirm wrongly |

## 4. Residual risks we cannot remove (to state in the thesis limitations)

1. **Labels are rule-generated.** The training labels come from our own protocol, so accuracy shows fidelity to the
   protocol, not clinical correctness. A person with emergency-care training should review the weights and floors.
2. **Real-message accuracy is not yet measured.** The English dev set (49 messages, author-written) is optimistic. The
   exam file `real_messages.csv` is what will give the honest number.
3. **No Swahili/Sheng in the learned classifier.** Swahili works only through the user-owned lexicon, so unknown
   words fall back to "ask the resident".
4. **Exact-word dependence.** Beyond the flag typo snap, the lexicon needs the word to be spelled as listed.
5. **Dart code and Firebase runtime are not yet compiled or tested** in this environment.
6. **Hotlines 999/112/116 are unverified** and stay off; only 922 and 1195 are shown.

## 5. How to re-verify at any time

`py scripts\run_all.py` runs all 12 steps. The ones that guard safety are:
step 4 (every combination: 0 floor breaks, 0 under-triage, 0 monotone violations), step 5 (dispatch rules),
step 6 (lexicon lint), step 9 (robustness: fuzz, flags, fallbacks, corrupt files).
Any failure prints `ATTENTION` or `FAIL` and the run log is saved to `docs/run_log.txt`.
