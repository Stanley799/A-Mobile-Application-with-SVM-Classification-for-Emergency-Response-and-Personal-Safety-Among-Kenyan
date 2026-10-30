"""Dispatcher approval rules, with a fake Firebase Auth and the in-memory Firestore. Run from functions:  py tests\test_staff_accounts.py"""
import os, sys
FN = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, FN)
import dispatch  # noqa: F401
from dispatch import staff_accounts as SA
from tests.fake_firestore import DB

class NotFound(Exception): pass
class U:
    def __init__(s, uid, email, claims=None): s.uid, s.email, s.custom_claims = uid, email, claims

class FakeAuth:
    def __init__(s): s.users, s.revoked = {}, []
    def get_user(s, uid):
        if uid not in s.users: raise NotFound()
        return s.users[uid]
    def set_custom_user_claims(s, uid, c): s.users[uid].custom_claims = c
    def revoke_refresh_tokens(s, uid): s.revoked.append(uid)

n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")
def fails(code, fn):
    try: fn()
    except SA.StaffError as e:
        assert e.code == code, (e.code, e.message)
        return e.message
    raise AssertionError("expected StaffError " + code)

db, auth = DB(), FakeAuth()
db.put("users/applicant", {"userId": "applicant", "email": "d@x.org", "firstName": "Dee", "lastName": "One", "role": "Dispatcher", "accountStatus": "PendingVerification"})
db.put("users/resident", {"userId": "resident", "role": "Resident", "accountStatus": "Active"})
db.put("users/admin", {"userId": "admin", "role": "Resident", "accountStatus": "Active"})
auth.users = {"applicant": U("applicant", "d@x.org", {"foo": 1}), "resident": U("resident", "r@x.org"), "admin": U("admin", "a@x.org", {"role": "SystemAdmin"})}
boss = "boss"

r = SA.review(db, auth, boss, "applicant", "approved")
assert r["accountStatus"] == "Active" and auth.users["applicant"].custom_claims == {"foo": 1, "role": "Dispatcher"}
assert "applicant" in auth.revoked
assert db.data["users/applicant"]["accountStatus"] == "Active"
assert db.data["staff_approvals/applicant"]["status"] == "approved" and db.data["staff_approvals/applicant"]["by"] == boss
ok("approving sets the Dispatcher claim, keeps other claims, activates the profile and revokes old sessions")

fails("invalid-argument", lambda: SA.review(db, auth, boss, "applicant", "rejected"))
fails("invalid-argument", lambda: SA.review(db, auth, boss, "applicant", "rejected", "x"))
assert SA.review(db, auth, boss, "applicant", "rejected", "  Not a staff role  ")["status"] == "rejected"
assert "role" not in auth.users["applicant"].custom_claims and auth.users["applicant"].custom_claims == {"foo": 1}
assert db.data["users/applicant"]["accountStatus"] == "Suspended"
assert db.data["staff_approvals/applicant"]["reason"] == "Not a staff role"
ok("rejecting needs a reason, removes only the Dispatcher claim and stores the reason the applicant can read")

SA.review(db, auth, boss, "applicant", "approved")
assert SA.review(db, auth, boss, "applicant", "suspended", "Shift review")["status"] == "suspended"
assert "role" not in auth.users["applicant"].custom_claims and db.data["users/applicant"]["accountStatus"] == "Suspended"
ok("suspending removes the claim immediately")

fails("invalid-argument", lambda: SA.review(db, auth, boss, "applicant", "promoted"))
fails("invalid-argument", lambda: SA.review(db, auth, boss, "", "approved"))
fails("not-found", lambda: SA.review(db, auth, boss, "missing", "approved"))
fails("not-found", lambda: SA.review(db, auth, boss, "resident", "approved"))
ok("unknown decisions, residents and missing accounts are refused")

fails("failed-precondition", lambda: SA.review(db, auth, "applicant", "applicant", "suspended", "me"))
ok("nobody can decide their own application")

db.put("users/admin2", {"userId": "admin2", "role": "Dispatcher", "accountStatus": "Active"})
auth.users["admin2"] = U("admin2", "a2@x.org", {"role": "SystemAdmin"})
fails("failed-precondition", lambda: SA.review(db, auth, boss, "admin2", "approved"))
db.collection("users").document("admin2").delete()
ok("an administrator account is never turned into a dispatcher")

db.put("users/p2", {"userId": "p2", "email": "b@x.org", "firstName": "B", "lastName": "Two", "role": "Dispatcher", "accountStatus": "PendingVerification"})
auth.users["p2"] = U("p2", "b@x.org")
lst = SA.list_dispatchers(db)
assert [x["uid"] for x in lst][0] == "p2", lst
assert {x["uid"]: x["status"] for x in lst} == {"p2": "pending", "applicant": "suspended"}
assert next(x for x in lst if x["uid"] == "applicant")["reason"] == "Shift review"
assert next(x for x in lst if x["uid"] == "p2")["email"] == "b@x.org"
ok("the list shows every application, pending first, with the latest reason")

print("\nALL STAFF ACCOUNT TESTS PASSED")
