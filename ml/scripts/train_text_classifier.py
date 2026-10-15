"""Trains the text classifier that SUPPORTS the lexicon (it never decides safety flags; those come from the lexicon only).

Training text =
  1. English / Kenyan-English phrases written by the assistant (about 45 per category, wide variety of wording),
  2. Swahili / Sheng lines built from YOUR lexicon terms in plain frames ('msaada <term>'), no guessing of grammar,
  3. every message in data/text_training_user.csv (counted 5x because it is real language).
An HONEST check is printed first: whole PHRASES are held out, so the score shows how it behaves on wording it never saw
(the old version only ever saw ~10 phrases per category and memorised them).
Run:  py scripts\\train_text_classifier.py"""
import os, csv, random, joblib
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
import triage_core as t
import text_triage as T
from text_triage import normalize_text

SEED = 7
OPEN = ["", "", "", "please help", "help", "emergency", "pls come fast", "hello", "quick", "urgent", "hi we need help", "someone please come"]
PLACE = ["", "", "", "at Githurai", "near Thika Road", "in Rongai", "along Mombasa Road", "in Kisumu town", "at the market", "near the stage", "in Nakuru",
         "at Eldoret", "in Kasarani", "in Kibera", "near the school", "at the junction", "in our compound", "on the highway", "in Mombasa", "at Kawangware"]

