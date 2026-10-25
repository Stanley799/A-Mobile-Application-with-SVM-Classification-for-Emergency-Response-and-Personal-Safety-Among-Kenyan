"""Phase 3A callables (self-contained; main.py imports them with one line).
  resident_request_unit : the resident asks one specific registered unit from their options list
  incident_route        : route line + ETA of an accepted unit (owner, that unit, or an administrator)
The Maps server key is the Firebase secret MAPS_SERVER_KEY. If it is missing, everything still works with straight-line estimates."""
import time

from firebase_admin import firestore
from firebase_functions import https_fn, options
from firebase_functions.params import SecretParam

import dispatch  # noqa: F401  (path set-up)
from dispatch import config as C, job_route, notify, resident_requests as rr

MAPS_SERVER_KEY = SecretParam("MAPS_SERVER_KEY")
OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_256, timeout_sec=30, max_instances=10, secrets=[MAPS_SERVER_KEY])
_CODES = {"not-found": https_fn.FunctionsErrorCode.NOT_FOUND, "failed-precondition": https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
          "resource-exhausted": https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED}


def _need_auth(req):
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")


def _strs(req, *names):
    d = req.data if isinstance(req.data, dict) else {}
    out = []
    for n in names:
        v = d.get(n)
        if not isinstance(v, str) or not v or len(v) > 128 or "/" in v:
            raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, f"{n} is required.")
        out.append(v)
    return out


@https_fn.on_call(**OPTS)
def resident_request_unit(req: https_fn.CallableRequest):
    _need_auth(req)
    iid, rid = _strs(req, "incidentId", "responderId")
    db = firestore.client()
    try:
        offer = rr.request_unit(db, iid, req.auth.uid, rid, time.time())
    except rr.RequestError as e:
        raise https_fn.HttpsError(_CODES.get(e.code, https_fn.FunctionsErrorCode.INTERNAL), e.message)
    notify.send_offer_push(db, offer)
    return {"ok": True}


@https_fn.on_call(**OPTS)
def incident_route(req: https_fn.CallableRequest):
    _need_auth(req)
    iid, rid = _strs(req, "incidentId", "responderId")
    return job_route.route_for(firestore.client(), iid, rid, req.auth.uid, (req.auth.token or {}).get("role") == "SystemAdmin", time.time())
