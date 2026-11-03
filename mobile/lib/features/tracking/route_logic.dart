// Pure route maths for live tracking. No Flutter imports, so it is fast to test and safe to reuse.
// Polyline coding is Google's encoded polyline format (precision 5), written here so the app needs no extra package.
import 'dart:math' as math;

const double _earthRadiusM = 6371000.0;

double _rad(double d) => d * math.pi / 180.0;

/// A latitude and longitude. Our own tiny class so this file has no map-package import.
class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is LatLngPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLngPoint($lat, $lng)';
}

/// Great-circle distance in metres.
double distanceMeters(LatLngPoint a, LatLngPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final s1 = math.sin(dLat / 2);
  final s2 = math.sin(dLng / 2);
  final h = s1 * s1 + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * s2 * s2;
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Decodes a Google encoded polyline (precision 5). Never throws: a malformed string gives the points read so far.
List<LatLngPoint> decodePolyline(String encoded) {
  final out = <LatLngPoint>[];
  if (encoded.isEmpty) return out;
  final units = encoded.codeUnits;
  for (final u in units) {
    if (u < 63 || u > 126) return <LatLngPoint>[];
  }
  var index = 0;
  var lat = 0;
  var lng = 0;

  int? nextValue() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (index >= units.length || shift > 30) return null;
      final b = units[index++] - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
    }
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < units.length) {
    final dLat = nextValue();
    if (dLat == null) break;
    final dLng = nextValue();
    if (dLng == null) break;
    lat += dLat;
    lng += dLng;
    out.add(LatLngPoint(lat / 1e5, lng / 1e5));
  }
  return out;
}

/// Exact inverse of [decodePolyline] for points with 5 decimals.
String encodePolyline(List<LatLngPoint> points) {
  final sb = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;

  void put(int delta) {
    var v = delta < 0 ? ~(delta << 1) : (delta << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  for (final p in points) {
    final la = (p.lat * 1e5).round();
    final ln = (p.lng * 1e5).round();
    put(la - prevLat);
    put(ln - prevLng);
    prevLat = la;
    prevLng = ln;
  }
  return sb.toString();
}

/// Where a position falls on a route.
class SnapResult {
  const SnapResult({required this.segment, required this.lat, required this.lng, required this.crossTrackM, required this.alongM});

  /// Index of the route point that starts the segment the position snapped to.
  final int segment;
  final double lat;
  final double lng;

  /// Distance from the route in metres.
  final double crossTrackM;

  /// Distance along the route, from its start to the snapped point, in metres.
  final double alongM;
}

double routeLengthM(List<LatLngPoint> route) {
  var total = 0.0;
  for (var i = 1; i < route.length; i++) {
    total += distanceMeters(route[i - 1], route[i]);
  }
  return total;
}

/// Snaps a position to the nearest point on the route. Null for an empty route.
SnapResult? snapToRoute(List<LatLngPoint> route, double lat, double lng) {
  if (route.isEmpty) return null;
  if (route.length == 1) {
    return SnapResult(segment: 0, lat: route[0].lat, lng: route[0].lng, crossTrackM: distanceMeters(route[0], LatLngPoint(lat, lng)), alongM: 0);
  }
  SnapResult? best;
  var cumulative = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final a = route[i];
    final b = route[i + 1];
    final segLen = distanceMeters(a, b);
    final lat0 = (a.lat + b.lat) / 2;
    final kx = math.cos(_rad(lat0)) * _earthRadiusM * math.pi / 180.0;
    const ky = _earthRadiusM * math.pi / 180.0;
    final abx = (b.lng - a.lng) * kx;
    final aby = (b.lat - a.lat) * ky;
    final apx = (lng - a.lng) * kx;
    final apy = (lat - a.lat) * ky;
    final len2 = abx * abx + aby * aby;
    var t = len2 == 0 ? 0.0 : (apx * abx + apy * aby) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final sLat = a.lat + (b.lat - a.lat) * t;
    final sLng = a.lng + (b.lng - a.lng) * t;
    final dx = (lng - sLng) * kx;
    final dy = (lat - sLat) * ky;
    final cross = math.sqrt(dx * dx + dy * dy);
    if (best == null || cross < best.crossTrackM) {
      best = SnapResult(segment: i, lat: sLat, lng: sLng, crossTrackM: cross, alongM: cumulative + segLen * t);
    }
    cumulative += segLen;
  }
  return best;
}

double remainingMeters(List<LatLngPoint> route, SnapResult snap) {
  final r = routeLengthM(route) - snap.alongM;
  return r < 0 ? 0 : r;
}

/// The route from the snapped point to the end, snapped point first. The part already travelled is not included.
List<LatLngPoint> trimRoute(List<LatLngPoint> route, SnapResult snap) {
  if (route.isEmpty) return <LatLngPoint>[];
  final start = LatLngPoint(snap.lat, snap.lng);
  final rest = snap.segment + 1 < route.length ? route.sublist(snap.segment + 1) : <LatLngPoint>[];
  return <LatLngPoint>[start, ...rest];
}

/// Tells when a unit has really left the route (three bad fixes in a row, and not too soon after the last reroute).
class OffRouteMonitor {
  int _count = 0;
  DateTime? _lastReroute;

  bool onFix({required DateTime now, required double crossTrackM, double? accuracyM}) {
    final limit = math.max(35.0, 1.5 * (accuracyM ?? 0));
    if (crossTrackM > limit) {
      _count++;
    } else {
      _count = 0;
    }
    final last = _lastReroute;
    final waited = last == null || now.difference(last) >= const Duration(seconds: 20);
    return _count >= 3 && waited;
  }

  void markRerouted(DateTime now) {
    _count = 0;
    _lastReroute = now;
  }
}

/// ETA from what is left of the route, with no network call. Null when the route has no length.
int? etaFromRemaining({required double remainingM, required double routeDistM, required double routeDurSec}) {
  if (routeDistM <= 0) return null;
  final v = (remainingM * routeDurSec / routeDistM).round();
  return v < 0 ? 0 : v;
}

/// True when the unit looks arrived: close to the target and slow. Only highlights a button; it never changes status.
bool arrivalSuggested({required double distToTargetM, required double speedMps, double? accuracyM}) {
  final limit = math.min(80.0, math.max(40.0, 1.5 * (accuracyM ?? 0)));
  return distToTargetM <= limit && speedMps < 3.0;
}

/// One turn-by-turn step of a route.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceM,
    required this.durationSec,
    this.polyline,
    this.endAlongM = 0,
  });

  final String instruction;
  final String? maneuver;
  final double distanceM;
  final double durationSec;
  final String? polyline;

  /// Distance from the route start to the end of this step. Filled by [withCumulativeEnds].
  final double endAlongM;

  RouteStep withEnd(double end) => RouteStep(
        instruction: instruction,
        maneuver: maneuver,
        distanceM: distanceM,
        durationSec: durationSec,
        polyline: polyline,
        endAlongM: end,
      );
}

