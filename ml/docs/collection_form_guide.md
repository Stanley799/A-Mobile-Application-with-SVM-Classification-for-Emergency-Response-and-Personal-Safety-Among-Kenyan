# The best way to collect the messages: a form, not typing

**Why a form.** Each classmate types their own messages. You do not retype anything (no transcription mistakes), consent is
recorded with a time stamp, nobody's name is stored, and the labels come automatically from the scenario. You only do 5 things:
build the form once, share it, download the CSV, run 2 commands, read the result.

## Step 1. Build the form (about 20 minutes)
Use Google Forms or Microsoft Forms (whichever your classmates already use).

**Settings (important for privacy)**
- Do NOT collect e-mail addresses. Do NOT require sign-in. Turn off "record name" (Microsoft) / "collect email addresses" (Google).
- Allow any number of responses; people answer once only because each has one personal code.

**Section 1: Information and consent** (use the wording in `message_collection_guide.md`, add: *"Please do not write real names,
phone numbers or places that identify anyone. Skip any scenario you do not want to answer. If a scenario is upsetting, stop. In an
emergency call 922; for gender-based violence call 1195."*)
1. Consent, required, a single checkbox/choice: `I have read the information above and I agree to take part`   (the title MUST contain the word "agree" or "consent")
2. `Your code (given to you on a slip)`   short answer, required   (title MUST contain "code")
3. `Main language you write in`   dropdown, required: **English, Kiswahili, Sheng, Mixed**   (title MUST contain "language")

**Section 2: The scenarios.** Paste the 30 titles from `docs/form_questions.txt`, one *long-answer* question each. Do not
rename them: each title must start with its scenario id (S01, S02 ...). Add this instruction at the top of the section:
> *Write the message exactly as you would type it to an emergency app, in a hurry, in the language you normally use. Do NOT copy
> the words of the scenario. Typos, short forms and mixed languages are welcome.*

## Step 2. Prepare contributor codes
Make a list C01, C02, C03 ... C40. Give each person **one code, once** (by WhatsApp or on a slip). Keep the list of who got which
code ONLY if you need to withdraw someone; keep it separate from the data and delete it when the project ends.
The code is what keeps one person's messages together, so the exam really is "unseen people".

## Step 3. Who and how many
- Minimum useful: about 40 messages. Good: 150 to 300 messages from 20 or more people (each answering at least 12 scenarios).
- At least 8 people who normally write **Kiswahili or Sheng**, because that is the part your lexicon must be tested on.
- Mix of ages, courses and home areas if you can. Do not coach anyone on which words to use.

## Step 4. Import and split (2 commands)
1. In the form: Responses, Download as CSV (Google: Responses > the three dots > Download responses).
2. From `C:\EmergencyResponseSystem\ml`:
```
py scripts\import_form_export.py "C:\path\to\Form responses.csv"
py scripts\split_collected_messages.py
```
The first adds rows to `data\collected_master.csv` (re-running it later is safe, it skips rows already imported). The second
checks consent, phone numbers, length and labels again, then writes the training file and the exam file split BY PERSON.
Fix anything it prints as NOTE, then run the second command again. If it says the target files already have data, add `--force`
only when you are sure.

## Step 5. Improve the lexicon ONLY from the training people, then take the exam once
1. Open `data\text_training_user.csv`. For messages the system cannot place, add the missing words to `schema\lexicon_user.json`
   (then `py scripts\check_lexicon.py`). **Do not open `real_messages.csv` yet**: the exam must stay unseen.
2. `py scripts\train_text_classifier.py`
3. `py scripts\evaluate_text.py data\real_messages.csv`   <- the honest number. Run it once when you are finished tuning.
4. After the exam you may read the exam errors and fix the lexicon, but then any further score is no longer unseen. Report the first
   score as your result and the improvement as "after error analysis".

## What to write in the report (limitations, stated honestly)
- Scenarios name the situation (for example "house on fire"), so some contributors may echo those words; the instruction
  to write in their own words reduces this but cannot remove it. Real users may be less predictable.
- Contributors are classmates, not the general Kenyan public, so the result shows feasibility, not nationwide accuracy.
- Labels come from the scenario the person was shown, not from an independent judge.

## Privacy checklist
- No e-mail, no names, no phone numbers in the data (the scripts reject phone numbers and e-mails).
- After importing, keep the downloaded CSV only on your own computer; delete the form's responses from the cloud when the
  project is marked.
- Report quotes only anonymised messages.
