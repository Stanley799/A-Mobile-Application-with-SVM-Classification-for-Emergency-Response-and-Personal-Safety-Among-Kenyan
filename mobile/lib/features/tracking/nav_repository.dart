// Firestore and Cloud Function access for the navigation map. Streams never throw: errors become empty data so the screen stays usable.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'route_logic.dart';
import 'track_logic.dart' show validCoordinate;

/// One live position from incidents/{id}/tracks/{uid}. Parsing is defensive: odd documents are skipped, never crash the map.
class NavTrack {
  const NavTrack({required this.lat, required this.lng, this.heading, this.speed, this.accuracy, this.at, this.sharing});

  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final double? accuracy;
  final DateTime? at;
  final String? sharing;

  LatLngPoint get position => LatLngPoint(lat, lng);

  static NavTrack? tryParse(Map<String, dynamic>? m) {
    if (m == null) return null;
    final la = m['lat'];
    final lo = m['lng'];
    if (la is! num || lo is! num) return null;
    if (!validCoordinate(la.toDouble(), lo.toDouble())) return null;
    final at = m['at'];
    return NavTrack(
      lat: la.toDouble(),
      lng: lo.toDouble(),
      heading: (m['heading'] as num?)?.toDouble(),
      speed: (m['speed'] as num?)?.toDouble(),
      accuracy: (m['accuracy'] as num?)?.toDouble(),
      at: at is Timestamp ? at.toDate() : (at is DateTime ? at : null),
      sharing: m['sharing']?.toString(),
    );
  }
}

/// A route with its turn-by-turn steps. [points] is empty when the server only had a straight-line estimate.
class NavRoute {
  const NavRoute({required this.points, required this.steps, required this.distanceM, required this.durationSec, this.estimate = false});

  final List<LatLngPoint> points;
  final List<RouteStep> steps;
  final double distanceM;
  final double durationSec;
  final bool estimate;
}

/// Reads the answer of the help_directions callable (asked with steps: true). Null when the server said no.
NavRoute? parseNavRoute(Object? data) {
  if (data is! Map) return null;
  final m = Map<String, dynamic>.from(data);
  if (m['ok'] != true) return null;
  final overview = (m['overviewPolyline'] ?? m['polyline'] ?? '').toString();
  final steps = <RouteStep>[];
  final raw = m['steps'];
  if (raw is List) {
    for (final s in raw) {
      if (s is! Map) continue;
      steps.add(RouteStep(
        instruction: (s['instruction'] ?? '').toString(),
        maneuver: s['maneuver']?.toString(),
        distanceM: (s['distanceM'] as num?)?.toDouble() ?? 0,
        durationSec: (s['durationSec'] as num?)?.toDouble() ?? 0,
        polyline: s['polyline']?.toString(),
      ));
    }
  }
  final withEnds = withCumulativeEnds(steps);
  final truncated = m['stepsTruncated'] == true;
  var points = truncated ? <LatLngPoint>[] : routeFromSteps(withEnds);
  if (points.length < 2) points = decodePolyline(overview);
  return NavRoute(
    points: points,
    steps: withEnds,
    distanceM: (m['distanceM'] as num?)?.toDouble() ?? 0,
    durationSec: ((m['durationSec'] ?? m['etaS']) as num?)?.toDouble() ?? 0,
    estimate: m['estimate'] == true,
  );
}

class NavRepository {
  NavRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _dbOverride = db,
        _fnOverride = functions;

  final FirebaseFirestore? _dbOverride;
  FirebaseFunctions? _fnOverride;

  /// Created on first use, so screens that never call them work without a Firebase app (tests).
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fn => _fnOverride ??= FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Live positions keyed by the uid that wrote them.
  Stream<Map<String, NavTrack>> watchTracks(String incidentId) => _db.collection('incidents').doc(incidentId).collection('tracks').snapshots().map((q) {
        final out = <String, NavTrack>{};
        for (final d in q.docs) {
          final t = NavTrack.tryParse(d.data());
          if (t != null) out[d.id] = t;
        }
        return out;
      }).handleError((_) {});

  /// A road route with steps from [from] to [to]. Null when the call fails; the caller keeps the route it already has.
  Future<NavRoute?> directions(LatLngPoint from, LatLngPoint to) async {
    try {
      final r = await _fn.httpsCallable('help_directions').call<dynamic>({
        'fromLat': from.lat,
        'fromLng': from.lng,
        'toLat': to.lat,
        'toLng': to.lng,
        'steps': true,
      });
      return parseNavRoute(r.data);
    } catch (_) {
      return null;
    }
  }
}