BANK = {
 "Medical Emergency": [
  "my father collapsed and is not responding", "she is having a seizure", "the baby has a high fever and is shaking", "my wife is in labour and the pain is too much",
  "he was bitten by a snake on the leg", "chest pain and sweating a lot", "he cannot breathe properly", "she drank poison by mistake", "diabetic patient is unconscious",
  "heavy bleeding after delivery", "my son is vomiting blood", "old man fainted at the bus stop", "asthma attack and no inhaler",
  "my mother has fainted and will not wake up", "the child is burning with fever and having fits", "a man is clutching his chest and cannot speak",
  "she is nine months pregnant and her water has broken", "my grandfather had a stroke and his face is drooping", "he swallowed kerosene", "the baby is blue and not breathing",
  "my brother is diabetic and will not respond", "a boy was bitten by a puff adder", "she has severe diarrhoea and vomiting and is very weak", "he is coughing up blood",
  "my wife is having convulsions", "food is stuck in the baby's throat", "she was stung by bees and her face is swelling", "an electric shock victim is not moving",
  "my father has severe stomach pain and is sweating", "mother has been in labour since morning and there is no transport", "the child is limp and has a very high temperature",
  "he has a deep cut and is bleeding badly", "she is pregnant and bleeding", "my uncle is sick and cannot stand", "a patient has stopped breathing", "he is gasping for air",
  "the toddler drank bleach", "my daughter has an allergic reaction and is swelling up", "he was poisoned at the party and is convulsing", "she keeps fainting and is pale",
  "my husband says his heart is racing and his arm is numb", "the old woman is unconscious on the floor", "baby is not breathing well after birth", "he is very sick and unresponsive"],
 "Road Accident": [
  "a matatu has overturned", "boda boda rider was knocked down by a car", "two vehicles collided head on", "lorry hit a pedestrian", "motorbike crash rider is on the road",
  "bus rolled off the road", "car accident people are still inside", "a truck crashed into a shop", "there was a serious road accident",
  "a car hit a child crossing the road", "the driver is trapped in the car after the crash", "a trailer overturned on the highway", "a bus and a lorry collided",
  "a motorcycle crashed into a pole and the rider is not moving", "a speeding car knocked down two people", "a matatu hit a boda boda and both are on the ground",
  "the vehicle rolled several times and passengers are injured", "a pedestrian was run over at the roundabout", "tuk tuk overturned with passengers", "a bus crash with many injured",
  "a car fell into a ditch with people inside", "a head on collision near the bridge", "a lorry lost its brakes and rammed into cars", "an accident at the junction and people are lying on the road",
  "a school bus has been in an accident", "a taxi crashed into a wall", "the matatu driver lost control and it flipped", "a cyclist was hit by a speeding vehicle",
  "a private car hit a stationary truck", "a car crash on the expressway with injuries", "a boda boda hit a pedestrian and fled", "a vehicle plunged off the bridge",
  "a collision between two matatus", "bus caught in an accident with passengers screaming", "a lorry overturned and spilled its load on the road", "a motorbike and a car collided at the stage",
  "an accident just happened near the petrol station", "a hit and run, the victim is lying on the road", "a car overturned on the roadside", "people are trapped after the crash"],
 "Fire & Rescue": [
  "house is on fire", "there is a fire in the market", "building has collapsed people are trapped", "flood waters are rising and we are stuck", "child is drowning in the river",
  "smoke is coming from the roof", "stuck inside a lift", "bush fire is coming towards our homes", "gas cylinder is burning",
  "the shop next door is burning", "flames are coming out of the building", "a storey building has fallen and workers are buried", "the river burst its banks and people are on the roof",
  "someone fell into a well and cannot get out", "a fire has started in the slum and is spreading fast", "the whole market is burning", "the school dormitory is on fire",
  "a wall has collapsed and someone is under the rubble", "we are surrounded by flood water with children", "a boy is drowning in the dam", "the car is submerged in the flood",
  "an electrical fire in the kitchen", "the petrol station is on fire", "a lorry is burning on the road", "a house caught fire at night and the family is inside",
  "a tent has collapsed on people during the event", "water has filled our house and we cannot get out", "a man is trapped in a pit latrine", "a child is stuck in the borehole",
  "thick smoke from the neighbours house", "fire is spreading to the next building", "the roof has caved in", "a cylinder exploded and the house is burning",
  "landslide has buried houses", "boat capsized and people are in the water", "a person is stuck in the elevator and it is smoking", "forest fire is close to the village",
  "the factory is on fire and workers are inside", "a mattress shop is burning", "the flood has swept away a vehicle with people"],
 "Security Threat": [
  "thieves broke into the house with a panga", "robbers have a gun and are in the compound", "a mob is attacking a man", "looters are breaking shops", "someone has been stabbed",
  "gang is chasing us", "carjackers took my car", "goons are beating people at the stage", "there is shooting nearby", "people invaded the shop with a knife",
  "armed men have entered our estate", "a group of youths robbed me and took my phone", "two men with machetes are attacking a shop owner", "I can hear gunshots outside",
  "a man is threatening people with a knife", "a mob wants to burn a suspected thief", "protesters are looting the supermarket", "burglars are trying to break the door",
  "a gang is attacking travellers on the road", "someone is following me with a weapon", "a man was shot in the leg", "robbery in progress at the shop", "thugs snatched my bag and stabbed my friend",
  "rioters are burning tyres and attacking people", "an armed guard has fired shots at the gate", "a fight broke out and someone has a knife", "bandits attacked our village",
  "a man is beating his wife and threatening her", "teenagers are being attacked by a gang", "they stole my motorbike at gunpoint", "an angry crowd is stoning a man",
  "men with guns are demanding money at the bar", "my neighbour is being attacked by robbers", "attackers have stormed the compound", "I was mugged near the stage",
  "shooting at the shopping centre", "a mob is chasing someone down the street", "criminals broke the shop window and are stealing", "an intruder is inside my house", "a violent riot has broken out in town"],
 "Abduction": [
  "my child was kidnapped", "he was forced into a car by men", "someone abducted my sister", "men took her by force from the road", "my daughter has been taken", "kidnappers called asking for money",
  "a man grabbed a girl and drove off", "my brother was bundled into a vehicle", "strangers took my son from the school gate", "a woman was dragged into a van near the stage",
  "my husband has been abducted and they want a ransom", "a child was snatched at the market", "I saw men forcing someone into a car", "they took our daughter and said they will call",
  "my friend was kidnapped on her way home", "unknown men took my father from the house at night", "a toddler has been carried away by a stranger", "someone is being held against their will",
  "a boy disappeared after getting into a car with a stranger", "my sister was taken at gunpoint", "the kidnappers say they will kill him unless we pay", "a girl was abducted from the bus stage",
  "men in a car grabbed him and sped away", "my niece did not return from school and a stranger was seen with her", "a missing child last seen with an unknown man", "they picked her by force and left in a vehicle",
  "a child is lost at the market and I cannot find her", "my little boy wandered off and is missing", "my daughter is missing since this morning", "the child has been missing for hours and we are searching",
  "a baby was stolen from the hospital", "a woman has been abducted by armed men", "my brother never came home and I think he was taken", "somebody kidnapped my cousin"],
 "Other / General": [
  "a hyena entered the compound", "elephant is destroying our farm and people are scared", "I fell from the stairs and my leg hurts", "I am lost and have no phone credit",
  "I have burnt my hand with hot water", "I feel very anxious and panicking", "stranded on the road with a broken down car", "buffalo near the road",
  "a lion has been seen near the school", "a crocodile is in the river where children play", "I fell from a tree and cannot stand", "I slipped and my arm looks broken",
  "my child spilled boiling water on her arm", "I am lost in the forest and it is getting dark", "a monkey bit the child", "a dog bit me and I am scared",
  "I am heartbroken after my breakup and cannot cope", "I failed my exams and feel very low", "I am so stressed and cannot sleep", "I feel very sad and keep crying",
  "a hippo is near our boat", "I twisted my ankle while hiking and cannot walk", "a stray dog attacked the child", "the wild animals are in the village",
  "my hand was burnt by a hot pan", "I have been crying all night and feel hopeless about my life", "I am overwhelmed and anxious about everything", "my friend is depressed and withdrawn",
  "a snake is inside the house but nobody is bitten", "a leopard is on the roof", "I fell off the roof and my back hurts", "I got lost on the mountain and my phone is dying",
  "I am scared and alone and want someone to talk to", "a bee swarm has attacked the compound", "the buffalo charged at us", "a student is devastated after the results",
  "an elephant is blocking the road and people are afraid"],
}

