"""Safety check-in brain: decides what should happen next. Pure and idempotent, like dispatch/core.py.

evaluate(checkin, now) -> {"status", "esc", "actions", "changed"}
  The caller (a later step) writes status and esc FIRST, then performs the actions. Running evaluate again with the saved
  state returns no repeat actions, so a retried function never texts a contact twice.

States:  Active -> Grace -> Level1 (contacts) -> Level2 (responders) -> Closed
         CheckedIn and Cancelled are set by the user and are final.
Times are epoch seconds. `expiryTime` is the deadline (the field name the app already uses).
"""
import copy

TERMINAL = ("CheckedIn", "Cancelled", "Closed")
OPEN = ("Active", "Grace", "Level1", "Level2")
ACK_KINDS = ("checking", "cannot_reach")
METHODS = ("sms", "voice", "push")
OFFLINE_FALLBACK_DELAY_SEC = 90          # the phone waits this long after the server's moment before it texts by itself

DEFAULTS = {
    "graceSec": 300,                      # deadline -> contacts are told
    "remindBeforeSec": [300],             # reminders to the user before the deadline
    "graceRemindEverySec": 60,            # repeat reminder to the user during grace
    "contactSpacingSec": 120,             # gap between contact 1, contact 2, ...
    "voiceAfterSec": 300,                 # automated voice call this long after a contact's SMS, if nobody acknowledged
    "level2AfterSec": 900,                # contacts -> responders
    "ackExtendSec": 900,                  # "I'm checking on them" postpones responders by this long
    "maxEscalationSec": 7200,             # stop working on it after this
    "escalateToResponders": True,
    "shareLocation": False,
}


def settings(c):
    s = dict(DEFAULTS)
    s.update({k: v for k, v in (c.get("plan") or {}).items() if k in DEFAULTS and v is not None})
    return s


def contacts_of(c):
    """Active contacts in alert order. Each: id, name, phone, methods (default sms)."""
    out = []
    for i, ct in enumerate((c.get("plan") or {}).get("contacts") or []):
        if not isinstance(ct, dict) or not ct.get("phone") or ct.get("active") is False:
            continue
        methods = [m for m in (ct.get("methods") or ["sms"]) if m in METHODS] or ["sms"]
        out.append({"id": str(ct.get("id") or i), "name": ct.get("name") or "", "phone": ct["phone"], "methods": methods, "uid": ct.get("uid")})
    return out


def offline_fallback_at(expiry, grace_sec):
    """When the PHONE texts by itself if it never saw the server act (no data, or no way to hear back)."""
    return expiry + grace_sec + OFFLINE_FALLBACK_DELAY_SEC


def _fresh_esc(c):
    esc = copy.deepcopy(c.get("esc") or {})
    esc.setdefault("level", 0)
    esc.setdefault("reminded", [])
    esc.setdefault("smsSent", {})
    esc.setdefault("voiceCalled", {})
    esc.setdefault("pushSent", {})
    return esc


def evaluate(c, now):
    status = c.get("status") or "Active"
    esc = _fresh_esc(c)
    before = (status, copy.deepcopy(esc))
    actions = []
    if status in TERMINAL or status not in OPEN or c.get("expiryTime") is None:
        return _out(status, esc, actions, before)
    s = settings(c)
    expiry = float(c["expiryTime"])
    grace_end = expiry + s["graceSec"]
    contacts = contacts_of(c)

    if status == "Active":
        for lead in sorted(s["remindBeforeSec"], reverse=True):
            key = "pre%d" % lead
            if expiry - lead <= now < expiry and key not in esc["reminded"]:
                esc["reminded"].append(key)
                actions.append({"type": "remind_user", "kind": "before", "leadSec": lead})
        if now >= expiry:
            status = "Grace"
            if now < grace_end:
                esc["lastUserRemindAt"] = now
                actions.append({"type": "remind_user", "kind": "due"})
        else:
            return _out(status, esc, actions, before)

    if status == "Grace":
        if now < grace_end:
            last = esc.get("lastUserRemindAt", expiry)
            if now - last >= s["graceRemindEverySec"]:
                esc["lastUserRemindAt"] = now
                actions.append({"type": "remind_user", "kind": "overdue"})
            return _out(status, esc, actions, before)
        status = "Level1"
        esc["level"] = 1
        esc["level1At"] = grace_end

    if status == "Level1":
        l1 = esc["level1At"]
        ack = esc.get("ack")
        for i, ct in enumerate(contacts):
            due = l1 + i * s["contactSpacingSec"]
            if now >= due:
                if "sms" in ct["methods"] and ct["id"] not in esc["smsSent"]:
                    esc["smsSent"][ct["id"]] = now
                    actions.append({"type": "sms_contact", "contactId": ct["id"]})
                if "push" in ct["methods"] and ct.get("uid") and ct["id"] not in esc["pushSent"]:
                    esc["pushSent"][ct["id"]] = now
                    actions.append({"type": "push_contact", "contactId": ct["id"]})
            if (now >= due + s["voiceAfterSec"] and "voice" in ct["methods"] and ct["id"] not in esc["voiceCalled"]
                    and not ack):
                esc["voiceCalled"][ct["id"]] = now
                actions.append({"type": "voice_contact", "contactId": ct["id"]})
        l2_at = l1 + s["level2AfterSec"]
        if ack and ack.get("kind") == "checking":
            l2_at = max(l2_at, float(ack["at"]) + s["ackExtendSec"])
        cannot = bool(ack and ack.get("kind") == "cannot_reach")
        if s["escalateToResponders"] and (cannot or now >= l2_at):
            status = "Level2"
            esc["level"] = 2
            esc["level2At"] = now
            esc["incidentRequested"] = True
            actions.append({"type": "create_incident", "reason": "contact_cannot_reach" if cannot else "no_response"})
        elif now >= l1 + s["maxEscalationSec"]:
            status = "Closed"
            esc["closedReason"] = "unresolved"
        return _out(status, esc, actions, before)

    if status == "Level2":
        if esc.get("incidentResolved"):
            status = "Closed"
            esc["closedReason"] = "resolved"
        elif now >= float(esc.get("level2At", now)) + s["maxEscalationSec"]:
            status = "Closed"
            esc["closedReason"] = "unresolved"
    return _out(status, esc, actions, before)