/// Computes each step's cumulative end distance once.
List<RouteStep> withCumulativeEnds(List<RouteStep> steps) {
  var sum = 0.0;
  final out = <RouteStep>[];
  for (final s in steps) {
    sum += s.distanceM;
    out.add(s.withEnd(sum));
  }
  return out;
}

class NextStep {
  const NextStep({required this.step, required this.distToStepEndM});
  final RouteStep step;
  final double distToStepEndM;
}

/// The step the unit is on: the first whose end is further along than the unit.
NextStep? nextStep(List<RouteStep> steps, double alongM) {
  for (final s in steps) {
    if (s.endAlongM > alongM) {
      return NextStep(step: s, distToStepEndM: s.endAlongM - alongM);
    }
  }
  return null;
}

/// Joins the full-precision step lines into one route, dropping the repeated joint point. Steps without a line are skipped.
List<LatLngPoint> routeFromSteps(List<RouteStep> steps) {
  final out = <LatLngPoint>[];
  for (final s in steps) {
    final enc = s.polyline;
    if (enc == null || enc.isEmpty) continue;
    final pts = decodePolyline(enc);
    if (pts.isEmpty) continue;
    var from = 0;
    if (out.isNotEmpty && out.last == pts.first) from = 1;
    for (var i = from; i < pts.length; i++) {
      out.add(pts[i]);
    }
  }
  return out;
}

const int kMaxSharedPolylineChars = 8000;

/// What to store for the other side to draw: the full route if it fits, else the simplified one if it fits, else nothing.
String? chooseRouteForSharing({String? fullEncoded, String? overviewEncoded}) {
  if (fullEncoded != null && fullEncoded.isNotEmpty && fullEncoded.length <= kMaxSharedPolylineChars) return fullEncoded;
  if (overviewEncoded != null && overviewEncoded.isNotEmpty && overviewEncoded.length <= kMaxSharedPolylineChars) return overviewEncoded;
  return null;
}

/// The point [alongM] metres from the start of the route (clamped to the route).
LatLngPoint pointAtAlong(List<LatLngPoint> route, double alongM) {
  if (route.isEmpty) return const LatLngPoint(0, 0);
  if (route.length == 1 || alongM <= 0) return route.first;
  var cumulative = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final seg = distanceMeters(route[i], route[i + 1]);
    if (alongM <= cumulative + seg) {
      final t = seg == 0 ? 0.0 : (alongM - cumulative) / seg;
      if (t >= 1) return route[i + 1];
      return LatLngPoint(
        route[i].lat + (route[i + 1].lat - route[i].lat) * t,
        route[i].lng + (route[i + 1].lng - route[i].lng) * t,
      );
    }
    cumulative += seg;
  }
  return route.last;
}

/// The part of the route between two distances, with interpolated end points. [fromAlongM] after [toAlongM] gives just the end point.
List<LatLngPoint> routeSlice(List<LatLngPoint> route, double fromAlongM, double toAlongM) {
  if (route.isEmpty) return <LatLngPoint>[];
  final total = routeLengthM(route);
  final from = fromAlongM.clamp(0.0, total).toDouble();
  final to = toAlongM.clamp(0.0, total).toDouble();
  if (from >= to) return <LatLngPoint>[pointAtAlong(route, to)];
  final out = <LatLngPoint>[pointAtAlong(route, from)];
  var cumulative = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    cumulative += distanceMeters(route[i], route[i + 1]);
    if (cumulative > from && cumulative < to) out.add(route[i + 1]);
  }
  out.add(pointAtAlong(route, to));
  return out;
}

/// Follow zoom: closer in when slow, near the target, or near a turn. Further out when fast.
double zoomForSpeed({required double speedMps, double? distToTargetM, double? distToStepEndM}) {
  double base;
  if (speedMps < 3) {
    base = 17.5;
  } else if (speedMps < 8) {
    base = 17.0;
  } else if (speedMps < 15) {
    base = 16.3;
  } else {
    base = 15.6;
  }
  if (distToTargetM != null && distToTargetM <= 200) return 17.5;
  if (distToStepEndM != null && distToStepEndM <= 150) return math.max(base, 17.0);
  return base;
}
