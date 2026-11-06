"""Safety check-in: the Firebase entry points. All decisions are in checkin/core.py, all storage in checkin/store.py.

  sweep_checkins      every minute: reminders, contacts, responders (only check-ins made by the new flow)
  on_checkin_updated  when a user closes a check-in: tell contacts it was a false alarm
  checkin_start / checkin_heartbeat / checkin_close   called by the app
  checkin_contact     the web page a contact opens from the SMS (two buttons)
  checkin_voice       what the automated call says, and the keypad answer
"""
import os
import time

from firebase_admin import firestore, messaging
from firebase_functions import firestore_fn, https_fn, options, scheduler_fn

from dispatch import config as C
from checkin import core, pages, sender, store

_OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_256, timeout_sec=60, max_instances=10)


def _db():
    return firestore.client()


def _base_url():
    base = os.environ.get("CHECKIN_BASE_URL", "").strip().rstrip("/")
    if base:
        return base
    project = os.environ.get("GCLOUD_PROJECT") or os.environ.get("GCP_PROJECT") or ""
    return "https://%s-%s.cloudfunctions.net" % (C.REGION, project)


def _push(uid, title, body, data):
    if not uid:
        return False
    snap = _db().collection("deviceTokens").document(uid).get()
    token = (snap.to_dict() or {}).get("token") if snap.exists else None
    if not token:
        return False
    messaging.send(messaging.Message(token=token, notification=messaging.Notification(title=title, body=body),
                                     data={k: str(v) for k, v in (data or {}).items()},
                                     android=messaging.AndroidConfig(priority="high")))
    return True


def _io():
    return store.make_io(push=_push, link=lambda cid, k, t: "%s/checkin_contact?c=%s&k=%s&t=%s" % (_base_url(), cid, k, t))


def _first_name(db, uid, token):
    for src in (token or {},):
        n = str(src.get("name") or "").split()
        if n:
            return n[0]
    snap = db.collection("users").document(uid).get()
    d = snap.to_dict() if snap.exists else {}
    for k in ("firstName", "fullName", "name", "displayName"):
        n = str(d.get(k) or "").split()
        if n:
            return n[0]
    return ""


def _need_auth(req):
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    return req.auth.uid


@scheduler_fn.on_schedule(schedule="every 1 minutes", **_OPTS)
def sweep_checkins(event: scheduler_fn.ScheduledEvent) -> None:
    store.sweep(_db(), time.time(), _io())


@firestore_fn.on_document_updated(document="safetyCheckins/{checkinId}", **_OPTS)
def on_checkin_updated(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    after = event.data.after.to_dict() if event.data and event.data.after else None
    before = event.data.before.to_dict() if event.data and event.data.before else None
    if after and before and before.get("status") != after.get("status") and after.get("status") in ("CheckedIn", "Cancelled"):
        store.settle(_db(), event.params["checkinId"], time.time(), _io())


@https_fn.on_call(**_OPTS)
def checkin_start(req: https_fn.CallableRequest):
    uid = _need_auth(req)
    d = req.data or {}
    db = _db()
    loc = d.get("location") if isinstance(d.get("location"), dict) else None
    try:
        return store.start(db, uid, _first_name(db, uid, req.auth.token), d.get("durationSec"), d.get("plan"), d.get("note"), time.time(), loc)
    except ValueError as e:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, " ".join(e.args[0]))


@https_fn.on_call(**_OPTS)
def checkin_heartbeat(req: https_fn.CallableRequest):
    uid = _need_auth(req)
    d = req.data or {}
    try:
        return store.heartbeat(_db(), uid, str(d.get("id") or ""), d.get("lat"), d.get("lng"), d.get("accuracy"), time.time())
    except LookupError:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "Check-in not found.")


@https_fn.on_call(**_OPTS)
def checkin_close(req: https_fn.CallableRequest):
    uid = _need_auth(req)
    d = req.data or {}
    try:
        return store.close(_db(), uid, str(d.get("id") or ""), d.get("status"), time.time(), _io())
    except LookupError:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "Check-in not found.")
    except ValueError as e:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, " ".join(e.args[0]))


def _html(body, code=200):
    return https_fn.Response(body, status=code, headers={"Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"})


@https_fn.on_request(invoker="public", **_OPTS)
def checkin_contact(req: https_fn.Request) -> https_fn.Response:
    q = {k: (req.values.get(k) or "") for k in ("c", "k", "t")}
    db = _db()
    got = store.view_for_page(db, q["c"], q["k"], q["t"])
    if got is None:
        return _html("<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'><p style='font-family:sans-serif;padding:24px'>"
                     "This link is not valid or has expired.</p>", 404)
    c, name, share = got
    msg = None
    if req.method == "POST":
        kind = req.values.get("a")
        r = store.contact_ack(db, q["c"], q["k"], q["t"], kind, time.time(), _io())
        msg = {"ok": {"checking": "Thank you. We will give you more time before alerting responders.",
                      "cannot_reach": "Thank you. Nusuru is alerting nearby responders now."}.get(kind, "Thank you."),
               "not_applicable": "This check-in is no longer waiting for an answer."}.get(r, "Sorry, that did not work.")
        got = store.view_for_page(db, q["c"], q["k"], q["t"]) or got
        c, name, share = got
    return _html(pages.contact_page(c, name, q, msg, share))


@https_fn.on_request(invoker="public", **_OPTS)
def checkin_voice(req: https_fn.Request) -> https_fn.Response:
    """Africa's Talking asks what to say (first request) and then posts the key the contact pressed (dtmfDigits)."""
    xml = {"Content-Type": "application/xml; charset=utf-8"}
    parts = (req.values.get("clientRequestId") or "").split("|")
    if len(parts) != 3:
        return https_fn.Response(pages.voice_reply_xml(None), headers=xml)
    cid, k, t = parts
    db = _db()
    digit = (req.values.get("dtmfDigits") or "").strip()
    if digit:
        kind = {"1": "checking", "2": "cannot_reach"}.get(digit)
        r = store.contact_ack(db, cid, k, t, kind, time.time(), _io()) if kind else "not_applicable"
        return https_fn.Response(pages.voice_reply_xml(kind if r == "ok" else None), headers=xml)
    got = store.view_for_page(db, cid, k, t)
    if got is None:
        return https_fn.Response(pages.voice_reply_xml(None), headers=xml)
    c, name, _share = got
    cb = "%s/checkin_voice?clientRequestId=%s" % (_base_url(), "|".join(parts))
    return https_fn.Response(pages.voice_menu_xml(core.voice_script(c, name), cb), headers=xml)
