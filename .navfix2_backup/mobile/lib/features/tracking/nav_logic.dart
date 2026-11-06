// Pure decisions for the navigation map: which map style to show at a zoom, the accuracy circle, progress along a route,
// gliding between GPS fixes, when to ask for a new route, and how to frame two points. No Flutter, no Firebase: tested without a phone.
import 'dart:math' as math;

import 'route_logic.dart';
import 'track_logic.dart';

/// [overview] is calm (few labels, good for the whole trip). [detail] adds street names and landmarks (good for the last few hundred metres).
enum NavMapStyle { overview, detail }

/// Detail switches on at this zoom and off again a little lower, so the map does not flicker at the boundary.
const double kDetailZoomIn = 16.0;
const double kDetailZoomOut = 15.4;

NavMapStyle styleForZoom(double zoom, NavMapStyle current) {
  if (current == NavMapStyle.overview) {
    return zoom >= kDetailZoomIn ? NavMapStyle.detail : NavMapStyle.overview;
  }
  return zoom < kDetailZoomOut ? NavMapStyle.overview : NavMapStyle.detail;
}

/// Radius (metres) of the "how sure is this position" circle. Null when the fix is good enough that a circle is only clutter.
double? accuracyRadiusM(double? accuracyM) {
  if (accuracyM == null || accuracyM.isNaN || accuracyM <= 20) return null;
  return math.min(accuracyM, 1000.0);
}

/// Where a unit is on its route, and what is left.
class RouteProgress {
  const RouteProgress({
    required this.snap,
    required this.remainingM,
    required this.etaSec,
    required this.traveled,
    required this.remaining,
    required this.next,
  });

  final SnapResult snap;
  final double remainingM;
  final int? etaSec;

  /// The part already driven (drawn grey).
  final List<LatLngPoint> traveled;

  /// The part still to go, starting at the snapped point (drawn bold).
  final List<LatLngPoint> remaining;
  final NextStep? next;

  double get crossTrackM => snap.crossTrackM;
}

/// [steps] must already have their cumulative ends ([withCumulativeEnds]). Null when the route is empty.
RouteProgress? progressOnRoute({
  required List<LatLngPoint> route,
  required List<RouteStep> steps,
  required double lat,
  required double lng,
  required double routeDistM,
  required double routeDurSec,
}) {
  final snap = snapToRoute(route, lat, lng);
  if (snap == null) return null;
  final left = remainingMeters(route, snap);
  return RouteProgress(
    snap: snap,
    remainingM: left,
    etaSec: etaFromRemaining(remainingM: left, routeDistM: routeDistM, routeDurSec: routeDurSec),
    traveled: routeSlice(route, 0, snap.alongM),
    remaining: trimRoute(route, snap),
    next: nextStep(steps, snap.alongM),
  );
}

/// The marker position [t] (0..1) of the way from one fix to the next. Along the road when both fixes are on the route and moving forward,
/// otherwise a straight line, so the marker never cuts through a building while the real position is on a road.
LatLngPoint glidePoint({
  required LatLngPoint from,
  required LatLngPoint to,
  required double t,
  List<LatLngPoint> route = const <LatLngPoint>[],
  double maxCrossTrackM = 35,
}) {
  final tt = t.clamp(0.0, 1.0).toDouble();
  if (route.length >= 2) {
    final s0 = snapToRoute(route, from.lat, from.lng);
    final s1 = snapToRoute(route, to.lat, to.lng);
    if (s0 != null && s1 != null && s0.crossTrackM <= maxCrossTrackM && s1.crossTrackM <= maxCrossTrackM && s1.alongM >= s0.alongM) {
      return pointAtAlong(route, s0.alongM + (s1.alongM - s0.alongM) * tt);
    }
  }
  return lerpLatLng(from, to, tt);
}

/// When to ask the server for a fresh route. Always rate-limited, so a bad signal cannot cause a storm of requests.
bool needReroute({
  required bool hasRoute,
  required bool offRoute,
  required double destMovedM,
  required DateTime now,
  DateTime? lastRouteAt,
}) {
  final since = lastRouteAt == null ? null : now.difference(lastRouteAt);
  bool waited(int seconds) => since == null || since >= Duration(seconds: seconds);
  if (!hasRoute) return waited(15);
  if (offRoute) return waited(10);
  if (destMovedM >= 150) return waited(30);
  return since != null && since >= const Duration(seconds: 180);
}

/// A camera that frames all [points] inside a box of [widthPx] x [heightPx] pixels. Worked out by hand (Web Mercator), never with
/// newLatLngBounds, which fails on some devices and in the browser. One point gives a close street-level view.
({double lat, double lng, double zoom}) fitView({
  required List<LatLngPoint> points,
  required double widthPx,
  required double heightPx,
  double paddingPx = 40,
  double minZoom = 10,
  double maxZoom = 17.5,
}) {
  if (points.isEmpty) return (lat: -1.2921, lng: 36.8219, zoom: 12);
  if (points.length == 1) return (lat: points.first.lat, lng: points.first.lng, zoom: math.min(16.5, maxZoom));
  var minLa = points.first.lat, maxLa = minLa, minLo = points.first.lng, maxLo = minLo;
  for (final p in points) {
    minLa = math.min(minLa, p.lat);
    maxLa = math.max(maxLa, p.lat);
    minLo = math.min(minLo, p.lng);
    maxLo = math.max(maxLo, p.lng);
  }
  final usableW = math.max(widthPx - 2 * paddingPx, 100.0);
  final usableH = math.max(heightPx - 2 * paddingPx, 100.0);
  double y(double lat) {
    final sn = math.sin(lat * math.pi / 180);
    return math.log((1 + sn) / (1 - sn)) / 2;
  }

  final dLo = math.max((maxLo - minLo).abs(), 0.0006);
  final dY = math.max((y(maxLa) - y(minLa)).abs(), 0.00001);
  final zLo = math.log(usableW * 360 / (256 * dLo)) / math.ln2;
  final zLa = math.log(usableH * 2 * math.pi / (256 * dY)) / math.ln2;
  final zoom = (math.min(zLo, zLa) - 0.3).clamp(minZoom, maxZoom).toDouble();
  return (lat: (minLa + maxLa) / 2, lng: (minLo + maxLo) / 2, zoom: zoom);
}

/// "Now", "120 m", "1.5 km": distance to the next turn, rounded to 10 m so the number does not jitter.
String turnDistanceText(double m) {
  if (m < 30) return 'Now';
  final r = (m / 10).round() * 10;
  if (r >= 1000) return distanceText(m);
  return '$r m';
}

/// The small chip that says how fresh the other person's position is.
String freshnessLabel(TrackFreshness f, DateTime? updatedAt, DateTime now) {
  switch (f) {
    case TrackFreshness.live:
      return 'Live';
    case TrackFreshness.delayed:
      return 'Live · slow signal';
    case TrackFreshness.stale:
      final minutes = updatedAt == null ? 1 : math.max(1, (now.difference(updatedAt).inSeconds / 60).round());
      return 'Last seen $minutes min ago';
    case TrackFreshness.none:
      return 'Location not shared';
  }
}
