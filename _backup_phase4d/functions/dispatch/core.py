"""The dispatch brain. PURE: no Firebase, no network, no clock. Everything comes in as plain dicts and goes out as a list of actions,
so every rule can be tested here on a laptop. store.py applies the actions to Firestore.

incident  : {id, code, status, category, subtype, triageStatus, answers{}, lat, lng, createdAt(epoch s), freeText}
responder : {id, name, type, phone, lat, lng, status('available'..), capabilities[], last_seen(epoch s), verified(bool)}
offer     : {id, responderId, role, status, createdAt, expiresAt, wave, covers[], priority, location{lat,lng}, flags[], summary}
"""
from . import config as C
from . import labels
import triage_core as t
import dispatch_logic as dl

R = t.SCHEMA["routing"]


def effective_caps(responder):
    caps = responder.get("capabilities")
    if isinstance(caps, list) and caps:
        return [c for c in caps if c in C.ALL_CAPABILITIES]
    return list(C.CAPS_BY_TYPE.get(responder.get("type"), []))


def filled_answers(incident):
    """The answers saved so far; every question not answered yet is 'Unknown' (the safe reading)."""
    cat = incident["category"]
    given = incident.get("answers") or {}
    payload = {"category": cat}
    for q in t.SCHEMA["categories"][cat]["questions"]:
        spec = t.QUESTIONS[q]
        if spec["type"] == "int":
            v = given.get(q)
            payload[q] = int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else 1
        else:
            v = given.get(q)
            payload[q] = v if v in spec["values"] else "Unknown"
    return t.normalize(payload)


def server_priority(incident, table):
    """The priority the SERVER trusts. While nothing has been answered yet the fail-safe is High. Never raises."""
    if incident.get("triageStatus", "pending") == "pending":
        return {"priority": "High", "source": "safe_fallback", "reasons": ["Alert just received, details not given yet"]}
    try:
        n = filled_answers(incident)
        sub = incident.get("subtype")
        floor, reasons = t.rule_floor(n, sub)
        e = table["entries"]["|".join(str(n[f]) for f in t.FEATURES)]
        final = e["p"] if t.RANK[e["p"]] >= t.RANK[floor] else floor
        return {"priority": final, "source": "rule_floor" if t.RANK[floor] > t.RANK[e["p"]] else "model_table", "reasons": reasons}
    except Exception as ex:  # noqa: BLE001 - any problem fails SAFE
        return {"priority": "High", "source": "safe_fallback", "reasons": [f"Could not assess ({type(ex).__name__})"]}


def needs(incident):
    """(required roles, preferred roles, normalized answers). With no details yet: the category's base needs only."""
    cat = incident["category"]
    sub = incident.get("subtype")
    try:
        n = filled_answers(incident)
        req, pref = t.required_capabilities(n, sub)
        if incident.get("triageStatus", "pending") == "pending":      # unanswered "Unknown" must not invent extra roles
            base = t.SCHEMA["routing"]["base"][cat]
            req, pref = list(base["required"]), list(base["preferred"])
        return req, pref, n
    except Exception:  # noqa: BLE001
        base = t.SCHEMA["routing"]["base"].get(cat, {"required": [], "preferred": []})
        return list(base["required"]), list(base["preferred"]), None


def rank_candidates(incident, responders, role, preferred, now, priority, exclude_ids):
    """Available + verified + fresh + inside the radius, best first. Straight-line distance."""
    radius = R["max_radius_km"][priority]
    out = []
    for r in responders:
        if r["id"] in exclude_ids or not r.get("verified") or r.get("status") != "available":
            continue
        if r.get("lat") is None or r.get("lng") is None or now - (r.get("last_seen") or 0) > R["heartbeat_max_age_seconds"]:
            continue
        caps = effective_caps(r)
        if role is not None and role not in caps:
            continue
        d = dl.haversine_km(incident["lat"], incident["lng"], r["lat"], r["lng"])
        if d > radius:
            continue
        bonus = R["preferred_bonus_km"] * len(set(preferred) & set(caps))
        out.append({**r, "caps": caps, "distance_km": round(d, 2), "effective": max(0.0, d - bonus)})
    return sorted(out, key=lambda r: (r["effective"], r["distance_km"], r["id"]))


