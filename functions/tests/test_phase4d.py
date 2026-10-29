"""Phase 4D tests: deterministic events, SLA attention, SOS, contact reveal, check-ins, metrics.
Run from the functions folder:   .venv\\Scripts\\python.exe tests\\test_phase4d.py
No network, no Firebase: the in-memory fake only."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FN = os.path.dirname(HERE)
sys.path.insert(0, FN)
sys.path.insert(0, HERE)

import dispatch  # noqa: F401  (path set-up)
from dispatch import store
import phase4d_core as p4
import fake_firestore as fake
from fake_firestore import DB

PASSED = 0


def ok(name, cond):
    global PASSED
    assert cond, name
    PASSED += 1
    print(f"{PASSED:2d} PASS {name}")


def incident(db, iid="INC1", status="Active", priority="High", accuracy=None, user="res1"):
    d = {"userId": user, "status": status, "category": "Medical Emergency", "priority": priority,
         "dispatch": {"priority": priority}, "createdAt": 1000.0, "location": None}
    if accuracy is not None:
        d["locationAccuracyM"] = accuracy
    db.put(f"incidents/{iid}", d)
    return d


def offer(db, oid, iid, rid="r1", status="offered", created=1000.0):
    db.put(f"offers/{oid}", {"incidentId": iid, "responderId": rid, "status": status, "createdAt": created, "role": "medical_transport"})


def event_count(db, iid):
    return len([p for p in db.data if p.startswith(f"incidents/{iid}/events/")])


def main():
    # 1 deterministic ids: a retried trigger cannot duplicate an event
    db = DB()
    ok("first event is written", p4.write_event(db, "INC1", "offer_accepted", "responder", "r1", {"role": "medical_transport"}, "offer_accepted_O1") is True)
    ok("the same event id is refused the second time", p4.write_event(db, "INC1", "offer_accepted", "responder", "r1", {"role": "medical_transport"}, "offer_accepted_O1") is False)
    ok("exactly one event document exists", event_count(db, "INC1") == 1)
    ok("event data keeps only scalar values", p4._clean_data({"a": "x" * 200, "loc": {"lat": 1}, "n": 2, "b": True}) == {"a": "x" * 60, "n": 2, "b": True})
    ok("unknown event types are refused", _raises(ValueError, lambda: p4.write_event(db, "INC1", "made_up", "system", "system")))

    # 2 SLA attention: High 60 s, Medium 120 s, Low 300 s after the first offer
    for priority, limit in (("High", 60), ("Medium", 120), ("Low", 300)):
        db = DB()
        inc = incident(db, priority=priority)
        offer(db, "O1", "INC1", created=1000.0)
        ok(f"{priority}: not yet flagged one second before {limit} s", p4.attention_decision(inc, p4.offers_of(db, "INC1"), 1000.0 + limit - 1) is None)
        ok(f"{priority}: flagged at {limit} s", p4.attention_decision(inc, p4.offers_of(db, "INC1"), 1000.0 + limit) == "no_accept_in_time")

    db = DB()
    inc = incident(db)
    offer(db, "O1", "INC1", created=1000.0)
    ok("sweep raises the flag and writes one attention_raised", p4.sweep_attention(db, 1060.0) == ["INC1"] and db.data["incidents/INC1"]["needsAttention"] is True)
    ok("the reason is stored", db.data["incidents/INC1"]["attentionReason"] == "no_accept_in_time")
    ok("attention_raised event exists once", [p for p in db.data if p.endswith("/attention_raised_no_accept_in_time")] != [])
    ok("running the sweep again changes nothing", p4.sweep_attention(db, 1061.0) == [])

    db.data["offers/O1"]["status"] = "accepted"
    p4.sweep_attention(db, 1100.0)
    ok("a unit accepting clears the SLA flag", db.data["incidents/INC1"]["needsAttention"] is False and db.data["incidents/INC1"]["attentionReason"] == "none")

    db = DB()
    incident(db)
    ok("a closed incident is never flagged", p4.attention_decision({**db.data["incidents/INC1"], "status": "Cancelled"}, [], 9999.0) is None)

    # 3 SOS: verified responders only, one per 60 s
    db = DB()
    db.put("responders/r1", {"verificationStatus": "Verified", "organizationName": "Unit A", "currentLatitude": -1.2921, "currentLongitude": 36.8219})
    incident(db)
    fake.CLOCK[0] = 2000.0                    # the fake turns SERVER_TIMESTAMP into CLOCK time, as Firebase does
    sos_id = p4.sos_create(db, "r1", "INC1", 2000.0)
    ok("SOS document is created with the last known position", db.data[f"sos_alerts/{sos_id}"]["lat"] == -1.2921 and db.data[f"sos_alerts/{sos_id}"]["status"] == "open")
    ok("SOS flags the incident", db.data["incidents/INC1"]["attentionReason"] == "responder_sos")
    ok("a second SOS within 60 s is refused", _raises(p4.Phase4DError, lambda: p4.sos_create(db, "r1", "INC1", 2030.0)))
    fake.CLOCK[0] = 2061.0
    ok("after 60 s a new SOS is allowed", p4.sos_create(db, "r1", "INC1", 2061.0) != sos_id)
    db.put("responders/r2", {"verificationStatus": "Pending", "organizationName": "Unit B"})
    ok("an unverified responder cannot send SOS", _raises(p4.Phase4DError, lambda: p4.sos_create(db, "r2", None, 2000.0)))
    ok("a missing responder cannot send SOS", _raises(p4.Phase4DError, lambda: p4.sos_create(db, "nobody", None, 2000.0)))

    # 4 contact reveal: staff only, always recorded
    db = DB()
    incident(db)
    db.put("users/res1", {"firstName": "Test", "phoneNumber": "+254700000000"})
    out = p4.reveal_contact(db, {"role": "Dispatcher", "uid": "d1"}, "INC1")
    ok("the dispatcher gets the contact", out == {"firstName": "Test", "phone": "+254700000000"})
    ok("the reveal is recorded as a dispatcher action", db.data[[p for p in db.data if p.startswith("incidents/INC1/events/admin_revealed_contact_")][0]]["actorRole"] == "dispatcher")
    ok("a resident is refused", _raises(p4.Phase4DError, lambda: p4.reveal_contact(db, {"role": "Resident", "uid": "x"}, "INC1")))
    ok("a responder is refused", _raises(p4.Phase4DError, lambda: p4.reveal_contact(db, {"role": "Responder", "uid": "x"}, "INC1")))
    ok("an administrator is allowed", p4.reveal_contact(db, {"role": "SystemAdmin", "uid": "a1"}, "INC1")["phone"] == "+254700000000")

    # 4b the dispatch contact goes into a Functions-only document at alert creation
    db = DB()
    incident(db)
    db.put("users/res1", {"firstName": "Test", "phoneNumber": "+254700000000"})
    ok("the contact snapshot is written at creation", p4.snapshot_contact(db, "INC1", db.data["incidents/INC1"]) is True)
    snap = db.data["incidents/INC1/private/contact"]
    ok("the snapshot holds the caller's first name and phone", snap["firstName"] == "Test" and snap["phone"] == "+254700000000")
    ok("the snapshot is never rewritten", p4.snapshot_contact(db, "INC1", db.data["incidents/INC1"]) is False)
    db.data["users/res1"]["phoneNumber"] = "+254700000099"
    ok("reveal_contact reads the snapshot, not the profile", p4.reveal_contact(db, {"role": "Dispatcher", "uid": "d1"}, "INC1")["phone"] == "+254700000000")
    ok("a caller with no profile still gets an empty snapshot", p4.snapshot_contact(db, "INC2", {"userId": "missing"}) is True
       and db.data["incidents/INC2/private/contact"]["phone"] == "")

    # 4c the post-acceptance release prefers the snapshot (the profile is only a fallback for older alerts)
    db.put("offers/O9", {"incidentId": "INC1", "responderId": "r1", "status": "accepted"})
    offer_doc = {"id": "O9", "incidentId": "INC1", "responderId": "r1", "resident": None}
    store.release_resident(db, offer_doc, {"id": "INC1", "userId": "res1"})
    ok("the unit receives the snapshot contact", db.data["offers/O9"]["resident"] == {"firstName": "Test", "phone": "+254700000000"})
    released_events = len([p for p in db.data if p.startswith("auditLogs/")])
    store.release_resident(db, {"id": "O9", "incidentId": "INC1", "responderId": "r1", "resident": db.data["offers/O9"]["resident"]},
                          {"id": "INC1", "userId": "res1"})
    ok("the contact is released once", len([p for p in db.data if p.startswith("auditLogs/")]) == released_events)

    # 5 check-ins: fixed questions only
    db = DB()
    incident(db)
    cid = p4.send_checkin(db, {"role": "Dispatcher", "uid": "d1"}, "INC1", "person_breathing", 3000.0)
    ok("the question text comes from the server template", db.data[f"incidents/INC1/checkins/{cid}"]["text"] == "Is the person breathing normally?")
    ok("the check-in starts unanswered", db.data[f"incidents/INC1/checkins/{cid}"]["reply"] is None)
    ok("an unknown question is refused", _raises(p4.Phase4DError, lambda: p4.send_checkin(db, {"role": "Dispatcher", "uid": "d1"}, "INC1", "what_drugs", 3001.0)))
    ok("a resident cannot send a check-in", _raises(p4.Phase4DError, lambda: p4.send_checkin(db, {"role": "Resident", "uid": "x"}, "INC1", "can_you_talk", 3002.0)))

    # 6 metrics: every step, then with steps missing
    full = p4.compute_metrics(1000.0, {"classified": 1064.0, "offer_sent": 1100.0, "offer_accepted": 1145.0, "unit_arrived": 1300.0}, 1600.0)
    ok("metrics: all five numbers", full == {"secondsToClassify": 64, "secondsToFirstOffer": 36, "secondsToFirstAccept": 45, "secondsToFirstArrival": 300, "secondsTotal": 600})
    empty = p4.compute_metrics(1000.0, {}, 1600.0)
    ok("metrics: missing steps are null, never a crash", empty == {"secondsToClassify": None, "secondsToFirstOffer": None, "secondsToFirstAccept": None, "secondsToFirstArrival": None, "secondsTotal": 600})
    ok("metrics: a step that happened before the alert is refused (null)", p4.compute_metrics(1000.0, {"classified": 900.0}, 1600.0)["secondsToClassify"] is None)
    ok("metrics: no timestamps at all", p4.compute_metrics(None, {}, None)["secondsTotal"] is None)

    # close_metrics writes once
    db = DB()
    incident(db, status="Resolved")
    p4.write_event(db, "INC1", "classified", "resident", "res1", {}, "classified_complete")
    ok("close_metrics writes the map", p4.close_metrics(db, "INC1", db.data["incidents/INC1"], 1600.0) is True)
    ok("close_metrics never overwrites", p4.close_metrics(db, "INC1", db.data["incidents/INC1"], 1700.0) is False)
    ok("stored metrics contain the total", db.data["incidents/INC1"]["metrics"]["secondsTotal"] == 600)

    print(f"\nALL PHASE 4D TESTS PASSED ({PASSED} assertions)")


def _raises(exc, fn):
    try:
        fn()
    except exc:
        return True
    return False


if __name__ == "__main__":
    main()
