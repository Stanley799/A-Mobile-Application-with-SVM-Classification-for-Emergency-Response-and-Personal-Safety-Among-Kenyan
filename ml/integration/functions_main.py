"""Firebase Cloud Functions (2nd gen, Python) - the server side of the triage.
Copy into your Firebase project:  functions/main.py   and copy the ml project's `scripts/`, `schema/`, `models/` folders into functions/ml/
(see INTEGRATION_CHECKLIST.md).  Requirements:  firebase-functions, firebase-admin, scikit-learn (text classifier only), joblib, numpy.

Three callable functions:
  triage_text_fn(text)                       -> category / subtype / flags suggestion. The resident ALWAYS confirms it in the app.
  triage_priority_fn(category, answers, subtype) -> priority. Never errors: falls back to High + human review.
  save_text_feedback_fn(text, confirmed_category, confirmed_subtype, consent) -> saves the resident-CONFIRMED label for later training.
triage_text_fn and triage_priority_fn store nothing. save_text_feedback_fn stores only what scripts/feedback_store.py allows
(consent required; sensitive messages are never stored). Needs a signed-in user (your app already requires sign-in) and env var FEEDBACK_SALT. Region must match TriageTextService.region in the app."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ml", "scripts"))

from firebase_functions import https_fn, options
from firebase_admin import initialize_app, firestore
import hashlib

initialize_app()
import text_triage as tx            # noqa: E402  (loads lexicons; classifier optional)
import predict_priority as pp       # noqa: E402  (loads decision table; never needs the SVM file)
import feedback_store as fb         # noqa: E402

OPTS = dict(region="europe-west1", memory=options.MemoryOption.GB_1, timeout_sec=30, max_instances=20)


@https_fn.on_call(**OPTS)
def triage_text_fn(req: https_fn.CallableRequest):
    text = (req.data or {}).get("text") if isinstance(req.data, dict) else None
    return tx.triage_text(text)                         # never raises; unclear -> needs_clarification


@https_fn.on_call(**OPTS)
def triage_priority_fn(req: https_fn.CallableRequest):
    d = req.data if isinstance(req.data, dict) else {}
    payload = {**(d.get("answers") or {}), "category": d.get("category")}
    return pp.suggest_priority_safe(payload, d.get("subtype"))   # never raises


@https_fn.on_call(**OPTS)
def save_text_feedback_fn(req: https_fn.CallableRequest):
    """Call this AFTER the resident has confirmed the category. The app should ignore the answer: failure to save must never
    block or delay an emergency request."""
    try:
        uid = req.auth.uid if req.auth else None
        record, why = fb.prepare_record(req.data, uid, os.environ.get("FEEDBACK_SALT", ""))
        if record is None:
            return {"stored": False, "reason": why}
        doc_id = hashlib.sha256((record["contributor"] + record["text"].lower()).encode()).hexdigest()[:24]   # same text twice = one row
        record["created"] = firestore.SERVER_TIMESTAMP
        firestore.client().collection("text_feedback").document(doc_id).set(record)
        return {"stored": True}
    except Exception as e:                                       # noqa: BLE001
        return {"stored": False, "reason": f"error: {type(e).__name__}"}