def _out(status, esc, actions, before):
    return {"status": status, "esc": esc, "actions": actions, "changed": (status, esc) != before}


def acknowledge(c, contact_id, kind, now):
    """A contact pressed a button on the link or on the phone keypad. Returns the new esc, or None if it does not apply."""
    if kind not in ACK_KINDS or (c.get("status") or "Active") not in ("Level1", "Level2"):
        return None
    if contact_id not in {ct["id"] for ct in contacts_of(c)}:
        return None
    esc = _fresh_esc(c)
    prior = esc.get("ack")
    if prior and prior.get("kind") == "cannot_reach":
        return esc                           # "send help" is never downgraded
    esc["ack"] = {"by": contact_id, "kind": kind, "at": now}
    return esc


def on_user_close(c, new_status, now):
    """The user pressed I'm safe or cancelled. Returns {"status","esc","actions"}: stops everything and clears contacts that were alerted."""
    esc = _fresh_esc(c)
    actions = []
    if new_status not in ("CheckedIn", "Cancelled") or (c.get("status") or "Active") in TERMINAL:
        return {"status": c.get("status"), "esc": esc, "actions": actions}
    if esc.get("level", 0) >= 1 and not esc.get("allClearSent"):
        for cid in sorted(esc["smsSent"]):
            actions.append({"type": "sms_all_clear", "contactId": cid})
        esc["allClearSent"] = True
        if esc.get("incidentId"):
            actions.append({"type": "cancel_incident", "incidentId": esc["incidentId"]})
    return {"status": new_status, "esc": esc, "actions": actions}


# ---------- words ----------
def _hhmm(ts, tz_hours=3):
    t = int(ts) + tz_hours * 3600
    return "%02d:%02d" % ((t // 3600) % 24, (t // 60) % 60)


def _clip(text, n):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1].rstrip() + "..."


def sms_text(c, contact_name, link=None):
    """Plain text for a contact. Says it is NOT a confirmed emergency. Works with coordinates as text when there is no link."""
    who = _clip(c.get("ownerFirstName") or "Your contact", 30)
    parts = ["NUSURU: %s has not checked in (due %s)." % (who, _hhmm(c["expiryTime"]))]
    if c.get("note"):
        parts.append("Note: %s." % _clip(c["note"], 80))
    loc = c.get("lastLocation") or {}
    if loc.get("lat") is not None and loc.get("lng") is not None:
        seen = " at %s" % _hhmm(c["lastSeenAt"]) if c.get("lastSeenAt") else ""
        parts.append("Last seen%s: %.5f,%.5f." % (seen, loc["lat"], loc["lng"]))
    if link:
        parts.append("Open: %s" % link)
    parts.append("Please try to reach them. This is not a confirmed emergency.")
    return " ".join(parts)


def voice_script(c, contact_name):
    who = _clip(c.get("ownerFirstName") or "your contact", 30)
    s = "This is Nusuru. %s did not check in at %s. " % (who, _hhmm(c["expiryTime"]))
    if c.get("note"):
        s += "Their note says: %s. " % _clip(c["note"], 80)
    s += "Press 1 if you are checking on them. Press 2 if you cannot reach them and want help sent."
    return s


def all_clear_text(c):
    who = _clip(c.get("ownerFirstName") or "Your contact", 30)
    return "NUSURU: Update. %s is safe. Thank you for checking. No further action is needed." % who


# ---------- checks on a plan a user wants to create ----------
def validate_plan(duration_sec, plan):
    """Returns a list of plain-language problems (empty = fine)."""
    problems = []
    plan = plan or {}
    if not isinstance(duration_sec, (int, float)) or not 300 <= duration_sec <= 12 * 3600:
        problems.append("Choose a length between 5 minutes and 12 hours.")
    g = plan.get("graceSec", DEFAULTS["graceSec"])
    if not isinstance(g, (int, float)) or not 60 <= g <= 1800:
        problems.append("Grace period must be between 1 and 30 minutes.")
    cts = [c for c in (plan.get("contacts") or []) if isinstance(c, dict)]
    if len(cts) > 5:
        problems.append("At most 5 contacts.")
    if not cts and not plan.get("escalateToResponders", DEFAULTS["escalateToResponders"]):
        problems.append("Add a contact, or allow Nusuru responders to be alerted.")
    for ct in cts:
        phone = str(ct.get("phone") or "")
        digits = phone[1:] if phone.startswith("+") else phone
        if not digits.isdigit() or not 9 <= len(digits) <= 15:
            problems.append("A contact has an invalid phone number.")
            break
    for lead in plan.get("remindBeforeSec", DEFAULTS["remindBeforeSec"]) or []:
        if not isinstance(lead, (int, float)) or lead <= 0 or (isinstance(duration_sec, (int, float)) and lead >= duration_sec):
            problems.append("A reminder must come before the deadline.")
            break
    l2 = plan.get("level2AfterSec", DEFAULTS["level2AfterSec"])
    if not isinstance(l2, (int, float)) or not 300 <= l2 <= 3600:
        problems.append("Responders can be alerted 5 to 60 minutes after contacts.")
    return problems
