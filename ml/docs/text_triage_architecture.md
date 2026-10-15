# Text triage architecture (version 2, schema 3.1.0)

Purpose: turn a short free-text message (English, Swahili, Sheng or mixed) into a SUGGESTED category, subtype and safety flag.
The resident always confirms. When the evidence is mixed the system asks; it never guesses.

## 1. The problem: one word, several meanings
| Word | Meanings | Wrong result with a plain keyword list |
|---|---|---|
| moto | fire / hot | "maji ya moto" (hot water) classed as a fire |
| piga | hit / call / photograph / shout / iron | "mke wangu anapiga simu" classed as domestic violence |
| basi | bus / "then", "enough" | every sentence containing "basi" classed as a road accident |
| kujiua vs kuniua | kill yourself vs kill ME | threat to the speaker routed as self-harm |
| hofu, wasiwasi | normal fear / worry vs a mental-health crisis | an exam worry sent as an always-High crisis |
| anguka | fall / collapse / fail | a faint and a trip are different emergencies |
| damu | blood (road, security and medical messages all mention it) | category flips on one common word |

## 2. Six mechanisms (all in scripts/text_triage.py, all explainable in the report)
1. **Tiers.** Strong terms can decide alone. Weak terms only support, or trigger a question.
2. **One owner.** A strong term belongs to ONE category. `check_lexicon.py` fails if two categories own it.
3. **Longest span wins.** A hit inside a longer hit of another category is dropped ("maji ya moto" removes "moto").
4. **Pairs (who + act within N words).** Domestic violence needs a relative ("mume wangu") AND a hitting verb. A hitting verb alone is only a weak signal.
5. **Verb morphology.** A Swahili verb is SUBJECT + TENSE + OBJECT + ROOT (a-na-ni-piga). One root covers every form, and the object marker carries meaning:
   - `vo:piga` needs me/us (ananipiga, hunipiga, kunipiga): done TO the speaker.
   - `vx:piga` needs any person marker (anampiga) but NOT "anapiga pasi" (iron).
   - `vr:ua` needs the reflexive "ji" (kujiua, anajiua): self. `vo:ua` (kuniua) is a threat to me and goes to Security Threat.
   - `v0:` no object marker (also passives: amepigwa, aligongwa). `v:` optional object marker.
6. **Idiom masks.** "hakuna wasiwasi" (no worries), "piga simu / picha / kelele" are blanked before matching.

Also: common function words (basi, sana, tu, na ...) are automatically demoted to weak; a weak flag only raises a question
when the message is otherwise unclear, EXCEPT possible self-harm which is always kept; weak distress terms can only suggest.

## 3. Decision flow
```
text -> normalise -> mask idioms
  -> safety flags (strong term or pair)  : self_harm > sexual_violence > domestic_violence  -> flag result, resident confirms
  -> category hits (strong/weak, pairs) -> longest span wins
       one category with the most strong hits           -> decided (lexicon, or lexicon+classifier)
       tie between categories                           -> "ambiguous": ask the resident (chips)
       no strong hit, one weak category, classifier agrees (>=0.55) -> decided, medium confidence
       nothing                                          -> classifier if >=0.55, else ask
  -> subtype (most strong hits; tie -> resident chooses; one weak subtype -> low-confidence suggestion)
  -> safety_check = True for emotional_distress or a possible self-harm signal
```
Output fields: category, subtype, subtype_confidence, method, confidence, flags, possible_flags, priority_floor, needs_clarification,
alternatives, safety_check, themes, matched (the exact terms that fired: use them in the audit log), requires_confirmation.

## 4. Mental health: two subtypes, not one
Before: every mental-health word became `mental_health_crisis` = always High, ambulance dispatched. Heartbreak or exam stress would have been over-triaged.
Now:
| Subtype | Meaning | Priority | Responder | Trusted contacts |
|---|---|---|---|---|
| `mental_health_crisis` | self-harm or suicide risk (safety flag, or a Yes to the safety question) | always High, human triage | yes | notified by default |
| `emotional_distress` | heartbreak, stress, grief, worry, low mood with NO self-harm sign | no floor (Low unless answers say otherwise) | NONE (resources only; 922 shown) | NOT notified by default |
The app must ask one question when `safety_check` is True: "Are you thinking of harming yourself?". Yes -> mental_health_crisis.
`themes` (relationship, academic, financial, family, grief, postpartum, substance, bullying) never vote; they only describe the distress so the app can offer relevant support.

