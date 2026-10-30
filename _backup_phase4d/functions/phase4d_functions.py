"""Phase 4D callables (registered from main.py with one import).
  responder_sos       : a responder asks for immediate help visible to dispatchers
  admin_resolve_sos   : a dispatcher or administrator closes one SOS alert with a note
  reveal_contact      : a dispatcher or administrator reveals the caller's name and phone (logged)
  send_checkin        : a dispatcher or administrator sends one fixed question to the caller
  request_more_units  : a dispatcher or administrator asks for another unit of a role (returns candidates)
Only ids and error codes are logged."""
import time

from firebase_admin import firestore
from firebase_functions import https_fn, options

import dispatch  # noqa: F401  (path set-up)
from dispatch import config as C

import phase4d_core as p4

OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_256, timeout_sec=30, max_instances=10)
_CODES = {"invalid-argument": https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
          "permission-denied": https_fn.FunctionsErrorCode.PERMISSION_DENIED,
          "not-found": https_fn.FunctionsErrorCode.NOT_FOUND,
          "failed-precondition": https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
          "resource-exhausted": https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED}


def _data(req):
    return req.data if isinstance(req.data, dict) else {}


def _call(fn):
    try:
        return fn()
    except p4.Phase4DError as e:
        raise https_fn.HttpsError(_CODES.get(e.code, https_fn.FunctionsErrorCode.INTERNAL), e.message)


def _auth(req):
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    return req.auth.uid, (req.auth.token or {})


@https_fn.on_call(**OPTS)
def responder_sos(req: https_fn.CallableRequest):
    uid, _token = _auth(req)
    d = _data(req)
    iid = d.get("incidentId")
    if iid is not None and not isinstance(iid, str):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId must be text.")
    sos_id = _call(lambda: p4.sos_create(firestore.client(), uid, iid, time.time()))
    return {"ok": True, "sosId": sos_id}


@https_fn.on_call(**OPTS)
def admin_resolve_sos(req: https_fn.CallableRequest):
    _uid, token = _auth(req)
    d = _data(req)
    done = _call(lambda: p4.resolve_sos(firestore.client(), token, d.get("sosId"), d.get("note"), time.time()))
    return {"ok": True, "resolved": done}


@https_fn.on_call(**OPTS)
def reveal_contact(req: https_fn.CallableRequest):
    _uid, token = _auth(req)
    d = _data(req)
    iid = d.get("incidentId")
    if not isinstance(iid, str) or not iid or "/" in iid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId is required.")
    return _call(lambda: p4.reveal_contact(firestore.client(), token, iid))


@https_fn.on_call(**OPTS)
def send_checkin(req: https_fn.CallableRequest):
    _uid, token = _auth(req)
    d = _data(req)
    iid = d.get("incidentId")
    if not isinstance(iid, str) or not iid or "/" in iid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId is required.")
    checkin_id = _call(lambda: p4.send_checkin(firestore.client(), token, iid, d.get("template"), time.time()))
    return {"ok": True, "checkinId": checkin_id}


@https_fn.on_call(**OPTS)
def request_more_units(req: https_fn.CallableRequest):
    _uid, token = _auth(req)
    d = _data(req)
    iid = d.get("incidentId")
    if not isinstance(iid, str) or not iid or "/" in iid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId is required.")
    candidates = _call(lambda: p4.request_more_units(firestore.client(), token, iid, d.get("role"), d.get("reason")))
    return {"ok": True, "candidates": candidates}
