r"""Makes ONE existing account a System Administrator (a server-side flag the app cannot change).
Run from C:\EmergencyResponseSystem\functions after:  gcloud auth application-default login   (once)
    py ..\tools\grant_admin.py --project emergencyresponsesystem-166601 --email you@example.com
The person must sign out and sign in again for the flag to take effect.  Remove it with --revoke."""
import argparse, sys
import firebase_admin
from firebase_admin import auth

ap = argparse.ArgumentParser()
ap.add_argument("--project", required=True)
g = ap.add_mutually_exclusive_group(required=True)
g.add_argument("--email"); g.add_argument("--uid")
ap.add_argument("--revoke", action="store_true")
a = ap.parse_args()
firebase_admin.initialize_app(options={"projectId": a.project})
try:
    u = auth.get_user_by_email(a.email) if a.email else auth.get_user(a.uid)
except Exception as e:  # noqa: BLE001
    sys.exit(f"Could not find that account: {type(e).__name__}: {e}")
claims = dict(u.custom_claims or {})
if a.revoke:
    claims.pop("role", None)
else:
    claims["role"] = "SystemAdmin"
auth.set_custom_user_claims(u.uid, claims)
print(("Removed admin from " if a.revoke else "Granted SystemAdmin to ") + f"{u.email or u.phone_number or u.uid} (uid {u.uid}). They must sign out and in again.")
