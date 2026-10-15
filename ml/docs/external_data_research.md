# Can public data replace collecting messages? Research findings (14 Oct 2026)

**Short answer.** Partly. I found no public, labelled collection of *emergency reports in Kenyan Swahili / Sheng* that matches our
six categories, so nothing can fully replace a Swahili/Sheng test set. I did find a large public English set of real
disaster messages that works well as an *independent stress test*, and it already exposed and fixed a real bug.

## What exists (every row checked against its own page; "not stated" means the page did not say)

| Source | What it is | Size | Language | Labels | Access / licence | Fit for us |
|---|---|---|---|---|---|---|
| **Disaster Response Messages (Appen)**, Hugging Face `community-datasets/disaster_response_messages` | Real messages (direct SMS, social posts, news) from disasters, English translation + original | 26,248 rows (card also says "30,000") | English translations of many languages (original kept) | 36 labels incl. medical_help, fire, floods, security, missing_people | Licence shown as "unknown" on the card | **Best available.** Aid-relief domain, not 999-style, but real people's words. Use as external test only |
| **HumAID** (QCRI, ICWSM 2021) | Human-labelled disaster tweets, 19 events 2016-2019 | 77,196 | English only | 11 humanitarian classes (injured/dead, missing, rescue, needs ...) | Released under Twitter terms; event files hold text, combined files hold IDs only | Different labels from ours; no Kenya event (Cyclone Idai only) |
| **Uchaguzi-2022** (Ushahidi, arXiv 2412.13098) | Kenyan citizen reports (SMS, X, USSD/WhatsApp) on the 2022 election | 14,169 labelled | 98% English, 1.3% Swahili (paper gives no Sheng share) | Election topics; Security Issues only 302 (abductions 26, sexual/gender-based violence 3) | Research-only; data request form + agreement; text inclusion not stated | Kenyan, but election domain, tiny security slice |
| **Ma3Route crash reports** (World Bank, 2017-18) | Kenyan transport-crowdsourcing tweets labelled "crash report or not" | records not stated | not stated | crash / not crash | Licensed access, confidentiality declaration; tweet **IDs**, text not stated | Road Accident only; text would need re-fetching from X |
| **RideKE** (arXiv 2502.06180) | Kenyan code-switched tweets (English with Swahili/Sheng) about ride-hailing | 29,623 entries | ~70% English, ~30% Swahili/Sheng | sentiment, emotion (only ~3,200 human-labelled) | Licence not stated; promised on GitHub | Only Sheng-containing set in the Kenya NLP survey; wrong domain, useful for style |
| **AfriSenti (Swahili), MasakhaNEWS, SIB-200, Kencorpus** | Swahili sentiment, news topics, sentences, general text | 3,014 / 6,431 / 1,004 / 2,585 texts | Swahili | sentiment or news topics | not stated in the survey | Not emergencies |
| **Common Swahili Slangs** (Mendeley, 2020) | Slang to standard-word lists | page does not state the count | Swahili | none (a lookup list) | Licence heading present but no name given | Possible vocabulary evidence for YOU to judge; I did not verify its content |
| **Emergency call transcripts** | Bangla999-ECD (simulated Bengali); US 911 open data | n/a | Bengali / English | n/a | n/a | US 911 listings I saw are call-for-service records, not transcripts; I found no real Kenyan transcripts |

The Kenya NLP survey (arXiv 2410.09948) lists no emergency, crisis or disaster message corpus for Swahili or Sheng, which
supports the conclusion that this gap is real. Searches for the Ushahidi 2008 SMS reports found descriptions only, no downloadable dataset.

## What I actually ran (independent test, English)
I tested the current text engine on the 26k-message Appen set (a third-party GitHub copy; HuggingFace was not reachable from my sandbox).

**1. Flags on 25,992 messages: found a real bug in my own work.** The typo-tolerance I added last week turned ordinary words into
rape-related flags: "raging" and "racing" became "raping", "defined" and "defied" became "defiled". Fixed: typo tolerance now
accepts only a missing letter or two swapped neighbouring letters on flag words of 7+ letters, a stop-list blocks "defied", and a test
(4c) guards the common words. Other false flags removed: "suicide bomber/blast/attacker" (news), "we don't want to die". After
the fixes, on the 12,971 direct and social messages there are 8 flags: 3 self-harm, 5 sexual-violence. Reading them: 7 are genuine
mentions ("I want to kill myself", "thinking about committing suicide", "what should we do if we are raped"); 1 is an accepted
false positive ("I don't want to live in the streets"), which I deliberately do not mask because "I don't want to live in this world" is real.
**False flags are about 1 in 13,000 messages. Missed flags cannot be measured here because the set has no flag labels.**

**2. Category fit: modest, as expected.** On 796 messages with one clean label (medical_help / fire / security), the engine decided
24% and was right on 50% of those; the rest were "unclear", so the app would ask the resident. This is NOT the app's accuracy:
the labels describe relief needs (tents, food, medicine), not individual emergencies. It did reveal missing everyday English
(injured, hospital, doctor, medicine ...), now added as weak Medical terms. Do not tune further to this set.

## Recommended solution (no questionnaires)
1. **English (done / repeatable):** keep Appen as the independent external test (`py scripts\evaluate_external.py`). Cite it as an
   external, real-world, out-of-domain check and state its limits above.
2. **Swahili / Sheng:** no public labelled emergency data exists, so the honest design is what you built: a lexicon you own,
   documented sources, 19+ built-in tests, and a clearly stated limitation. Optional low-effort extra: request Uchaguzi-2022 (Ushahidi
   form) for its 302 Kenyan security reports and 26 abduction reports, and use them only to find missing vocabulary.
3. **If a supervisor asks for a Swahili/Sheng accuracy number:** the cheapest valid evidence is a small, clearly labelled
   author-written test set, reported as weaker evidence. A form to a few friends remains the only way to get independent Swahili/Sheng text.
4. **Thesis framing (a strength, not a weakness):** "Kenya NLP datasets exist for sentiment, hate speech, news and elections,
   but none for emergency reports in Swahili or Sheng [survey]; this is why the design is lexicon-first with a safety-first classifier,
   and why the resident always confirms."

## Cautions
- Licences: the Appen card says "unknown"; HumAID follows Twitter terms; Uchaguzi and Ma3Route need agreements. I did not put any
  third-party text into your project; the evaluation script prints examples and saves counts only.
- Verify citations before using them in the report; the NLP survey itself has inconsistent citations (for example RideKE's authors).
- Nothing here validates triage *priority*; that still rests on the protocol and needs a clinician's review.
