"""The words a contact sees and hears: a small web page (two big buttons) and the voice call menu. Pure text, no Firebase."""
import html
from xml.sax.saxutils import escape as _x

from . import core


def _e(v):
    return html.escape(str(v if v is not None else ""), quote=True)


def _maps_link(loc):
    return "https://www.google.com/maps?q=%.6f,%.6f" % (loc["lat"], loc["lng"])


def contact_page(c, contact_name, query, message=None, share_location=False):
    """c is the core view of the check-in. query = the 3 link values (c, k, t) so the buttons can post them back."""
    status = c.get("status") or "Active"
    who = _e(c.get("ownerFirstName") or "Your contact")
    if status in ("CheckedIn", "Cancelled"):
        body = "<h1>%s is safe</h1><p>They checked in. Thank you for looking out for them. You do not need to do anything.</p>" % who
    elif status in ("Closed",):
        body = "<h1>This check-in is closed</h1><p>Nothing more is needed from you.</p>"
    else:
        due = core._hhmm(c["expiryTime"]) if c.get("expiryTime") else ""
        note = "<p class='note'>Their note: %s</p>" % _e(c.get("note")) if c.get("note") else ""
        loc = c.get("lastLocation") or {}
        where = ""
        if share_location and loc.get("lat") is not None and loc.get("lng") is not None:
            where = "<p><a href='%s'>Open their last known location on a map</a></p>" % _e(_maps_link(loc))
        hidden = "".join("<input type='hidden' name='%s' value='%s'>" % (k, _e(query.get(k))) for k in ("c", "k", "t"))
        body = (
            "<h1>%s has not checked in</h1><p>They were due at %s (Nairobi time). This is <b>not</b> a confirmed emergency. "
            "Please try to reach them.</p>%s%s"
            "<form method='post'>%s<button name='a' value='checking' class='b1'>I am checking on them</button>"
            "<button name='a' value='cannot_reach' class='b2'>I cannot reach them &mdash; send help</button></form>"
            "<p class='small'>If you press the second button, Nusuru alerts nearby responders for %s.</p>"
        ) % (who, _e(due), note, where, hidden, who)
    msg = "<div class='msg'>%s</div>" % _e(message) if message else ""
    return (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Nusuru check-in</title><style>body{font-family:system-ui,sans-serif;margin:0;padding:24px;background:#f6f7f6;color:#14201e}"
        "h1{font-size:24px}button{display:block;width:100%%;padding:18px;margin:12px 0;font-size:18px;font-weight:700;border:0;border-radius:14px;color:#fff}"
        ".b1{background:#0f766e}.b2{background:#b3261e}.note{background:#fff;padding:10px;border-radius:10px}.small{color:#5f6b68;font-size:13px}"
        ".msg{background:#e6f4ea;padding:12px;border-radius:10px;margin-bottom:14px}a{color:#0f766e}</style></head><body>"
        "<p><b>Nusuru</b> safety check-in</p>%s%s<p class='small'>Hello %s.</p></body></html>"
    ) % (msg, body, _e(contact_name))


def voice_menu_xml(script, callback_url):
    return ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response><GetDigits timeout=\"20\" numDigits=\"1\" callbackUrl=\"%s\">"
            "<Say>%s</Say></GetDigits><Say>We did not get your answer. Goodbye.</Say></Response>") % (_x(callback_url, {'"': "&quot;"}), _x(script))


def voice_reply_xml(kind):
    text = {"checking": "Thank you. We will give you more time. Goodbye.",
            "cannot_reach": "Thank you. We are alerting responders now. Goodbye."}.get(kind, "Sorry, that did not apply. Goodbye.")
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response><Say>%s</Say></Response>" % _x(text)
