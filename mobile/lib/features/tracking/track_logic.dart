// Pure rules for sharing and showing a live position. No Flutter, no Firebase: tested without a phone.
import 'dart:math' as math;

import 'route_logic.dart';

double _rad(double d) => d * math.pi / 180.0;
double _deg(double r) => r * 180.0 / math.pi;

/// Great-circle distance in metres between two coordinates.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) =>
    distanceMeters(LatLngPoint(lat1, lng1), LatLngPoint(lat2, lng2));

/// Compass bearing 0..360 from the first point to the second.
double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
  final dLng = _rad(lng2 - lng1);
  final y = math.sin(dLng) * math.cos(_rad(lat2));
  final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) - math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(dLng);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Whether a new GPS fix should be written. Keeps writes useful and cheap.
bool shouldWriteTrack({required DateTime now, DateTime? lastWriteAt, required double movedMeters, double? accuracyM}) {
  final age = lastWriteAt == null ? null : now.difference(lastWriteAt);
  if (age != null && age < const Duration(seconds: 3)) return false;
  final poor = accuracyM != null && accuracyM > 150;
  if (poor && age != null && age < const Duration(seconds: 30)) return false;
  if (age == null) return true;
  if (movedMeters >= 10) return true;
  return age >= const Duration(seconds: 20);
}

enum TrackFreshness { live, delayed, stale, none }

enum TrackSharing { live, paused, stopped }

/// Reads the `sharing` value. Older documents have none: they count as live.
TrackSharing sharingOf(String? sharing) => switch (sharing) {
      'paused' => TrackSharing.paused,
      'stopped' => TrackSharing.stopped,
      _ => TrackSharing.live,
    };

/// How fresh a position is. Paused, stopped or never written gives [TrackFreshness.none].
TrackFreshness freshnessOf(DateTime now, DateTime? updatedAt, String? sharing) {
  if (updatedAt == null) return TrackFreshness.none;
  if (sharingOf(sharing) != TrackSharing.live) return TrackFreshness.none;
  final age = now.difference(updatedAt);
  if (age <= const Duration(seconds: 15)) return TrackFreshness.live;
  if (age <= const Duration(seconds: 45)) return TrackFreshness.delayed;
  return TrackFreshness.stale;
}

enum FollowTarget { caller, reported }

/// The caller's phone is followed only when it is fresh and accurate; otherwise the reported location.
FollowTarget chooseDefaultTarget({required TrackFreshness callerFreshness, double? callerAccuracyM}) {
  final fresh = callerFreshness == TrackFreshness.live || callerFreshness == TrackFreshness.delayed;
  if (fresh && callerAccuracyM != null && callerAccuracyM <= 100) return FollowTarget.caller;
  return FollowTarget.reported;
}

/// A phone reports a meaningless heading when standing still, so keep the last one until it moves.
double effectiveHeading({double? lastHeading, double? newHeading, double? speedMps}) {
  if (newHeading != null && newHeading >= 0 && newHeading <= 360 && speedMps != null && speedMps >= 1.0) {
    return newHeading;
  }
  return lastHeading ?? 0;
}

/// Moves [prev] towards [target] along the shortest arc.
double smoothBearing(double prev, double target, {double alpha = 0.3}) {
  final diff = ((target - prev + 540) % 360) - 180;
  return (prev + alpha * diff + 360) % 360;
}

/// A point between [a] and [b], taking the short way across longitude 180.
LatLngPoint lerpLatLng(LatLngPoint a, LatLngPoint b, double t) {
  final dLng = ((b.lng - a.lng + 540) % 360) - 180;
  final lng = (((a.lng + dLng * t) + 540) % 360) - 180;
  return LatLngPoint(a.lat + (b.lat - a.lat) * t, lng);
}

/// Words for an ETA. Never promises ("arriving in"); `lang` is `en` or `sw`.
String etaText(int? sec, {String lang = 'en'}) {
  final sw = lang == 'sw';
  if (sec == null) return sw ? 'Muda haujapatikana' : 'ETA not available';
  if (sec < 60) return sw ? 'Chini ya dakika moja' : 'Less than a minute';
  final minutes = (sec / 60).round();
  if (minutes >= 90) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return sw ? 'Takriban saa $h dakika $m' : 'About $h h $m min';
  }
  return sw ? 'Takriban dakika $minutes' : 'About $minutes min';
}

/// The big number on the ETA card: "5 min", "1 h 05 min", "<1 min", or a dash.
String bigEtaText(int? sec) {
  if (sec == null) return '–';
  if (sec < 60) return '<1 min';
  final minutes = (sec / 60).round();
  if (minutes >= 60) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h h $m min';
  }
  return '$minutes min';
}

String distanceText(double m) {
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

/// Clock time of arrival (24 hour, local) for an ETA in seconds, or a dash.
String arrivalClock(DateTime now, int? sec) {
  if (sec == null) return '–';
  final t = now.add(Duration(seconds: sec));
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

bool validCoordinate(double lat, double lng) {
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  if (lat == 0 && lng == 0) return false;
  return true;
}
