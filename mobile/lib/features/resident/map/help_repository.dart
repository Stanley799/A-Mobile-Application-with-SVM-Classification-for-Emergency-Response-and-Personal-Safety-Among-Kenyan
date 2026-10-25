// Firestore and Cloud Function access for the resident help map. Streams never throw: errors become empty data so the screen stays usable.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'help_models.dart';

class HelpRepository {
  HelpRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  DocumentReference<Map<String, dynamic>> _incident(String id) => _db.collection('incidents').doc(id);

  Stream<HelpState> watchOptions(String incidentId) => _incident(incidentId).collection('options').snapshots().map((q) {
        final opts = <HelpOption>[];
        HelpMeta meta = const HelpMeta();
        for (final d in q.docs) {
          if (d.id == 'meta') {
            meta = HelpMeta.fromMap(d.data());
          } else {
            opts.add(HelpOption.fromMap(d.id, d.data()));
          }
        }
        opts.sort((a, b) => a.rank.compareTo(b.rank));
        return HelpState(options: opts, meta: meta, loaded: true);
      }).handleError((_) {});

  /// Live positions keyed by responder id.
  Stream<Map<String, TrackPoint>> watchTracks(String incidentId) => _incident(incidentId).collection('tracks').snapshots().map((q) {
        final out = <String, TrackPoint>{};
        for (final d in q.docs) {
          final p = TrackPoint.tryParse(d.data());
          if (p != null) out[d.id] = p;
        }
        return out;
      }).handleError((_) {});

  /// The resident's own location for this alert, as written when the alert was sent.
  Stream<({double lat, double lng})?> watchIncidentLocation(String incidentId) => _incident(incidentId).snapshots().map((s) {
        final loc = s.data()?['location'];
        if (loc is GeoPoint) return (lat: loc.latitude, lng: loc.longitude);
        return null;
      }).handleError((_) {});

  /// Throws a FirebaseFunctionsException whose message is safe to show.
  Future<void> requestUnit(String incidentId, String responderId) => _fn.httpsCallable('resident_request_unit').call<dynamic>({'incidentId': incidentId, 'responderId': responderId});

  Future<RouteInfo?> route(String incidentId, String responderId) async {
    try {
      final r = await _fn.httpsCallable('incident_route').call<dynamic>({'incidentId': incidentId, 'responderId': responderId});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['ok'] != true) return null;
      return RouteInfo(
        points: decodePolyline((m['polyline'] ?? '').toString()),
        etaSeconds: (m['etaS'] as num?)?.toDouble() ?? 0,
        distanceMeters: (m['distanceM'] as num?)?.toInt() ?? 0,
        estimate: m['estimate'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
