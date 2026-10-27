import sys
import urllib.request
import json

def test_geocoding(key):
    url = f"https://maps.googleapis.com/maps/api/geocode/json?latlng=-1.2921,36.8219&key={key}"
    try:
        req = urllib.request.urlopen(url)
        data = json.loads(req.read().decode())
        status = data.get("status")
        if status == "OK":
            print("PASS Geocoding API")
            return True
        else:
            print(f"FAIL Geocoding API: {status} - {data.get('error_message', '')}")
            return False
    except Exception as e:
        print(f"FAIL Geocoding API: {e}")
        return False

def test_places(key):
    url = f"https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=-1.2921,36.8219&radius=1000&type=hospital&key={key}"
    try:
        req = urllib.request.urlopen(url)
        data = json.loads(req.read().decode())
        status = data.get("status")
        if status in ("OK", "ZERO_RESULTS"):
            print("PASS Places API")
            return True
        else:
            print(f"FAIL Places API: {status} - {data.get('error_message', '')}")
            return False
    except Exception as e:
        print(f"FAIL Places API: {e}")
        return False

def test_routes(key):
    url = f"https://routes.googleapis.com/directions/v2:computeRoutes?key={key}"
    headers = {"Content-Type": "application/json", "X-Goog-FieldMask": "routes.distanceMeters"}
    body = {
        "origin": {"location": {"latLng": {"latitude": -1.2921, "longitude": 36.8219}}},
        "destination": {"location": {"latLng": {"latitude": -1.3000, "longitude": 36.8300}}},
        "travelMode": "DRIVE"
    }
    try:
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method="POST")
        resp = urllib.request.urlopen(req)
        print("PASS Routes API")
        return True
    except Exception as e:
        print(f"FAIL Routes API: {e}")
        return False

def main():
    key = "AIzaSyDcAvlh3KAyoWdrYnxeN9GiEYJ-RxGjjSQ"
    print("Testing API key against Geocoding, Places, and Routes...")
    test_geocoding(key)
    test_places(key)
    test_routes(key)

if __name__ == "__main__":
    main()
