"""Trains the demo text classifier. Training text = English template messages (written by the assistant)
+ every message you add to data/text_training_user.csv (Swahili, Sheng, mixed, real phrasing). Run:  py scripts\\train_text_classifier.py"""
import os, csv, random, joblib
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
import triage_core as t
from text_triage import normalize_text
random.seed(7)
OPEN = ["", "", "please help", "help", "emergency", "pls come fast", "hello", "quick", "urgent"]
PLACE = ["", "", "at Githurai", "near Thika Road", "in Rongai", "along Mombasa Road", "in Kisumu town", "at the market", "near the stage", "in Nakuru", "at Eldoret", "in Kasarani"]
BANK = {
 "Medical Emergency": ["my father collapsed and is not responding", "she is having a seizure", "the baby has a high fever and is shaking", "my wife is in labour and the pain is too much",
   "he was bitten by a snake on the leg", "chest pain and sweating a lot", "he cannot breathe properly", "she drank poison by mistake", "diabetic patient is unconscious",
   "heavy bleeding after delivery", "my son is vomiting blood", "old man fainted at the bus stop", "asthma attack and no inhaler"],
 "Road Accident": ["a matatu has overturned", "boda boda rider was knocked down by a car", "two vehicles collided head on", "lorry hit a pedestrian", "motorbike crash rider is on the road",
   "bus rolled off the road", "car accident people are still inside", "a truck crashed into a shop", "there was a serious road accident"],
 "Fire & Rescue": ["house is on fire", "there is a fire in the market", "building has collapsed people are trapped", "flood waters are rising and we are stuck", "child is drowning in the river",
   "smoke is coming from the roof", "stuck inside a lift", "bush fire is coming towards our homes", "gas cylinder is burning"],
 "Security Threat": ["thieves broke into the house with a panga", "robbers have a gun and are in the compound", "a mob is attacking a man", "looters are breaking shops", "someone has been stabbed",
   "gang is chasing us", "carjackers took my car", "goons are beating people at the stage", "there is shooting nearby", "people invaded the shop with a knife"],
 "Abduction": ["my child was kidnapped", "he was forced into a car by men", "someone abducted my sister", "men took her by force from the road", "my daughter has been taken", "kidnappers called asking for money"],
 "Other / General": ["a hyena entered the compound", "elephant is destroying our farm and people are scared", "I fell from the stairs and my leg hurts", "I am lost and have no phone credit",
   "I have burnt my hand with hot water", "I feel very anxious and panicking", "stranded on the road with a broken down car", "not sure what to do something is wrong", "need advice urgently", "buffalo near the road"],
}
def typo(s):
    out = []
    for w in s.split():
        r = random.random()
        if len(w) > 4 and r < .06: w = w[:2] + w[3:]
        elif len(w) > 4 and r < .10: w = w[:3] + w[2] + w[3:]
        out.append(w)
    return " ".join(out)
X, y = [], []
for cat, phrases in BANK.items():
    for _ in range(300):
        parts = [random.choice(OPEN), random.choice(phrases), random.choice(PLACE)]
        X.append(normalize_text(typo(" ".join(p for p in parts if p)))); y.append(cat)
user_path = os.path.join(t.ROOT, "data", "text_training_user.csv"); n_user = 0
if os.path.exists(user_path):
    for r in csv.DictReader(open(user_path, encoding="utf-8")):
        if r.get("text") and r.get("expected_category") in t.CATEGORIES and r.get("consent_given", "").strip().upper() in ("Y", "YES", "TRUE"):
            for _ in range(5):                                   # your real messages count more than templates
                X.append(normalize_text(r["text"])); y.append(r["expected_category"])
            n_user += 1
clf = make_pipeline(TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 5), sublinear_tf=True), LogisticRegression(C=5, max_iter=2000))
clf.fit(X, y)
joblib.dump(clf, os.path.join(t.ROOT, "models", "text_classifier.joblib"))
print(f"trained text classifier on {len(X)} messages ({n_user} real messages from you x5, rest English templates)")
