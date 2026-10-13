"""Responder selection, the responder briefing and the 922 fallback. Reference logic for the Cloud Function and the Flutter screens.
Straight-line (haversine) distance is used. Real road ETA needs a paid routing service and is future work."""
import math
import triage_core as t

R = t.SCHEMA["routing"]

def haversine_km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(a))

def hotlines_for(subtype):
    """Verified hotlines only. 922 is always shown."""
    out = []
    for h in t.SCHEMA["hotlines"]:
        if not h["verified"]:
            continue
        if h["show_when"] == "always" or (subtype and subtype in h["show_when"].split(",")):
            out.append({"number": h["number"], "name": h["name"]})
    return out

def plan_dispatch(incident, responders, now):
    """incident: {lat, lng, priority, answers (normalized), subtype}
    responder: {id, name, type, phone, lat, lng, status, capabilities[], last_seen}   (times are epoch seconds)"""
    n, subtype, pr = incident["answers"], incident.get("subtype"), incident["priority"]
    if t.SCHEMA["subtype_rules"].get(subtype, {}).get("dispatch_responder", True) is False:
        # e.g. emotional distress: no ambulance or police. The app shows support resources and asks the safety question.
        return {"plan": [], "required": [], "preferred": [], "missing_roles": [], "escalate_922": False, "escalate_reason": "",
                "show_922_always": True, "hotlines": hotlines_for(subtype), "excluded": {}, "offer_timeout_seconds": R["offer_timeout_seconds"],
                "no_responder_reason": "support resources only; ask the safety question first"}
    required, preferred = t.required_capabilities(n, subtype)
    radius = R["max_radius_km"][pr]
    excluded, pool = {}, []
    for r in responders:
        if r["status"] != "available":
            excluded[r["id"]] = "not available"
        elif now - r["last_seen"] > R["heartbeat_max_age_seconds"]:
            excluded[r["id"]] = "location is out of date"
        else:
            d = haversine_km(incident["lat"], incident["lng"], r["lat"], r["lng"])
            if d > radius:
                excluded[r["id"]] = f"outside {radius} km"
            else:
                bonus = R["preferred_bonus_km"] * len(set(preferred) & set(r["capabilities"]))
                pool.append({**r, "distance_km": round(d, 2), "effective": max(0.0, d - bonus)})
    def ranked(cap):
        c = [r for r in pool if cap is None or cap in r["capabilities"]]
        return sorted(c, key=lambda r: (r["effective"], r["distance_km"], r["id"]))
    plan, covered, missing = [], set(), []
    roles = required if required else [None]
    for cap in roles:
        if cap is not None and cap in covered:
            continue
        cands = ranked(cap)
        if not cands:
            missing.append(cap or "any responder")
            continue
        best = cands[0]
        covered |= set(best["capabilities"]) & set(required)
        plan.append({"role": cap or "any responder", "responder": {k: best[k] for k in ("id", "name", "type", "phone", "distance_km")},
                     "covers": sorted(set(best["capabilities"]) & set(required + preferred)),
                     "fallback_ids": [c["id"] for c in cands[1:3]]})
    far = any(p["responder"]["distance_km"] > R["far_warning_km"] for p in plan) and pr == "High"
    return {"plan": plan[: R["max_cards_shown"]], "required": required, "preferred": preferred, "missing_roles": missing,
            "escalate_922": bool(missing) or far, "escalate_reason": ("no suitable responder: " + ", ".join(missing)) if missing else ("nearest responder is far away" if far else ""),
            "show_922_always": True, "hotlines": hotlines_for(subtype), "excluded": excluded,
            "offer_timeout_seconds": R["offer_timeout_seconds"]}

def build_briefing(incident, accepted=False, resident=None):
    """What a responder receives. Minimal by design. Resident contact details are released only after acceptance."""
    n, subtype, rule = incident["answers"], incident.get("subtype"), t.SCHEMA["subtype_rules"].get(incident.get("subtype"), {})
    flags = t.briefing_flags(n)
    text = incident.get("free_text", "") if rule.get("share_free_text_with_responder", True) else ""
    text = text[: t.SCHEMA["briefing"]["free_text_max_chars"]]
    b = {"incident_id": incident["id"], "category": n["category"], "subtype": subtype, "priority": incident["priority"],
         "priority_source": incident.get("priority_source", "model_table"),
         "location": {"lat": incident["lat"], "lng": incident["lng"]}, "people_count": n["people_count"], "flags": flags,
         "summary_text": f"{n['category']}{' (' + subtype + ')' if subtype else ''} | {incident['priority'].upper()} | {n['people_count']} {'person' if n['people_count'] == 1 else 'people'} | " + ("; ".join(flags) if flags else "no danger signs reported")}
    if text:
        b["free_text"] = text
    if rule.get("confidential"):
        b["confidential"] = True
    if accepted and resident:
        b["resident_first_name"], b["resident_phone"] = resident["first_name"], resident["phone"]
    return b

def contacts_to_notify(incident, trusted_contacts, survivor_opted_in=False):
    rule = t.SCHEMA["subtype_rules"].get(incident.get("subtype"), {})
    if rule.get("notify_trusted_contacts_by_default", True) or survivor_opted_in:
        return list(trusted_contacts)
    return []