def _offer_covers(offer, role):
    return role in (offer.get("covers") or []) or offer.get("role") == role


def briefing_fields(incident, priority, required, n):
    """The minimal briefing stored on an offer (see schema 'briefing'). Resident contact is NOT here: it is added on accept."""
    inc = {"id": incident["id"], "lat": incident["lat"], "lng": incident["lng"], "priority": priority, "answers": n,
           "subtype": incident.get("subtype"), "free_text": incident.get("freeText", "") or ""}
    b = dl.build_briefing(inc)
    return {"flags": b["flags"], "summary": b["summary_text"], "peopleCount": b["people_count"], "confidential": bool(b.get("confidential")),
            "freeText": b.get("free_text", ""), "needs": list(required)}


def reconcile(incident, responders, offers, now, table):
    """Decide what to do right now. Returns {'actions': [...], 'dispatch': {...}}. Idempotent: running it twice changes nothing."""
    actions, status = [], incident.get("status")
    live = [o for o in offers if o["status"] in ("offered", "accepted", "enroute", "arrived")]
    # 1 closed incident: pull everything back
    if status in ("Cancelled", "Resolved"):
        for o in live:
            actions.append({"type": "withdraw_offer", "id": o["id"], "reason": "incident_cancelled" if status == "Cancelled" else "incident_resolved"})
        done = status == "Cancelled"
        keep = [] if done else [{"role": o.get("role"), "responderId": o["responderId"], "status": o["status"], "distanceKm": o.get("distanceKm")}
                                for o in offers if o["status"] in ("accepted", "enroute", "arrived", "completed")]
        return {"actions": actions, "dispatch": _summary("cancelled" if done else "completed", offers, False, "", None, keep, [])}
    # 2 expire offers that ran out of time
    expired = {o["id"] for o in offers if o["status"] == "offered" and o.get("expiresAt") is not None and o["expiresAt"] <= now}
    for oid in sorted(expired):
        actions.append({"type": "expire_offer", "id": oid})
    view = [({**o, "status": "expired"} if o["id"] in expired else o) for o in offers]
    # 3 emotional distress etc: support only
    if t.SCHEMA["subtype_rules"].get(incident.get("subtype"), {}).get("dispatch_responder", True) is False:
        return {"actions": actions, "dispatch": _summary("support_only", view, False, "Support resources only. No responder is sent.", None, [], [])}
    age = now - (incident.get("createdAt") or now)
    pr = server_priority(incident, table)
    priority = pr["priority"]
    # 4 "Other" alerts wait briefly for the category to be confirmed
    if incident["category"] == "Other / General" and incident.get("triageStatus", "pending") == "pending" and age < C.OTHER_HOLD_SECONDS:
        return {"actions": actions, "dispatch": _summary("awaiting_details", view, False, "", pr, [], [])}
    if incident["category"] == "Other / General" and priority == "Low" and incident.get("triageStatus") == "complete":
        return {"actions": actions, "dispatch": _summary("needs_review", view, False, "Low priority, no danger signs. A dispatcher will review.", pr, [], [])}
    # 5 location
    if incident.get("lat") is None or incident.get("lng") is None:
        if age > C.LOCATION_WAIT_SECONDS:
            return {"actions": actions, "dispatch": _summary("no_location", view, True, "We could not get your location. Call 922 or 999 and say where you are.", pr, [], [])}
        return {"actions": actions, "dispatch": _summary("waiting_location", view, False, "", pr, [], [])}
    required, preferred, n = needs(incident)
    roles = required if required else [None]
    resp_by_id = {r["id"]: r for r in responders}
    asked = {o["responderId"] for o in view}                                  # one offer per responder per incident, ever
    wave_size = C.WAVE_SIZE[priority]
    unfilled, far = [], False
    creates = []
    for role in roles:
        label = role or "any_responder"
        have = [o for o in view if o["status"] in C.ACCEPTED_OFFER and (role is None or _offer_covers(o, role))]
        flight = [o for o in view if o["status"] == "offered" and (role is None or _offer_covers(o, role))]
        if have or flight:
            continue
        tried = len([o for o in view if o.get("role") == label])
        if tried >= C.MAX_OFFERS_PER_ROLE:
            unfilled.append(label); continue
        cands = rank_candidates(incident, responders, role, preferred, now, priority, asked)
        if not cands:
            unfilled.append(label); continue
        wave = 1 + max([o.get("wave", 0) for o in view if o.get("role") == label] or [0])
        for c in cands[: max(1, min(wave_size, C.MAX_OFFERS_PER_ROLE - tried))]:
            far = far or (priority == "High" and c["distance_km"] > R["far_warning_km"])
            asked.add(c["id"])
            covers = sorted(set(c["caps"]) & set(required + preferred))
            creates.append({"type": "create_offer", "offer": {
                "id": f"{incident['id']}_{c['id']}", "incidentId": incident["id"], "incidentCode": incident.get("code") or incident["id"],
                "responderId": c["id"], "role": label, "wave": wave, "status": "offered", "createdAt": now, "expiresAt": now + C.OFFER_SECONDS,
                "distanceKm": c["distance_km"], "priority": priority, "category": incident["category"], "subtype": incident.get("subtype"),
                "covers": covers, "location": {"lat": incident["lat"], "lng": incident["lng"]}, **briefing_fields(incident, priority, required, n or {})}})
    actions += creates
    # 6 keep open offers up to date (location, priority, new answers)
    fresh = briefing_fields(incident, priority, required, n or {}) if n else None
    for o in view:
        if o["status"] in ("offered", "accepted", "enroute", "arrived"):
            want = {"priority": priority, "location": {"lat": incident["lat"], "lng": incident["lng"]}}
            if fresh:
                want.update({"flags": fresh["flags"], "summary": fresh["summary"], "peopleCount": fresh["peopleCount"], "needs": fresh["needs"]})
            diff = {k: v for k, v in want.items() if o.get(k) != v}
            if diff:
                actions.append({"type": "update_offer", "id": o["id"], "fields": diff})
    after = view + [c["offer"] for c in creates]
    state = _state(required, after)
    esc = bool(unfilled) or far
    reason = labels.unfilled_reason(unfilled) if unfilled else ("The nearest responder is far away. Call 922 or 999 as well." if far else "")
    units = [{"role": o.get("role"), "responderId": o["responderId"], "status": o["status"], "distanceKm": o.get("distanceKm")}
             for o in after if o["status"] in ("offered", "accepted", "enroute", "arrived", "completed")]
    if unfilled and state in ("dispatching", "partially_assigned") and not any(o["status"] == "offered" for o in after):
        state = "unfilled"
    return {"actions": actions, "dispatch": _summary(state, after, esc, reason, pr, units, unfilled)}


