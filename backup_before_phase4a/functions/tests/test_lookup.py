import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dispatch import lookup, options


def test_every_category_has_types():
    for c in ["Medical Emergency", "Road Accident", "Fire & Rescue", "Security Threat", "Abduction", "Other / General", "Unknown new"]:
        assert lookup.wanted_types(c), c
    assert lookup.wanted_types("Security Threat") == ["police"]
    assert lookup.wanted_types("Medical Emergency", "sexual_violence")[0] == "hospital"


def test_places_nearby_parses_and_never_raises():
    sample = {"places": [{"id": "abc", "displayName": {"text": "Kilimani Police Station"}, "location": {"latitude": -1.29, "longitude": 36.78}, "formattedAddress": "Kilimani", "nationalPhoneNumber": "020 123"}, {"id": "x"}]}
    out = lookup.places_nearby("k", -1.3, 36.8, "police", http=lambda u, h, b: sample)
    assert len(out) == 1 and out[0]["id"] == "g_abc" and out[0]["type"] == "police" and out[0]["phones"] == ["020 123"] and out[0]["source"] == "google"
    def boom(u, h, b): raise OSError("net")
    assert lookup.places_nearby("k", -1.3, 36.8, "police", http=boom) == []
    assert lookup.places_nearby(None, -1.3, 36.8, "police") == []
    assert lookup.places_nearby("k", -1.3, 36.8, "bar", http=lambda u, h, b: sample) == []


def test_geocode_label():
    data = {"results": [{"formatted_address": "Waiyaki Way, Nairobi, Kenya", "address_components": [
        {"long_name": "Waiyaki Way", "types": ["route"]}, {"long_name": "Westlands", "types": ["sublocality", "sublocality_level_1"]}]}]}
    g = lookup.reverse_geocode("k", -1.26, 36.80, http=lambda u, h, b: data)
    assert g["label"] == "Waiyaki Way, Westlands"
    assert lookup.reverse_geocode(None, 0, 0) is None
    assert lookup.reverse_geocode("k", 0, 0, http=lambda u, h, b: {"results": []}) is None


def _fac(i, t, dlat):
    return {"id": i, "name": i, "type": t, "lat": -1.2921 + dlat, "lng": 36.8219, "phones": ["0700"], "status": "active", "verified": True}


def test_other_category_still_gets_options_and_road_accident_is_diverse():
    facs = [_fac("h1", "hospital", .01), _fac("h2", "hospital", .012), _fac("h3", "hospital", .014), _fac("p1", "police", .03), _fac("f1", "fire", .05)]
    inc = {"lat": -1.2921, "lng": 36.8219, "category": "Other / General", "subtype": None, "triageStatus": "pending", "userId": "u"}
    top, meta = options.build(inc, "Low", [], [], [], facs, "unfilled", 1000.0)
    assert top, "Other / General must still get picks"
    inc2 = dict(inc, category="Road Accident")
    top2, _ = options.build(inc2, "High", [], [], [], facs, "unfilled", 1000.0)
    kinds = {c["orgType"] for c in top2}
    assert "police" in kinds and "hospital" in kinds and len(top2) <= 3
