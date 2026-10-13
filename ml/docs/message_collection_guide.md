# Collecting real messages: step by step

## What a "real message" is
The exact text a real person would type into the app in an emergency, in the language they really use (Swahili, Sheng, English or a mix).
It is NOT a translation of an English sentence and NOT written by you for them. These messages answer one question: does the text path understand how Kenyans actually write?

## Three files, three jobs (do not mix them)
| File | Job | Who writes it |
|---|---|---|
| `schema/lexicon_user.json` | RULES: the words and patterns that trigger a category or flag | you, from your own knowledge and your training contributors |
| `data/text_training_user.csv` | TEACHING EXAMPLES for the classifier (counted 5 times as much as the English templates) | contributors in the training group |
| `data/real_messages.csv` | the EXAM: never used for training, never used to build the lexicon; gives the accuracy figure for your report | contributors in the exam group |

## The three files in plain words (worked example)

Think of a school.

| File | School comparison | Who fills it | What the system does with it |
|------|-------------------|--------------|------------------------------|
| `schema/lexicon_user.json` | The **rulebook / dictionary**: "if you see *kujiua* it means self-harm" | You, by hand, from your own knowledge of Swahili/Sheng | Reads it directly. Nothing is learned; a rule fires or it does not. |
| `data/text_training_user.csv` | **Practice questions with answers** | You, from messages of the *training* contributors | The text classifier learns patterns from it (counted 5x because it is real language). |
| `data/real_messages.csv` | The **final exam**, sealed until the end | The split script, from the *exam* contributors | Never learned from. Only used to mark the system and print an honest accuracy. |

