"""All dispatch settings in one place. Change values here, nowhere else."""
REGION = "europe-west1"          # MUST equal the region used in the Dart app (TriageTextService.region) and be a region your Firestore database supports

WAVE_SIZE = {"High": 2, "Medium": 1, "Low": 1}   # responders asked at the same time for each needed role; the first to accept wins
MAX_OFFERS_PER_ROLE = 6          # after this many tries for one role the system stops and tells the resident to call 922/999
OFFER_SECONDS = 45               # time a responder has to answer (same as triage_schema routing.offer_timeout_seconds)
LOCATION_WAIT_SECONDS = 20       # wait this long for the resident's GPS before telling them to call 922
OTHER_HOLD_SECONDS = 25          # "Other / General" alerts wait this long for the category to be confirmed, then dispatch fail-safe
STALE_OFFLINE_SECONDS = 600      # an "Available" responder not heard from for 10 minutes is set to Offline
ACTIVE_WINDOW_SECONDS = 3600     # the engine stops working on an incident after one hour (an admin can still act)
MANUAL_OFFER_SECONDS = 90        # offers created by an administrator

ACTIVE_OFFER = ("offered", "accepted", "enroute", "arrived")      # still counts as "someone is on it"
ACCEPTED_OFFER = ("accepted", "enroute", "arrived", "completed")  # a unit has taken the job
CLOSED_OFFER = ("declined", "expired", "withdrawn")

# What each kind of responder organisation can do, unless an administrator sets "capabilities" on the responder.
CAPS_BY_TYPE = {
    "Ambulance": ["medical_transport"],
    "Fire": ["fire_suppression", "extrication"],
    "Police": ["law_enforcement"],
    "Hospital": ["medical_transport", "maternal_care", "gbv_care"],
    "Community": [],
    "Maritime": [],
    "Other": [],
}
ALL_CAPABILITIES = ["medical_transport", "fire_suppression", "extrication", "law_enforcement", "maternal_care", "gbv_care", "antivenom"]
CAP_LABELS = {
    "medical_transport": "Ambulance / medical transport", "fire_suppression": "Fire suppression", "extrication": "Extrication (cutting free)",
    "law_enforcement": "Police", "maternal_care": "Maternal care", "gbv_care": "GBV care", "antivenom": "Antivenom",
}