### Evidence used (Kenya), by age group
| Group | What was found | Source (read in this study) | Caution |
|---|---|---|---|
| Adolescents 13-19 (Nairobi, n=658) | 45.9% above the PHQ-8 depression cutoff and 38.0% above the GAD-7 anxiety cutoff; older adolescents scored higher; females higher anxiety; social support protective | Osborn et al., 2020, J Child Fam Stud (authors' PDF, scholar.harvard.edu) | screening scores, not diagnoses; the paper's abstract and results bands differ slightly |
| Nairobi secondary-school adolescents | conflict with parents, traumatic experiences, peer pressure, relationship breakdowns, school problems | Richtmann JESR 7716 (abstract) | measures what adolescents are AWARE of as risk factors |
| University students (Pwani University, n=1,424) | 30.9% screened positive; family support protective (AOR 0.47); social media use over 5 hours a day (AOR 2.43); off-campus living (AOR 1.52) | Frontiers in Public Health 2025, doi 10.3389/fpubh.2025.1557058 | purposive sample, one university |
| Young and middle-aged adults 20-39 | about three-quarters of recorded suicide cases; economic hardship, debt, unemployment, alcohol (mainly men), relationship breakdown; for women also domestic violence and caregiving | educationnews.co.ke article | NEWS article quoting unnamed "official estimates": not peer-reviewed, do not cite as primary evidence |
| Mothers (Nairobi, n=171) | postpartum depression 18.7%; conflict with partner OR 7.52; economic stress OR 2.73 | Springer BMC Psychiatry 2018, s12888-018-1904-7 | two clinics, small sample |
| Older adults | NO source found in this study | - | gap: say so in the report |
Not read (blocked): the qualitative study "Perspectives on reasons for suicidal behaviour ... in Kenya" (PMC9970164; PubMed/PMC showed a robot check) and Europe PMC (rate-limited). Read them yourself and cite them.
The app only asks `age_group` (Adult/Child/Unknown), so the age brackets above guide WORDING and THEMES, not the priority.

## 5. Kiswahili terms: what was verified and what was not
Found in Kenyan documents (Kiswahili texts fetched):
- "ya kudhalilisha" = degrading treatment (Constitution of Kenya, Kiswahili text). So **kudhalilisha means to humiliate/degrade**, not specifically to oppress and not specifically sexual. It is therefore WEAK, and strong only next to kingono/ngono/kijinsia.
- "unyanyasaji" and "kutonyanyaswa" = abuse / freedom from abuse (same text). General, so WEAK.
- "Unyanyasaji wa Kijinsia" and the abbreviation "UWAKI" = gender-based violence (Ministry of Gender service charter).
- "Vurugu Nyumbani" = domestic violence (title of the Kiswahili text of the Protection Against Domestic Violence Act, 2015).
- "Unyanyasaji wa Kingono" appears as a Kiswahili fatwa title on dar-alifta.org (an Egyptian site: NOT Kenyan, so it is only a language check).
NOT found in any source I could read: rape terms (ubakaji, kubaka), "kupiga mke", Sheng forms. These rest on your own words and standard usage, and are marked in docs/lexicon_review.csv (`native_check = yes`).
Dictionary sites (Kamusi, TUKI, Wiktionary pages) could not be fetched, so no dictionary entry is quoted here.
For "oppress" the usual words are kuonea, kudhulumu, kukandamiza (NOT verified here); they are in the proposed file only as a bullying theme (kuonea).

## 6. Files
| File | Owner | Loaded by the app? |
|---|---|---|
| schema/lexicon.json | assistant (English) | yes |
| schema/lexicon_user.json | YOU (Swahili/Sheng) | yes |
| schema/lexicon_proposed.json | assistant suggestions awaiting your approval | NO (unless TRIAGE_INCLUDE_PROPOSED=1 for testing) |
| docs/lexicon_review.csv | every term with status, source/note and native_check | no (audit trail) |
| scripts/check_lexicon.py | lint + the built-in tests inside the lexicon files | - |
| scripts/merge_proposed.py | merges approved proposals, with a backup | - |

Status values: USER (you wrote it), USER_ROOT (generalised from your word), USER_FIXED (typo corrected: please confirm),
KENYAN_DOC (found in a Kenyan document), SOURCE (found in another document), GRAMMAR (closed-class grammar such as possessives: please confirm),
IDIOM / GUARD (protects against a wrong match), PROPOSED_HIGH / PROPOSED_MEDIUM (assistant suggestion), REMOVED_OR_MERGED.

## 7. Routine for you
1. Edit schema\lexicon_user.json (lowercase; strong only if the word alone is clear).
2. `py scripts\check_lexicon.py` (must print 0 errors).
3. `py scripts\evaluate_text.py` (English dev set) and, once you have real messages, `py scripts\evaluate_text.py data\real_messages.csv`.
4. Add 3-5 sentences of your own to the `tests` list in the lexicon file for every new group of words.

## 8. Honest limits
- The Swahili path is verified only on the tests written inside the lexicon (written by the assistant from your words). It is NOT measured on real messages.
- Morphology covers common forms (subject, tense, one object marker). It does not cover every dialect form, negatives ("hakuna"), or relative forms.
- The English dev set was tuned by the author: treat the score as a regression check, not accuracy.
- Weights and floors are still not clinician-reviewed.

## Text classifier training, version 2 (14 Oct 2026)
Why: the first version learned from only about 10 phrases per category and effectively memorised them (on its own it was wrong on 10 of 34 test messages).
What changed:
- About 40 varied English / Kenyan-English phrases per category (typos, openers and place names added at random).
- 573 Swahili / Sheng lines built from the owner's own lexicon terms in neutral frames ("msaada <term>", "<term> hapa"); no Swahili grammar is invented.
- An honest check holds out 20% of the *phrases* before training: accuracy 0.83 on wording it never saw; where the model is confident (>= 0.55, 62% of cases) it is right 0.97 of the time.
- Result on the 49-message development set: classifier alone wrong 10 -> 6, combined engine decided 38 -> 42 with 0 wrong, 10/10 safety flags, 0 false flags.
Limits: the development set and the phrases were both written by the assistant, so these numbers are optimistic; the classifier never decides safety flags (lexicon only) and the resident always confirms.
