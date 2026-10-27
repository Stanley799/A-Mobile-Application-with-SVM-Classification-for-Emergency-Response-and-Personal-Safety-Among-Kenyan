"""Human wording for the resident. Internal role codes (law_enforcement, ...) must never reach a person in an emergency."""
ROLE_NAMES = {
    "law_enforcement": "police unit", "fire_suppression": "fire unit", "extrication": "rescue unit", "medical_transport": "ambulance",
    "maternal_care": "maternity unit", "gbv_care": "support unit", "antivenom": "antivenom hospital",
}


def role_names(roles):
    out = []
    for r in roles or []:
        n = ROLE_NAMES.get(r, "responder")
        if n not in out:
            out.append(n)
    return out


def _join(names):
    if len(names) <= 1:
        return "".join(names)
    return ", ".join(names[:-1]) + " or " + names[-1]


def unfilled_reason(unfilled):
    """'No registered police unit is free right now. Call 999 or 922, or use the nearby places on the map.'"""
    names = role_names(unfilled) or ["responder"]
    return f"No registered {_join(names)} is free right now. Call 999 or 922, or use the nearby places on the map."