def _state(required, offers):
    roles = required if required else [None]
    stages = []
    for role in roles:
        got = [o for o in offers if o["status"] in C.ACCEPTED_OFFER and (role is None or _offer_covers(o, role))]
        if not got:
            return "partially_assigned" if stages else "dispatching"
        order = ["accepted", "enroute", "arrived", "completed"]
        stages.append(min(order.index(o["status"]) for o in got))
    return ["assigned", "enroute", "arrived", "completed"][min(stages)]


def _summary(state, offers, escalate, reason, pr, units, unfilled):
    return {"state": state, "escalate922": bool(escalate), "reason": reason, "priority": pr["priority"] if pr else None,
            "prioritySource": pr["source"] if pr else None, "priorityReasons": (pr or {}).get("reasons", []), "unfilled": unfilled, "units": units}


def resolve_acceptance(incident_roles, offers):
    """After an accept: a role can have only ONE accepted unit (the earliest). Later ones and waiting siblings are withdrawn.
    offers: all offers of the incident. Returns actions."""
    actions, taken = [], {}
    acc = sorted([o for o in offers if o["status"] in C.ACCEPTED_OFFER], key=lambda o: (o.get("respondedAt") or 0, o["id"]))
    for o in acc:
        role = o.get("role")
        if role in taken and o["status"] == "accepted":
            actions.append({"type": "withdraw_offer", "id": o["id"], "reason": "role_already_filled"})
        else:
            taken.setdefault(role, o["id"])
            for c in o.get("covers") or []:
                taken.setdefault(c, o["id"])
    for o in offers:
        if o["status"] == "offered" and (o.get("role") in taken or any(c in taken for c in (o.get("covers") or []) if c in (incident_roles or []))):
            actions.append({"type": "withdraw_offer", "id": o["id"], "reason": "another_unit_accepted"})
    return actions