Why the exam must stay separate: if the system studied the exam answers, a high mark would prove nothing.
That is also why the split is **by person** (a contributor's messages all go to training OR exam) and the lexicon is
built only from training people and then frozen.

### How to record (one master file, then one command)
1. Give each classmate a contributor id (C01, C02 ...). Show them a scenario from `data/collection_scenarios.csv`
   and ask them to write what they would send. Never ask for names, phone numbers or real incidents.
2. Add one row per message to `data/collected_master.csv`:

   `scenario_id,contributor_id,language,text,consent_given,expected_category,expected_flag`

   Example (placeholders, not real data):

   `S07,C03,en,"there is smoke coming from the shop next door",yes,Fire & Rescue,`
   `S01,C04,en,"I do not want to live anymore",yes,Other / General,self_harm`

   Leave `expected_category` empty for genuinely unclear messages. `expected_flag` is only for self_harm,
   sexual_violence or domestic_violence.
3. Run `py scripts\split_collected_messages.py`. It checks consent, phone numbers, length, labels and duplicates,
   then writes the training and exam files for you. You do not edit those two files by hand.
4. Run `py scripts\run_all.py`, then read the exam result in `docs/run_log.txt`.

### How the data helps
- **Finds vocabulary gaps**: every message the system cannot place shows a word your lexicon lacks.
- **Teaches real spelling and style**: SMS shortcuts, mixed English/Swahili, typos.
- **Gives the honest accuracy number** for Chapter 4 (the synthetic and author-written tests are optimistic).
- **Shows the error types** (which wrong, which unclear) so fixes are targeted.
- **Measures how often it falls back to "ask the resident"**, which is the safe outcome, not a failure.
- With under about 30 messages, put all of them in the exam: it is too little to learn from but still gives evidence.

## Steps
1. **Ethics first (see section below). Do not collect before you know the answer.**
2. **Recruit** 8-12 classmates or friends (aim for 60-100 messages in total). Mix of Swahili-dominant, Sheng and English speakers if you can.
3. **Give each person a code** (C01, C02 ...). Keep the list of names and codes on paper or in a separate private file, never in the project folder.
4. **Give each person about 10 scenarios** from `data/collection_scenarios.csv` (mix the groups). Read out the scenario and ask: "Type exactly what you would send to an emergency app. Use your normal language. Do not explain, do not translate."
   - The sensitive scenarios (S25-S27) are OPTIONAL. Say so. Never ask anyone for their own experience; the scenarios are written in the third person.
   - Tell them: no real names, phone numbers or places that identify a person.
5. **Record** each message in `data/collected_master.csv` (Excel or Google Sheets, then Save As **CSV UTF-8**). Columns:
   `scenario_id, contributor_id, language, text, consent_given, expected_category, expected_flag`.
   Leave the last two empty: they are copied from the scenario. `language` is one of `en`, `sw`, `sheng`, `mixed`. `consent_given` is `yes` only if the person agreed.
   A message that is only "help" or very vague keeps the label of its scenario (S23/S24 have none, meaning "should be sent back to the resident").
6. **Check labels once.** If a message does not fit its scenario (the person described something else), change `expected_category` for that row or delete it.
7. **Split**: `py scripts\split_collected_messages.py`. It splits BY PERSON (not by message), refuses rows without consent or with phone numbers/e-mails, removes duplicates and fills the two CSV files.
8. **Build the lexicon from the TRAINING contributors only** (read their messages, add words to `lexicon_user.json`, run `py scripts\check_lexicon.py`). Do NOT open `real_messages.csv` while doing this.
9. **Freeze** the lexicon. Run `py scripts\train_text_classifier.py` then `py scripts\evaluate_text.py data\real_messages.csv`. **Write the numbers down: this is your result.**
10. If you fix things after seeing the exam failures, the exam is "used up". Report the first score honestly and, if you can, collect a few NEW messages from NEW people for a second round.

## How many are enough
With 30 exam messages one mistake is 3.3 percentage points, so report counts ("26 of 30"), not only percentages. Aim for at least 3 exam messages in every category.
If you can only collect about 30 messages in total, put ALL of them in the exam (a measured result is worth more than a slightly better classifier).

## Consent wording (translate it yourself into the language the person prefers)
> I am a Strathmore University student building an emergency-response app as my final-year project. I am asking you to write short messages you might type in an emergency.
> Your name will not be recorded, only a code. The messages will be used only for this project (to test and improve the text-understanding part of the app) and may be quoted anonymously in the report.
> You may skip any scenario and may withdraw before [date]. Please do not include real names, phone numbers or places that identify anyone.
> I agree: ☐ Yes   Code: ______

## Ethics approval (what it means)
Messages written by people are data from human participants. Universities normally need an ethics review before you collect such data.
What was found on Strathmore's own pages (research.strathmore.edu and creates.strathmore.edu/su-irb):
- the committee is the Strathmore University Institutional Scientific and Ethics Review Committee (the pages use SU-ISERC, SU-IERC and SU-IRB for it), accredited by NACOSTI;
- it reviews student proposals, and a subcommittee handles ethics approval for undergraduate, master's and PhD research with minimal risk;
- "ethical approval should be obtained prior to the commencement of any data gathering activities";
- for students it "usually takes place after the defense of their research proposal";
- submissions go through the RHInnO Ethics platform; documents include a participant information sheet and consent form; standard review is about 14 business days and expedited review 4-5 business days (counted from when a reviewer is assigned);
- contact: ethicsreview@strathmore.edu.
I cannot tell you whether YOUR project needs approval or is exempt. Ask Mr. Shabaya in writing this week, and ask the committee whether anonymous, non-sensitive, hypothetical messages need review.
If approval cannot be obtained before your deadline: write the Swahili/Sheng test messages yourself, label them as "author-written" in the report, and state that they are weaker evidence than messages from independent people.

## Data protection (Kenya Data Protection Act, 2019)
From the Act's text: personal data is "any information relating to an identified or identifiable natural person"; consent must be "express, unequivocal, free, specific and informed"; data must be "limited to what is necessary" (s.25(d)); anonymisation means the person is "no longer identifiable".
Practical rules: record a code, never a name; remove phone numbers and identifying places; keep the code-to-name list outside the project and delete it when the project ends; do not publish raw messages that identify anyone. (This is a summary of the Act's wording, not legal advice.)
