import time, triage_core as t
from dispatch_logic import plan_dispatch, build_briefing, contacts_to_notify, haversine_km
NOW = 1_000_000.0
LAT, LNG = -1.2921, 36.8219  # Nairobi CBD
def R(i, name, typ, dlat, caps, status="available", age=10):  # dlat 0.009 = about 1 km north
    return dict(id=i, name=name, type=typ, phone="07xx", lat=LAT + dlat, lng=LNG, status=status, capabilities=caps, last_seen=NOW - age)
def inc(cat, sub=None, priority="High", **kw):
    base = dict(age_group="Adult", conscious="Yes", breathing="Yes", severe_bleeding="No", chest_pain="No", pregnant="No", trapped="No", hazard="No", weapon_involved="No", immediate_danger="No", people_count=1)
    return dict(id="INC1", lat=LAT, lng=LNG, priority=priority, subtype=sub, answers=t.normalize({**base, "category": cat, **kw}))
amb = R("A1", "Ambulance A", "Ambulance", .045, ["medical_transport"])
fire = R("F1", "Fire Unit", "Fire & Rescue Unit", .09, ["fire_suppression", "extrication"])
pol = R("P1", "Police Post", "Police", .02, ["law_enforcement"])
hosp = R("H1", "Hospital H", "Hospital", .054, ["medical_transport", "maternal_care", "gbv_care"])
pool = [amb, fire, pol, hosp]
print("haversine 1 deg lat =", round(haversine_km(0, 0, 1, 0), 1), "km (expected about 111.2)"); assert 111 < haversine_km(0, 0, 1, 0) < 111.4

p = plan_dispatch(inc("Road Accident", trapped="Yes", hazard="Yes"), pool, NOW)
roles = {x["role"]: x["responder"]["id"] for x in p["plan"]}; print("1 trapped + fire:", roles)
assert roles["medical_transport"] in ("A1", "H1") and roles["extrication"] == "F1" and "P1" not in [x["responder"]["id"] for x in p["plan"]] and not p["escalate_922"]
p = plan_dispatch(inc("Medical Emergency", pregnant="Yes"), pool, NOW); first = p["plan"][0]["responder"]["id"]; print("2 pregnant prefers maternal_care hospital (5.9 km vs ambulance 5.0 km):", first); assert first == "H1"
p = plan_dispatch(inc("Medical Emergency"), pool, NOW); print("3 plain medical nearest:", p["plan"][0]["responder"]["id"]); assert p["plan"][0]["responder"]["id"] == "A1"
p = plan_dispatch(inc("Security Threat", "sexual_violence", "Medium"), pool, NOW); print("4 sexual violence plan:", [x["responder"]["id"] for x in p["plan"]], "hotlines:", [h["number"] for h in p["hotlines"]])
assert "P1" not in [x["responder"]["id"] for x in p["plan"]] and p["plan"][0]["responder"]["id"] == "H1" and "1195" in [h["number"] for h in p["hotlines"]]
p = plan_dispatch(inc("Abduction"), pool, NOW); print("5 abduction:", [x["responder"]["id"] for x in p["plan"]]); assert [x["responder"]["id"] for x in p["plan"]] == ["P1"]
p = plan_dispatch(inc("Road Accident"), [R("A9", "Busy", "Ambulance", .01, ["medical_transport"], status="busy"), R("A8", "Stale", "Ambulance", .01, ["medical_transport"], age=500)], NOW)
print("6 busy and stale:", p["excluded"], "| escalate:", p["escalate_922"], p["escalate_reason"]); assert p["escalate_922"] and len(p["excluded"]) == 2
p = plan_dispatch(inc("Medical Emergency", priority="Low"), [R("A7", "Far", "Ambulance", .2, ["medical_transport"])], NOW); print("7 outside radius:", p["excluded"], p["escalate_922"]); assert p["escalate_922"]
p = plan_dispatch(inc("Medical Emergency"), [R("A6", "Far but inside", "Ambulance", .162, ["medical_transport"])], NOW); print("8 far warning:", p["escalate_922"], p["escalate_reason"]); assert p["escalate_922"] and p["plan"]
print("9 922 always shown:", all(x["show_922_always"] for x in [p]))

b = build_briefing({**inc("Security Threat", "sexual_violence", "Medium"), "free_text": "details that must not be shared"}, accepted=True, resident=dict(first_name="Amina", phone="0700"))
print("10 confidential briefing keys:", sorted(b)); assert "free_text" not in b and b["confidential"] and b["resident_phone"] == "0700"
b = build_briefing(inc("Road Accident", "boda_boda", trapped="Yes", hazard="Yes")); print("11 before accept:", b["summary_text"]); assert "resident_phone" not in b and "trusted_contacts" not in b
assert contacts_to_notify(inc("Security Threat", "sexual_violence", "Medium"), ["c1", "c2"]) == []
assert contacts_to_notify(inc("Security Threat", "sexual_violence", "Medium"), ["c1", "c2"], survivor_opted_in=True) == ["c1", "c2"]
assert contacts_to_notify(inc("Medical Emergency"), ["c1"]) == ["c1"]
print("12 trusted contacts: none for sexual violence unless the survivor opts in")
i = inc("Other / General", "emotional_distress", "Low"); p = plan_dispatch(i, pool, NOW)
print("13 emotional distress sends NO responder:", p["plan"], "| 922 shown:", p["show_922_always"]); assert p["plan"] == [] and not p["escalate_922"] and p["show_922_always"]
assert contacts_to_notify(i, ["c1"]) == []; print("14 trusted contacts are not told about emotional distress by default")
p = plan_dispatch(inc("Other / General", "mental_health_crisis", "High"), pool, NOW); print("15 self-harm crisis still gets a responder:", [x["responder"]["id"] for x in p["plan"]]); assert p["plan"]
print("\nALL DISPATCH TESTS PASSED")