# --- Swahili / Sheng lines from YOUR lexicon: only plain terms, only trivially safe frames, no grammar guessing -----------------------
FRAMES = ["{t}", "msaada {t}", "tafadhali msaada {t}", "{t} hapa", "{t} haraka", "tafadhali saidia {t}", "{t} tafadhali"]


def lexicon_lines():
    """Plain (non verb-pattern) STRONG terms of each category from the lexicon files, wrapped in the frames above."""
    lines = {c: [] for c in t.CATEGORIES}
    for cat, v in T.LEX["cats"].items():
        for tm in v["strong"]:
            if tm.plain and 2 <= len(tm.plain) <= 40 and tm.plain not in T.LEX["common"]:
                lines[cat].append(tm.plain)
    return lines


def make_sample(phrase, rnd):
    parts = [rnd.choice(OPEN), phrase, rnd.choice(PLACE)]
    return normalize_text(typo(" ".join(p for p in parts if p), rnd))


def typo(s, rnd):
    out = []
    for w in s.split():
        r = rnd.random()
        if len(w) > 4 and r < .06:
            w = w[:2] + w[3:]
        elif len(w) > 4 and r < .10:
            w = w[:3] + w[2] + w[3:]
        out.append(w)
    return " ".join(out)


def build(phrases_by_cat, per_cat, rnd):
    X, y = [], []
    for cat, phrases in phrases_by_cat.items():
        for _ in range(per_cat):
            X.append(make_sample(rnd.choice(phrases), rnd)); y.append(cat)
    return X, y


def new_model():
    return make_pipeline(TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 5), sublinear_tf=True), LogisticRegression(C=5, max_iter=3000))


def main():
    rnd = random.Random(SEED)
    lex = lexicon_lines()
    # ---- honest check: hold out 20% of the PHRASES of every category -------------------------------------------------------------
    train_p, test_p = {}, {}
    for cat, ph in BANK.items():
        ph = ph[:]
        rnd.shuffle(ph)
        k = max(3, len(ph) // 5)
        test_p[cat], train_p[cat] = ph[:k], ph[k:]
    Xtr, ytr = build(train_p, 300, rnd)
    Xte, yte = build(test_p, 60, rnd)
    m = new_model().fit(Xtr, ytr)
    P = m.predict_proba(Xte)
    pred = np.array(m.classes_)[P.argmax(1)]
    conf = P.max(1)
    acc = float((pred == np.array(yte)).mean())
    sure = conf >= 0.55
    print(f"honest check on {len(Xte)} messages built from phrases the model never saw: accuracy {acc:.3f}; "
          f"it is confident (>=0.55) on {sure.mean():.0%} and right on {float((pred[sure] == np.array(yte)[sure]).mean()):.3f} of those")
    # ---- final model on everything ---------------------------------------------------------------------------------------------------
    X, y = build(BANK, 320, rnd)
    n_sw = 0
    for cat, terms in lex.items():
        for term in terms:
            for _ in range(3):
                X.append(normalize_text(rnd.choice(FRAMES).format(t=term))); y.append(cat); n_sw += 1
    user_path = os.path.join(t.ROOT, "data", "text_training_user.csv")
    n_user = 0
    if os.path.exists(user_path):
        for r in csv.DictReader(open(user_path, encoding="utf-8-sig")):
            if r.get("text") and r.get("expected_category") in t.CATEGORIES and r.get("consent_given", "").strip().upper() in ("Y", "YES", "TRUE"):
                for _ in range(5):                                # real messages count more than templates
                    X.append(normalize_text(r["text"])); y.append(r["expected_category"])
                n_user += 1
    clf = new_model().fit(X, y)
    joblib.dump(clf, os.path.join(t.ROOT, "models", "text_classifier.joblib"))
    print(f"trained text classifier on {len(X)} messages ({n_user} real messages from you x5, {n_sw} Swahili/Sheng lines from your lexicon, rest English phrases)")


if __name__ == "__main__":
    main()
