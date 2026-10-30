"""Dispatcher accounts. An application is a users/{uid} document with role=Dispatcher and accountStatus=PendingVerification.
Only an administrator decides. Real access is the custom claim role=Dispatcher, set here and nowhere else, so approving or
suspending always revokes the person's sessions. The decision is also written to staff_approvals/{uid} so the applicant can
read the reason on their own screen. Same shape as admin_accounts: pure rules, `auth` and `db` injected for the tests."""
from google.cloud.firestore import SERVER_TIMESTAMP

CLAIM = "role"
DISPATCHER = "Dispatcher"
ADMIN = "SystemAdmin"
ACTIONS = ("approved", "rejected", "suspended")
ACTIVE, SUSPENDED, PENDING = "Active", "Suspended", "PendingVerification"


class StaffError(Exception):
    """A refusal the callable turns into an HttpsError with a message that is safe to show."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def _reason(raw, required):
    r = str(raw or "").strip()
    if required and len(r) < 3:
        raise StaffError("invalid-argument", "Give a reason (at least 3 characters).")
    if len(r) > 200:
        raise StaffError("invalid-argument", "Keep the reason under 200 characters.")
    return r


def review(db, auth, caller_uid, uid, action, reason=None):
    """approved | rejected | suspended. Returns the stored decision."""
    if action not in ACTIONS:
        raise StaffError("invalid-argument", "Unknown decision.")
    if not isinstance(uid, str) or not uid:
        raise StaffError("invalid-argument", "Choose a dispatcher.")
    if uid == caller_uid:
        raise StaffError("failed-precondition", "You cannot change your own account here.")
    snap = db.collection("users").document(uid).get()
    if not snap.exists:
        raise StaffError("not-found", "Account not found.")
    doc = snap.to_dict() or {}
    if doc.get("role") != DISPATCHER:
        raise StaffError("not-found", "That account is not a dispatcher application.")
    reason = _reason(reason, action != "approved")
    try:
        user = auth.get_user(uid)
    except Exception:  # noqa: BLE001 - a profile without a sign-in account cannot be approved
        raise StaffError("not-found", "The sign-in account no longer exists.")
    claims = dict(user.custom_claims or {})
    if claims.get(CLAIM) == ADMIN:
        raise StaffError("failed-precondition", "That account is an administrator.")
    if action == "approved":
        claims[CLAIM] = DISPATCHER
        status = ACTIVE
    else:
        claims.pop(CLAIM, None)
        status = SUSPENDED
    auth.set_custom_user_claims(uid, claims)
    auth.revoke_refresh_tokens(uid)                 # sign out everywhere: the claim changed
    db.collection("users").document(uid).update({"accountStatus": status, "updatedAt": SERVER_TIMESTAMP})
    db.collection("staff_approvals").document(uid).set(
        {"role": DISPATCHER, "status": action, "reason": reason, "at": SERVER_TIMESTAMP,
         "by": caller_uid or "", "updatedAt": SERVER_TIMESTAMP})
    return {"uid": uid, "status": action, "accountStatus": status}


def list_dispatchers(db):
    """Every dispatcher application with the administrator's latest decision (or pending)."""
    out = []
    for s in db.collection("users").where("role", "==", DISPATCHER).stream():
        d = s.to_dict() or {}
        ap = db.collection("staff_approvals").document(s.id).get()
        a = (ap.to_dict() or {}) if ap.exists else {}
        status = a.get("status") or ("approved" if d.get("accountStatus") == ACTIVE else "pending")
        out.append({
            "uid": s.id,
            "email": str(d.get("email") or ""),
            "firstName": str(d.get("firstName") or ""),
            "lastName": str(d.get("lastName") or ""),
            "accountStatus": str(d.get("accountStatus") or PENDING),
            "status": status,
            "reason": str(a.get("reason") or ""),
            "decidedAt": a.get("at"),
        })
    out.sort(key=lambda x: (x["status"] != "pending", x["email"]))
    return out
