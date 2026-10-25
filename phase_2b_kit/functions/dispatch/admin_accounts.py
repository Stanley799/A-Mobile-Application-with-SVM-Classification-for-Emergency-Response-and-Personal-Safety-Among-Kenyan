"""Administrator accounts: who may create, list and remove administrators. PURE rules + thin calls to the Firebase Auth admin API
(`auth` is injected so the tests can use a fake). An administrator is an account whose sign-in token carries the claim role=SystemAdmin.
Rules enforced here:
  * only an existing administrator may add or remove one (checked by the caller in main.py);
  * the e-mail must be valid (and on an allowed domain if ADMIN_EMAIL_DOMAINS is set);
  * you cannot remove yourself, and you cannot remove the LAST administrator;
  * every change is written to the audit log by the caller; tokens of a removed administrator are revoked."""
import re

from . import config as C

CLAIM = "role"
ADMIN = "SystemAdmin"
_EMAIL = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")


class AdminError(Exception):
    """Carries a code the caller maps to an HTTPS error and a message that is safe to show an administrator."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def clean_email(raw):
    e = str(raw or "").strip().lower()
    if not _EMAIL.match(e) or len(e) > 254:
        raise AdminError("invalid-argument", "Enter a valid e-mail address.")
    allowed = [d.lower().lstrip("@") for d in C.ADMIN_EMAIL_DOMAINS]
    if allowed and e.rsplit("@", 1)[1] not in allowed:
        raise AdminError("invalid-argument", "Administrators must use an e-mail from: " + ", ".join(allowed) + ".")
    return e


def is_admin(user):
    return (user.custom_claims or {}).get(CLAIM) == ADMIN


def list_admins(auth):
    out = []
    for u in auth.list_users().iterate_all():
        if is_admin(u):
            meta = u.user_metadata
            out.append({"uid": u.uid, "email": u.email or "", "name": u.display_name or "", "disabled": bool(u.disabled),
                        "createdAt": getattr(meta, "creation_timestamp", None), "lastSignInAt": getattr(meta, "last_sign_in_timestamp", None)})
    return sorted(out, key=lambda a: a["email"])


def grant(auth, email):
    """Makes `email` an administrator. Creates the account if it does not exist (no password: they set it with the link).
    Returns {uid, email, created, link, already}."""
    email = clean_email(email)
    created, link = False, None
    try:
        user = auth.get_user_by_email(email)
    except auth.UserNotFoundError:
        user = auth.create_user(email=email, email_verified=False, disabled=False)
        created = True
    if user.disabled:
        raise AdminError("failed-precondition", "That account is disabled.")
    already = is_admin(user)
    if not already:
        claims = dict(user.custom_claims or {})
        claims[CLAIM] = ADMIN
        auth.set_custom_user_claims(user.uid, claims)
    if created:
        link = auth.generate_password_reset_link(email)
    return {"uid": user.uid, "email": email, "created": created, "link": link, "already": already and not created}


def revoke(auth, caller_uid, target_uid):
    if not isinstance(target_uid, str) or not target_uid:
        raise AdminError("invalid-argument", "Choose an administrator to remove.")
    if target_uid == caller_uid:
        raise AdminError("failed-precondition", "You cannot remove your own administrator access. Ask another administrator.")
    admins = list_admins(auth)
    target = next((a for a in admins if a["uid"] == target_uid), None)
    if target is None:
        raise AdminError("not-found", "That person is not an administrator.")
    if len(admins) <= 1:
        raise AdminError("failed-precondition", "You cannot remove the last administrator.")
    user = auth.get_user(target_uid)
    claims = {k: v for k, v in (user.custom_claims or {}).items() if k != CLAIM}
    auth.set_custom_user_claims(target_uid, claims)
    auth.revoke_refresh_tokens(target_uid)          # they must sign in again; without the claim they get no admin access
    return {"uid": target_uid, "email": target["email"]}
