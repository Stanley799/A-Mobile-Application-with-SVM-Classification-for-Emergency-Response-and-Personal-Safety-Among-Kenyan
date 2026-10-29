"""Callables for dispatcher approvals. Administrators only; the decision itself lives in dispatch/staff_accounts.py."""
from firebase_admin import auth as fb_auth, firestore
from firebase_functions import https_fn, options

import dispatch  # noqa: F401  (path set-up)
from dispatch import config as C, staff_accounts as sa

OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_256, timeout_sec=30, max_instances=10)
_CODES = {"invalid-argument": https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
          "failed-precondition": https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
          "not-found": https_fn.FunctionsErrorCode.NOT_FOUND}


def _require_admin(req):
    if req.auth is None or (req.auth.token or {}).get("role") != "SystemAdmin":
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.PERMISSION_DENIED, "Administrators only.")


@https_fn.on_call(**OPTS)
def admin_list_dispatchers(req: https_fn.CallableRequest):
    _require_admin(req)
    return {"dispatchers": sa.list_dispatchers(firestore.client())}


@https_fn.on_call(**OPTS)
def admin_review_dispatcher(req: https_fn.CallableRequest):
    """approved | rejected | suspended, with a reason for any refusal. Sets or removes the Dispatcher claim."""
    _require_admin(req)
    d = req.data if isinstance(req.data, dict) else {}
    try:
        return sa.review(firestore.client(), fb_auth, req.auth.uid, d.get("uid"), d.get("action"), d.get("reason"))
    except sa.StaffError as e:
        raise https_fn.HttpsError(_CODES.get(e.code, https_fn.FunctionsErrorCode.INTERNAL), e.message)
