"""Sends SMS and automated voice calls through Africa's Talking, and writes nothing else. `http` can be replaced in tests.

Credentials come from functions/.env (loaded by Firebase at deploy):
  AT_USERNAME, AT_API_KEY      required for real sending
  AT_SENDER_ID                 optional alphanumeric sender (needs approval in Kenya)
  AT_VOICE_FROM                the voice number Africa's Talking gave you (needed for calls)
  AT_SANDBOX=1                 use the sandbox (does not deliver real messages)
Without AT_USERNAME and AT_API_KEY everything runs in TEST MODE: nothing is sent, and the result says so.
"""
import json
import os
import urllib.parse
import urllib.request

LIVE_SMS = "https://api.africastalking.com/version1/messaging"
SANDBOX_SMS = "https://api.sandbox.africastalking.com/version1/messaging"
LIVE_VOICE = "https://voice.africastalking.com/call"
SANDBOX_VOICE = "https://voice.sandbox.africastalking.com/call"
SMS_OK_CODES = (100, 101, 102)           # Processed, Sent, Queued


def _env(k):
    return os.environ.get(k, "").strip()


def configured():
    return bool(_env("AT_USERNAME") and _env("AT_API_KEY"))


def normalize_phone(p):
    """Kenyan numbers in any common spelling -> +2547XXXXXXXX. Other international numbers keep their +. Returns '' if unusable."""
    s = "".join(ch for ch in str(p or "") if ch.isdigit() or ch == "+")
    if s.startswith("+"):
        digits = s[1:]
    elif s.startswith("00"):
        digits = s[2:]
    elif s.startswith("0") and len(s) == 10:
        digits = "254" + s[1:]
    elif len(s) == 9 and s[0] in "71":
        digits = "254" + s
    else:
        digits = s
    if not digits.isdigit() or not 9 <= len(digits) <= 15:
        return ""
    return "+" + digits


def mask(phone):
    p = str(phone or "")
    return p[:4] + "***" + p[-3:] if len(p) > 8 else "***"


def _post(url, headers, fields, http=None):
    if http is not None:
        return http(url, headers, fields)
    req = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode("utf-8"), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=15) as r:                       # noqa: S310 (fixed https URLs above)
        return r.status, r.read().decode("utf-8", "replace")


def send_sms(to, text, http=None):
    """-> {"ok": bool, "mode": "live"|"test", "detail": str}. Never raises."""
    to = normalize_phone(to)
    if not to:
        return {"ok": False, "mode": "live", "detail": "invalid phone number"}
    if not configured():
        return {"ok": True, "mode": "test", "detail": "TEST MODE: nothing was sent"}
    url = SANDBOX_SMS if _env("AT_SANDBOX") == "1" else LIVE_SMS
    fields = {"username": _env("AT_USERNAME"), "to": to, "message": text}
    if _env("AT_SENDER_ID"):
        fields["from"] = _env("AT_SENDER_ID")
    headers = {"apiKey": _env("AT_API_KEY"), "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"}
    try:
        status, body = _post(url, headers, fields, http)
        rec = (((json.loads(body) or {}).get("SMSMessageData") or {}).get("Recipients") or [{}])[0]
        code = rec.get("statusCode")
        ok = status in (200, 201) and code in SMS_OK_CODES
        return {"ok": ok, "mode": "live", "detail": str(rec.get("status") or body)[:120]}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "mode": "live", "detail": "%s: %s" % (type(e).__name__, e)[:120]}


def send_voice(to, client_request_id, http=None):
    """Starts an automated call. Africa's Talking then asks OUR voice function what to say (set its URL on the voice number)."""
    to = normalize_phone(to)
    if not to:
        return {"ok": False, "mode": "live", "detail": "invalid phone number"}
    if not configured():
        return {"ok": True, "mode": "test", "detail": "TEST MODE: no call was made"}
    if not _env("AT_VOICE_FROM"):
        return {"ok": False, "mode": "live", "detail": "AT_VOICE_FROM is not set"}
    url = SANDBOX_VOICE if _env("AT_SANDBOX") == "1" else LIVE_VOICE
    fields = {"username": _env("AT_USERNAME"), "from": _env("AT_VOICE_FROM"), "to": to, "clientRequestId": client_request_id}
    headers = {"apiKey": _env("AT_API_KEY"), "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"}
    try:
        status, body = _post(url, headers, fields, http)
        entry = ((json.loads(body) or {}).get("entries") or [{}])[0]
        ok = status in (200, 201) and str(entry.get("status")) == "Queued"
        return {"ok": ok, "mode": "live", "detail": str(entry.get("status") or body)[:120]}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "mode": "live", "detail": "%s: %s" % (type(e).__name__, e)[:120]}
