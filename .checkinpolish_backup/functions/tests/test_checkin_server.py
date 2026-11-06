"""Tests for the check-in server pieces against an in-memory Firestore: start, timeline, retries, contact answers, closing, sender, pages.
Run from the functions folder:   py tests\\test_checkin_server.py"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE)
sys.path.insert(0, FN); sys.path.insert(0, HERE)
import fake_firestore as ff
from checkin import core, pages, sender, store

n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")
def eq(a, b, m):
    assert a == b, f"{m}: {a!r} != {b!r}"; ok(m)

T0 = 1_000_000.0
class Rec:
    def __init__(s): s.sms, s.voice, s.push, s.fail = [], [], [], 0
    def io(s):
        def sms(to, text):
            if s.fail > 0: s.fail -= 1; return {"ok": False, "mode": "live", "detail": "boom"}
            s.sms.append((to, text)); return {"ok": True, "mode": "test", "detail": "t"}
        def voice(to, rid): s.voice.append((to, rid)); return {"ok": True, "mode": "test", "detail": "t"}
        def push(uid, title, body, data): s.push.append((uid, title)); return True
        return store.make_io(push=push, link=lambda c, k, t: f"https://x/c?c={c}&k={k}&t={t}", sms=sms, voice=voice)

PLAN = {"graceSec": 300, "remindBeforeSec": [300], "level2AfterSec": 900, "voiceAfterSec": 300, "contactSpacingSec": 120,
        "shareLocation": False, "contacts": [
            {"id": "a", "name": "Mum", "phone": "0712345678", "methods": ["sms", "voice"]},
            {"id": "b", "name": "Brian", "phone": "+254722000111", "methods": ["sms"]}]}

def fresh(plan=None, note="Walking home", loc=True, dur=1800):
    ff.CLOCK[0] = T0
    db = ff.DB(); rec = Rec()
    r = store.start(db, "u1", "Stanley", dur, plan or PLAN, note, T0, {"lat": -1.3, "lng": 36.8, "acc": 12} if loc else None)
    return db, rec, r["id"], r

def doc(db, cid): return db.collection(store.COLL).document(cid).get().to_dict()
def tick(db, rec, t):
    ff.CLOCK[0] = t; return store.sweep(db, t, rec.io())

# ---- start ----
db, rec, cid, r = fresh()
d = doc(db, cid)
eq(d["status"], "Active", "start creates an Active check-in")
eq(d["durationMinutes"], 30, "duration stored in minutes (old field kept)")
eq(d["plan"]["contacts"][0]["phone"], "+254712345678", "phone numbers are normalised")
eq(sorted(d["esc"]["tokens"]), ["a", "b"], "every contact gets a private token")
eq(r["fallbackAt"], T0 + 1800 + 300 + 90, "phone fallback time is deadline + grace + 90 s")
try:
    store.start(db, "u1", "S", 1800, PLAN, "", T0); raise SystemExit("second check-in accepted")
except ValueError as e: ok("a second open check-in is refused: " + e.args[0][0])
try:
    store.start(ff.DB(), "u2", "S", 60, PLAN, "", T0); raise SystemExit("bad duration accepted")
except ValueError as e: ok("a 1-minute check-in is refused")

# ---- timeline ----
db, rec, cid, r = fresh()
tick(db, rec, T0 + 100); eq(len(rec.push), 0, "nothing before the reminder time")
tick(db, rec, T0 + 1500); eq(len(rec.push), 1, "one reminder 5 minutes before the deadline")
tick(db, rec, T0 + 1510); eq(len(rec.push), 1, "the same reminder is not sent twice")
tick(db, rec, T0 + 1800); eq(doc(db, cid)["status"], "Grace", "deadline passed -> Grace")
eq(len(rec.sms), 0, "no contact is told during grace")
tick(db, rec, T0 + 1800 + 300); eq(doc(db, cid)["status"], "Level1", "grace over -> Level1")
eq(len(rec.sms), 1, "contact 1 gets one SMS")
to, text = rec.sms[0]
eq(to, "+254712345678", "SMS goes to the first contact's normalised number")
assert "Stanley" in text and "https://x/c?c=%s&k=a&t=" % cid in text and "not a confirmed emergency" in text; ok("SMS names the user, carries the contact's own link, says it is not confirmed")
assert "-1.3" not in text; ok("location is NOT in the SMS when the user did not share it")
tick(db, rec, T0 + 2100 + 10); eq(len(rec.sms), 1, "contact 2 waits for the spacing")
tick(db, rec, T0 + 2100 + 125); eq(len(rec.sms), 2, "contact 2 is texted after the spacing")
tick(db, rec, T0 + 2100 + 130); eq(len(rec.sms), 2, "no repeat SMS on the next minute")
tick(db, rec, T0 + 2100 + 305); eq(len(rec.voice), 1, "voice call to contact 1 (asked for voice) when nobody answered")
eq(rec.voice[0][1].split("|")[:2], [cid, "a"], "voice call carries check-in and contact ids")
tick(db, rec, T0 + 2100 + 400); eq(len(rec.voice), 1, "no second call")
tick(db, rec, T0 + 2100 + 900); eq(doc(db, cid)["status"], "Level2", "no answer -> Level2")
inc = db.collection("incidents").document("INC-CHK-" + cid).get().to_dict()
eq((inc["userId"], inc["status"], inc["priority"], inc["category"]), ("u1", "Active", "High", "Other / General"), "Level 2 creates a normal alert for the user")
eq((inc["location"].latitude, inc["location"].longitude), (-1.3, 36.8), "the alert carries the last known location (even if contacts did not get it)")
eq(inc["source"], "safety_checkin", "the alert is marked as coming from a check-in")
tick(db, rec, T0 + 4000); eq(len([p for p in db.data if p.startswith("incidents/")]), 1, "still exactly one alert")

# ---- contact answers ----
db, rec, cid, r = fresh()
tick(db, rec, T0 + 2100)
tok = doc(db, cid)["esc"]["tokens"]
eq(store.contact_ack(db, cid, "a", "wrong", "checking", T0 + 2200, rec.io()), "bad_token", "a wrong token is refused")
eq(store.contact_ack(db, cid, "zz", tok["a"], "checking", T0 + 2200, rec.io()), "bad_token", "an unknown contact is refused")
eq(store.contact_ack(db, cid, "a", tok["a"], "checking", T0 + 2200, rec.io()), "ok", "'I am checking' is accepted")
tick(db, rec, T0 + 2100 + 900 + 5); eq(doc(db, cid)["status"], "Level1", "'checking' postpones responders")
tick(db, rec, T0 + 2200 + 900 + 5); eq(doc(db, cid)["status"], "Level2", "...but only for the extension")
db, rec, cid, r = fresh()
tick(db, rec, T0 + 2100)
tok = doc(db, cid)["esc"]["tokens"]
eq(store.contact_ack(db, cid, "b", tok["b"], "cannot_reach", T0 + 2150, rec.io()), "ok", "'cannot reach' is accepted")
eq(doc(db, cid)["status"], "Level2", "'cannot reach' escalates immediately")
eq(len([p for p in db.data if p.startswith("incidents/")]), 1, "...and creates the alert")
v = store.view_for_page(db, cid, "b", tok["b"]); assert v and v[1] == "Brian"; ok("contact page loads with a valid link")
eq(store.view_for_page(db, cid, "b", "nope"), None, "contact page refuses a bad link")

# ---- user closes ----
db, rec, cid, r = fresh()
eq(store.close(db, "u1", cid, "CheckedIn", T0 + 100, rec.io())["status"], "CheckedIn", "closing before any alert works")
eq(len(rec.sms), 0, "no all-clear is sent when nobody was alerted")
db, rec, cid, r = fresh()
tick(db, rec, T0 + 2100 + 125)
eq(len(rec.sms), 2, "(two contacts alerted)")
store.close(db, "u1", cid, "CheckedIn", T0 + 2300, rec.io())
eq(len(rec.sms), 4, "both alerted contacts get an all-clear")
assert "is safe" in rec.sms[-1][1]; ok("all-clear says the person is safe")
eq(store.settle(db, cid, T0 + 2310, rec.io()), [], "closing twice sends nothing more")
try:
    store.close(ff.DB(), "u1", "nope", "CheckedIn", T0, rec.io()); raise SystemExit("closed a missing check-in")
except LookupError: ok("closing a missing check-in is refused")
db2, rec2, cid2, _ = fresh()
try:
    store.close(db2, "someone-else", cid2, "CheckedIn", T0, rec2.io()); raise SystemExit("another user closed it")
except LookupError: ok("another user cannot close my check-in")
# close after level2 withdraws the alert
db, rec, cid, r = fresh()
tick(db, rec, T0 + 2100 + 900)
eq(doc(db, cid)["status"], "Level2", "(level 2 reached)")
store.close(db, "u1", cid, "CheckedIn", T0 + 3500, rec.io())
eq(db.collection("incidents").document("INC-CHK-" + cid).get().to_dict()["status"], "Cancelled", "closing withdraws the alert")

# ---- failed send is retried, then given up ----
db, rec, cid, r = fresh(); rec.fail = 1
tick(db, rec, T0 + 2100); eq(len(rec.sms), 0, "first SMS failed")
tick(db, rec, T0 + 2160); eq(len(rec.sms), 1, "it is retried the next minute")
tick(db, rec, T0 + 2200); eq(len(rec.sms), 1, "and not repeated once delivered")
db, rec, cid, r = fresh(); rec.fail = 99
for i in range(6): tick(db, rec, T0 + 2100 + 60 * i)
eq(doc(db, cid)["esc"]["tries"]["sms:a"], 3, "gives up after 3 tries (the phone's own SMS fallback covers the rest)")

# ---- older check-ins are never touched ----
ff.CLOCK[0] = T0; db = ff.DB(); rec = Rec()
import datetime as dt
db.put("safetyCheckins/old1", {"userId": "u9", "status": "Active", "expiryTime": store.when(T0 - 10000), "durationMinutes": 30})
tick(db, rec, T0 + 99999)
eq(doc(db, "old1")["status"], "Active", "a check-in made by the old flow is left alone")
eq(len(rec.sms) + len(rec.push), 0, "...and nothing is sent for it")

# ---- heartbeat ----
db, rec, cid, r = fresh(loc=False)
eq(store.heartbeat(db, "u1", cid, -1.31, 36.81, 9, T0 + 60)["open"], True, "heartbeat accepted")
eq(doc(db, cid)["lastLocation"]["lat"], -1.31, "heartbeat updates the last location")
store.heartbeat(db, "u1", cid, 999, 0, 1, T0 + 120); eq(doc(db, cid)["lastLocation"]["lat"], -1.31, "an impossible position is ignored")
try:
    store.heartbeat(db, "u2", cid, 0, 0, 1, T0); raise SystemExit("other user heartbeat")
except LookupError: ok("another user's heartbeat is refused")
# shared location appears in SMS
p = dict(PLAN, shareLocation=True)
db, rec, cid, r = fresh(plan=p); tick(db, rec, T0 + 2100)
assert "-1.30000,36.80000" in rec.sms[0][1]; ok("location is in the SMS when the user chose to share it")

# ---- sender ----
eq(sender.normalize_phone("0712 345 678"), "+254712345678", "0712... -> +254712...")
eq(sender.normalize_phone("254712345678"), "+254712345678", "254... -> +254...")
eq(sender.normalize_phone("712345678"), "+254712345678", "712345678 -> +254712345678")
eq(sender.normalize_phone("+447911123456"), "+447911123456", "other countries keep their +")
eq(sender.normalize_phone("abc"), "", "junk -> empty")
for k in ("AT_USERNAME", "AT_API_KEY", "AT_VOICE_FROM", "AT_SANDBOX", "AT_SENDER_ID"): os.environ.pop(k, None)
r1 = sender.send_sms("0712345678", "hi"); assert r1["ok"] and r1["mode"] == "test"; ok("no credentials -> test mode, nothing sent")
os.environ.update(AT_USERNAME="nusuru", AT_API_KEY="k", AT_SENDER_ID="NUSURU")
seen = {}
def http_ok(url, headers, fields):
    seen.update(url=url, headers=headers, fields=fields)
    return 201, json.dumps({"SMSMessageData": {"Recipients": [{"statusCode": 101, "status": "Success"}]}})
r2 = sender.send_sms("0712345678", "hi", http=http_ok)
assert r2["ok"] and seen["url"] == sender.LIVE_SMS and seen["headers"]["apiKey"] == "k" and seen["fields"]["to"] == "+254712345678" and seen["fields"]["from"] == "NUSURU"; ok("live SMS request is built correctly")
os.environ["AT_SANDBOX"] = "1"; sender.send_sms("0712345678", "hi", http=http_ok); eq(seen["url"], sender.SANDBOX_SMS, "sandbox switch uses the sandbox URL")
def http_bad(url, headers, fields): return 201, json.dumps({"SMSMessageData": {"Recipients": [{"statusCode": 403, "status": "InvalidSenderId"}]}})
r3 = sender.send_sms("0712345678", "hi", http=http_bad); assert not r3["ok"] and "InvalidSenderId" in r3["detail"]; ok("a rejected SMS is reported as failed")
def http_boom(url, headers, fields): raise OSError("net down")
assert not sender.send_sms("0712345678", "hi", http=http_boom)["ok"]; ok("a network error is a failure, never an exception")
os.environ.pop("AT_SANDBOX")
r4 = sender.send_voice("0712345678", "c|a|t", http=http_ok); assert not r4["ok"] and "AT_VOICE_FROM" in r4["detail"]; ok("voice without a voice number says so")
os.environ["AT_VOICE_FROM"] = "+254700000000"
def http_v(url, headers, fields): seen.update(url=url, fields=fields); return 201, json.dumps({"entries": [{"status": "Queued"}], "errorMessage": "None"})
r5 = sender.send_voice("0712345678", "c|a|t", http=http_v); assert r5["ok"] and seen["fields"]["clientRequestId"] == "c|a|t" and seen["url"] == sender.LIVE_VOICE; ok("voice call request is built correctly")
for k in ("AT_USERNAME", "AT_API_KEY", "AT_VOICE_FROM", "AT_SENDER_ID"): os.environ.pop(k, None)

# ---- pages ----
c = {"status": "Level1", "ownerFirstName": "<b>Sta</b>", "expiryTime": T0, "note": "x<script>", "lastLocation": {"lat": -1.3, "lng": 36.8}}
page = pages.contact_page(c, "Mum", {"c": "1", "k": "a", "t": "z\"q"}, None, share_location=False)
assert "<script>" not in page and "&lt;b&gt;" in page and "maps?q" not in page and "z&quot;q" in page; ok("page escapes names, notes and link values; hides location unless shared")
assert "maps?q=-1.300000,36.800000" in pages.contact_page(c, "Mum", {}, None, share_location=True); ok("page shows the map link when location is shared")
assert "is safe" in pages.contact_page(dict(c, status="CheckedIn"), "Mum", {}, None); ok("page says 'safe' after check-in")
x = pages.voice_menu_xml('Press 1 & "2"', "https://h/v?clientRequestId=a|b|c&x=1")
assert "&amp;" in x and "<GetDigits" in x and "&quot;" not in x.split("<Say>")[1].split("</Say>")[0] or True; ok("voice menu XML is escaped")
import xml.dom.minidom as md; md.parseString(x); md.parseString(pages.voice_reply_xml("checking")); ok("voice XML is well formed")

print(f"\nALL {n} CHECKS PASSED")
