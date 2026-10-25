"""Tests for administrator account rules, with a fake Firebase Auth. Run from the functions folder:  py tests\test_admin_accounts.py"""
import os, sys
FN = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, FN)
import dispatch  # noqa: F401
from dispatch import admin_accounts as A, config as C

class NotFound(Exception): pass
class Meta: creation_timestamp = 1; last_sign_in_timestamp = 2
class U:
    def __init__(s, uid, email, claims=None, disabled=False): s.uid, s.email, s.custom_claims, s.disabled, s.display_name, s.user_metadata = uid, email, claims, disabled, "", Meta()
class Page:
    def __init__(s, users): s.users = users
    def iterate_all(s): return iter(list(s.users.values()))
class FakeAuth:
    UserNotFoundError = NotFound
    def __init__(s): s.users, s.revoked, s.n = {}, [], 0
    def get_user_by_email(s, e):
        for u in s.users.values():
            if u.email == e: return u
        raise NotFound()
    def get_user(s, uid): return s.users[uid]
    def create_user(s, email, email_verified, disabled): s.n += 1; u = U(f"u{s.n}", email, None, disabled); s.users[u.uid] = u; return u
    def set_custom_user_claims(s, uid, c): s.users[uid].custom_claims = c
    def revoke_refresh_tokens(s, uid): s.revoked.append(uid)
    def generate_password_reset_link(s, e): return f"https://example/reset?e={e}"
    def list_users(s): return Page(s.users)
n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")
def fails(code, fn):
    try: fn()
    except A.AdminError as e: assert e.code == code, (e.code, e.message); return e.message
    raise AssertionError("expected AdminError " + code)

a = FakeAuth(); a.users["boss"] = U("boss", "boss@x.org", {"role": "SystemAdmin"}); a.users["res"] = U("res", "res@x.org", {"foo": 1})
r = A.grant(a, "  New.Admin@X.org "); assert r["created"] and r["link"] and r["email"] == "new.admin@x.org" and a.users[r["uid"]].custom_claims == {"role": "SystemAdmin"}; ok("a new e-mail gets an account, the admin flag and a one-time password link (no password chosen)")
r = A.grant(a, "res@x.org"); assert not r["created"] and r["link"] is None and a.users["res"].custom_claims == {"foo": 1, "role": "SystemAdmin"}; ok("an existing account is promoted and keeps its other flags; no link needed")
r = A.grant(a, "res@x.org"); assert r["already"]; ok("promoting someone who is already an administrator is harmless")
for bad in ("", "nope", "a@b", "a b@c.org", None, "x" * 250 + "@a.org"): fails("invalid-argument", lambda b=bad: A.grant(a, b))
ok("invalid e-mails are refused")
C.ADMIN_EMAIL_DOMAINS = ["strathmore.edu"]
msg = fails("invalid-argument", lambda: A.grant(a, "x@gmail.com")); assert "strathmore.edu" in msg; assert A.grant(a, "ok@strathmore.edu")["created"]; C.ADMIN_EMAIL_DOMAINS = []
ok("optional domain allow-list works")
a.users["dis"] = U("dis", "dis@x.org", None, True); fails("failed-precondition", lambda: A.grant(a, "dis@x.org")); ok("a disabled account cannot be made administrator")
assert {x["email"] for x in A.list_admins(a)} >= {"boss@x.org", "res@x.org", "new.admin@x.org"} and all(x["email"] != "dis@x.org" for x in A.list_admins(a)); ok("list shows exactly the administrators")
fails("failed-precondition", lambda: A.revoke(a, "boss", "boss")); ok("nobody can remove themselves")
fails("not-found", lambda: A.revoke(a, "boss", "nobody")); fails("not-found", lambda: A.revoke(a, "boss", "dis")); ok("only real administrators can be removed")
r = A.revoke(a, "boss", "res"); assert a.users["res"].custom_claims == {"foo": 1} and "res" in a.revoked; ok("removing keeps other flags, drops admin, and revokes their sessions")
b = FakeAuth(); b.users["only"] = U("only", "o@x.org", {"role": "SystemAdmin"}); b.users["x"] = U("x", "x@x.org")
fails("failed-precondition", lambda: A.revoke(b, "x", "only")); ok("the last administrator can never be removed")
print("\nALL ADMIN ACCOUNT TESTS PASSED")
