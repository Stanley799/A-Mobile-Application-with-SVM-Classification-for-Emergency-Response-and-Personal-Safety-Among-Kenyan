"""Push notifications to responders (Firebase Cloud Messaging). Sends the MINIMUM: priority, category, distance. Never any resident detail."""
from firebase_admin import messaging


def send_offer_push(db, offer):
    s = db.collection("deviceTokens").document(offer["responderId"]).get()
    token = (s.to_dict() or {}).get("token") if s.exists else None
    if not token:
        return
    label = offer["category"] + (" · " + offer["subtype"].replace("_", " ") if offer.get("subtype") and not offer.get("confidential") else "")
    messaging.send(messaging.Message(
        token=token,
        notification=messaging.Notification(title=f"NEW ALERT · {offer['priority'].upper()} PRIORITY", body=f"{label} · {offer['distanceKm']} km away"),
        data={"type": "offer", "offerId": offer["id"], "incidentId": offer["incidentId"]},
        android=messaging.AndroidConfig(priority="high", ttl=60, notification=messaging.AndroidNotification(channel_id="emergency_offers", sound="default")),
        apns=messaging.APNSConfig(headers={"apns-priority": "10"}, payload=messaging.APNSPayload(aps=messaging.Aps(sound="default")))))
