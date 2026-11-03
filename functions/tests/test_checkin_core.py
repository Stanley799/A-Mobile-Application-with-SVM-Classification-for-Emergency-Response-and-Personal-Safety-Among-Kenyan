"""Tests for the safety check-in brain. Run from the functions folder:   py tests\test_checkin_core.py"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE)
sys.path.insert(0, FN)
from checkin import core

T0 = 1_000_000.0
n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")

def CI(expiry=T0 + 1800, status="Active", plan=None, esc=None, **extra):
    base_plan = {"graceSec": 300, "contacts": [
        {"id": "c1", "name": "Mum", "phone": "+254700000001", "methods": ["sms", "voice"]},
        {"id": "c2", "name": "Brother", "phone": "+254700000002", "methods": ["sms"]}]}
    base_plan.update(plan or {})
    d = {"userId": "U1", "status": status, "expiryTime": expiry, "plan": base_plan, "esc": esc or {}, "ownerFirstName": "Amina",
         "note": "Walking Ngong Hills, red jacket", "lastSeenAt": T0 + 600, "lastLocation": {"lat": -1.3, "lng": 36.7}}
    d.update(extra); return d

def step(c, now):
    r = core.evaluate(c, now); c = dict(c); c["status"] = r["status"]; c["esc"] = r["esc"]; return c, r
def kinds(r): return [(a["type"], a.get("contactId") or a.get("kind") or a.get("reason")) for a in r["actions"]]

# 1 early: nothing happens
c = CI(); r = core.evaluate(c, T0); assert r["actions"] == [] and r["status"] == "Active" and not r["changed"]; ok("long before the deadline: nothing happens")

# 2 reminder 5 minutes before, once
c = CI(); c, r = step(c, T0 + 1500); assert kinds(r) == [("remind_user", "before")] and r["status"] == "Active"
c, r = step(c, T0 + 1510); assert r["actions"] == [] and not r["changed"]; ok("reminder fires 5 min before the deadline, once")

# 3 deadline: Grace and a reminder
c, r = step(c, T0 + 1800); assert r["status"] == "Grace" and kinds(r) == [("remind_user", "due")]; ok("at the deadline: Grace, user reminded")
c, r = step(c, T0 + 1830); assert r["actions"] == []
c, r = step(c, T0 + 1861); assert kinds(r) == [("remind_user", "overdue")]; ok("during grace the user is reminded every minute, no contact is told yet")

# 4 grace over: contact 1 now, contact 2 after spacing, voice later
c, r = step(c, T0 + 2100); assert r["status"] == "Level1" and kinds(r) == [("sms_contact", "c1")], kinds(r); assert r["esc"]["level1At"] == T0 + 2100; ok("grace over: only the first contact gets the SMS")
c, r = step(c, T0 + 2100 + 119); assert r["actions"] == []
c, r = step(c, T0 + 2100 + 120); assert kinds(r) == [("sms_contact", "c2")]; ok("second contact is told 2 minutes later")
c, r = step(c, T0 + 2100 + 300); assert kinds(r) == [("voice_contact", "c1")], kinds(r); ok("no answer: automated voice call to contact 1 after 5 minutes (contact 2 has no voice)")
c, r = step(c, T0 + 2100 + 301); assert r["actions"] == [] and not r["changed"]; ok("running again repeats nothing")

# 5 no acknowledgement: responders after 15 minutes
c, r = step(c, T0 + 2100 + 900); assert r["status"] == "Level2" and kinds(r) == [("create_incident", "no_response")]; ok("15 minutes with no acknowledgement: responders alerted")
c, r = step(c, T0 + 2100 + 1000); assert r["actions"] == [] and r["status"] == "Level2"; ok("the incident is requested only once")

# 6 "I'm checking" postpones responders
c = CI(); c, _ = step(c, T0 + 2100); c, _ = step(c, T0 + 2100 + 300)
e = core.acknowledge(c, "c1", "checking", T0 + 2100 + 400); assert e["ack"]["kind"] == "checking"; c["esc"] = e
c, r = step(c, T0 + 2100 + 900); assert r["status"] == "Level1" and not [a for a in r["actions"] if a["type"] == "create_incident"]; ok("a contact checking on them postpones responders")
c, r = step(c, T0 + 2100 + 400 + 900); assert r["status"] == "Level2"; ok("...but only for 15 minutes")

# 7 "cannot reach" is immediate and is never downgraded
c = CI(); c, _ = step(c, T0 + 2100)
c["esc"] = core.acknowledge(c, "c1", "cannot_reach", T0 + 2200); c, r = step(c, T0 + 2201)
assert r["status"] == "Level2" and kinds(r) == [("create_incident", "contact_cannot_reach")]; ok("'cannot reach them' alerts responders at once")
c2 = CI(); c2, _ = step(c2, T0 + 2100); c2["esc"] = core.acknowledge(c2, "c1", "cannot_reach", T0 + 2200)
again = core.acknowledge(c2, "c2", "checking", T0 + 2210); assert again["ack"]["kind"] == "cannot_reach"; ok("a later 'checking' never cancels 'send help'")
assert core.acknowledge(c2, "zzz", "checking", T0) is None and core.acknowledge(c2, "c1", "bogus", T0) is None and core.acknowledge(CI(), "c1", "checking", T0) is None; ok("acknowledgement from a stranger, a bad kind, or before escalation is ignored")

# 8 user checks in during grace: nobody is ever told
c = CI(); c, _ = step(c, T0 + 1850); res = core.on_user_close(c, "CheckedIn", T0 + 1900)
assert res["status"] == "CheckedIn" and res["actions"] == []; ok("I'm safe during grace: no one is contacted")

# 9 user checks in after contacts were told: all-clear to those contacts
c = CI(); c, _ = step(c, T0 + 2100); c, _ = step(c, T0 + 2220)
res = core.on_user_close(c, "CheckedIn", T0 + 2300); assert [(a["type"], a["contactId"]) for a in res["actions"]] == [("sms_all_clear", "c1"), ("sms_all_clear", "c2")]; ok("I'm safe after contacts were told: both get an all-clear")
c["esc"] = res["esc"]; assert core.on_user_close(c, "CheckedIn", T0 + 2400)["actions"] == []; ok("the all-clear is sent only once")
c = CI(); c, _ = step(c, T0 + 2100); c, _ = step(c, T0 + 2100 + 900); c["esc"]["incidentId"] = "INC9"
res = core.on_user_close(c, "CheckedIn", T0 + 4000); assert ("cancel_incident", "INC9") in [(a["type"], a.get("incidentId")) for a in res["actions"]]; ok("I'm safe after responders were alerted: the incident is called off")

# 10 terminal states do nothing
for st in ("CheckedIn", "Cancelled", "Closed"):
    assert core.evaluate(CI(status=st), T0 + 99999)["actions"] == []
ok("finished check-ins never act again")

# 11 responders off: stops at contacts and closes
c = CI(plan={"escalateToResponders": False}); c, _ = step(c, T0 + 2100); c, r = step(c, T0 + 2100 + 900)
assert r["status"] == "Level1" and not [a for a in r["actions"] if a["type"] == "create_incident"]; ok("responders switched off: the ladder stops at contacts")
c, r = step(c, T0 + 2100 + 7200); assert r["status"] == "Closed" and r["esc"]["closedReason"] == "unresolved"; ok("...and the check-in closes as unresolved after 2 hours")

# 12 a server that was down: one catch-up pass does the right things in order
c = CI(); r = core.evaluate(c, T0 + 1800 + 300 + 130)
assert r["status"] == "Level1" and kinds(r) == [("sms_contact", "c1"), ("sms_contact", "c2")], kinds(r); ok("late sweep: no user reminders, both due contacts told in one pass")
r = core.evaluate(CI(), T0 + 99999); assert r["status"] == "Level2" and [a["type"] for a in r["actions"]].count("create_incident") == 1; ok("very late sweep still escalates exactly once")

# 13 contacts: skips inactive and phoneless ones, caps nothing silently
c = CI(plan={"contacts": [{"id": "a", "phone": "", "methods": ["sms"]}, {"id": "b", "phone": "+254711", "active": False}, {"id": "c", "phone": "+254722", "methods": ["bogus"]}]})
assert [x["id"] for x in core.contacts_of(c)] == ["c"] and core.contacts_of(c)[0]["methods"] == ["sms"]; ok("contacts without a phone, inactive ones and unknown methods are handled")
c = CI(plan={"contacts": [{"id": "p", "phone": "+254733", "methods": ["push"], "uid": "UU"}]}); c, _ = step(c, T0 + 2100)
assert kinds(core.evaluate(c, T0 + 2100)) == [] and "p" in c["esc"]["pushSent"]; ok("a contact who is a Nusuru user can get a push")

# 14 words
t = core.sms_text(CI(), "Mum", "https://x.example/c/AB12"); print("   ", t, len(t))
assert "Amina" in t and "not a confirmed emergency" in t and "-1.30000,36.70000" in t and "https://x.example/c/AB12" in t and len(t) <= 320; ok("SMS names the person, the note, the last place, the link, and says it is not confirmed")
assert "https" not in core.sms_text(CI(), "Mum"); ok("without a link the SMS still carries coordinates as text")
assert "Press 1" in core.voice_script(CI(), "Mum") and "Press 2" in core.voice_script(CI(), "Mum"); ok("voice script explains the keypad")
assert "is safe" in core.all_clear_text(CI()); ok("all-clear text")
assert core._hhmm(0) == "03:00" and core._hhmm(86400 - 60) == "02:59"; ok("times are shown in Nairobi time")
long_note = CI(note="x" * 500); assert len(core.sms_text(long_note, "Mum")) <= 320; ok("a very long note cannot blow up the SMS")

# 15 offline fallback moment
assert core.offline_fallback_at(T0 + 1800, 300) == T0 + 1800 + 300 + 90; ok("the phone's own fallback comes 90 s after the server's moment")

# 16 validation
assert core.validate_plan(1800, {"contacts": [{"phone": "+254700000001"}]}) == []; ok("a normal plan is valid")
assert core.validate_plan(60, {"contacts": [{"phone": "+254700000001"}]}); ok("too short is rejected")
assert core.validate_plan(1800, {"contacts": [{"phone": "abc"}]}); ok("a bad phone is rejected")
assert core.validate_plan(1800, {"contacts": [{"phone": "+254700000001"}] * 6}); ok("more than 5 contacts is rejected")
assert core.validate_plan(1800, {"contacts": [], "escalateToResponders": False}); ok("nobody to alert is rejected")
assert core.validate_plan(1800, {"contacts": [{"phone": "+254700000001"}], "remindBeforeSec": [1800]}); ok("a reminder at or after the deadline is rejected")
assert core.validate_plan(1800, {"contacts": [{"phone": "+254700000001"}], "graceSec": 5}); ok("a tiny grace period is rejected")
print("\nALL CHECK-IN CORE TESTS PASSED")
