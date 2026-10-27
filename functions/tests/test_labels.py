import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dispatch import labels


def test_no_internal_codes_reach_the_resident():
    msg = labels.unfilled_reason(["law_enforcement"])
    assert "law_enforcement" not in msg and "police unit" in msg and "999" in msg
    two = labels.unfilled_reason(["medical_transport", "law_enforcement", "law_enforcement"])
    assert "ambulance or police unit" in two and "_" not in two
    assert "responder" in labels.unfilled_reason([])
    assert "responder" in labels.unfilled_reason(["something_new"])
