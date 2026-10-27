r"""Explains in plain words why the map / options may not appear. Reads only; changes nothing; prints no phone numbers or keys.
Run from C:\EmergencyResponseSystem\functions with the venv active (after `gcloud auth application-default login`):
    py ..\tools\check_phase3a.py --project emergencyresponsesystem-166601"""
import argparse, datetime as dt, time


def age(v, now):
    if v is None:
        return None
    if hasattr(v, "timestamp"):
        return int(now - v.timestamp())
    return None


def run(db, now=None):
    now = now or time.time()
    out = []
    fac = {}
    for s in db.collection("facilities").stream():
        d = s.to_dict() or {}
        k = f"{d.get('type', '?')}{'' if d.get('lat') is not None else ' (call-only)'}"
        fac[k] = fac.get(k, 0) + 1
    out.append(f"DIRECTORY: {sum(fac.values())} places  {fac}")
    if not any("hospital" in k or "police" in k for k in fac):
        out.append("  -> No hospitals or police stations in the directory yet. Only call-only services exist. Run tools\\import_facilities.py again.")
    out.append("RESPONDERS:")
    live_ok = 0
    for s in db.collection("responders").stream():
        d = s.to_dict() or {}
        seen = age(d.get("lastSeenAt"), now)
        has_loc = d.get("currentLatitude") is not None
        ok = d.get("verificationStatus") == "Verified" and d.get("availabilityStatus") == "Available" and has_loc and seen is not None and seen <= 120
        live_ok += ok
        why = "" if ok else " <- NOT offered: " + ", ".join(w for w, bad in (("not Verified", d.get("verificationStatus") != "Verified"), (f"status {d.get('availabilityStatus')}", d.get("availabilityStatus") != "Available"), ("no location", not has_loc), ("location older than 2 min" if seen else "never reported", seen is None or seen > 120)) if bad)
        out.append(f"  {str(d.get('organizationName'))[:30]:30} {d.get('organizationType')!s:10} {d.get('verificationStatus')!s:9} {d.get('availabilityStatus')!s:9} last seen {seen}s ago{why}")
    out.append(f"  -> {live_ok} responder(s) can receive an offer right now.")
    incs = []
    for s in db.collection("incidents").stream():
        d = s.to_dict() or {}
        incs.append((d.get("createdAt").timestamp() if hasattr(d.get("createdAt"), "timestamp") else 0, s.id, d))
    incs.sort(reverse=True)
    out.append("LATEST ALERTS:")
    for _t, iid, d in incs[:3]:
        o = [x.id for x in db.collection("incidents").document(iid).collection("options").stream()]
        meta = db.collection("incidents").document(iid).collection("options").document("meta").get()
        disp = d.get("dispatch") or {}
        out.append(f"  {iid[:10]}  {d.get('category')}  status={d.get('status')}  has location={d.get('location') is not None}  dispatch={disp.get('state')}  option docs={sorted(o)}")
        if not o:
            out.append("    -> No options were written. Causes: dispatch is not running for this alert (functions), the alert has no location, or the feature flag in the app is off so you never saw it.")
        elif meta.exists:
            out.append(f"    meta: {({k: v for k, v in (meta.to_dict() or {}).items() if k != 'updatedAt'})}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--project", required=True); a = ap.parse_args()
    import firebase_admin
    from firebase_admin import firestore
    firebase_admin.initialize_app(options={"projectId": a.project})
    print("\n".join(run(firestore.client())))
