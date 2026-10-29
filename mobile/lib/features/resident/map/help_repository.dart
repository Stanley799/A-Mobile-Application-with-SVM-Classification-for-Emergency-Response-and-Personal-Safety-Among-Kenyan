// Firestore and Cloud Function access for the resident help map. Streams never throw: errors become empty data so the screen stays usable.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'help_models.dart';

class IncidentInfo {
  const IncidentInfo({
    this.latitude,
    this.longitude,
    this.category,
    this.subtype,
    this.status,
    this.landmark = '',
    this.accuracyM,
    this.feedbackSafe,
    this.locationSource = 'gps',
  });
  final double? latitude;
  final double? longitude;
  final String? category;
  final String? subtype;
  final String? status;
  final String landmark;
  final double? accuracyM;
  final bool? feedbackSafe;
  final String locationSource;
  bool get hasLocation => latitude != null && longitude != null;
}

class HelpRepository {
  HelpRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions;

  final FirebaseFirestore _db;
  FirebaseFunctions? _functions;

  /// Created on first use: screens that never call a Cloud Function work without a Firebase app (tests).
  FirebaseFunctions get _fn => _functions ??= FirebaseFunctions.instanceFor(region: 'europe-west1');

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

  /// Where the alert is, and what kind of emergency it is.
  Stream<IncidentInfo> watchIncident(String incidentId) => _incident(incidentId).snapshots().map((s) {
        final d = s.data();
        final loc = d?['location'];
        final fb = d?['residentFeedback'];
        return IncidentInfo(
          latitude: loc is GeoPoint ? loc.latitude : null,
          longitude: loc is GeoPoint ? loc.longitude : null,
          category: d?['category']?.toString(),
          subtype: d?['subtype']?.toString(),
          status: d?['status']?.toString(),
          landmark: (d?['landmark'] ?? '').toString(),
          accuracyM: (d?['locationAccuracyM'] as num?)?.toDouble(),
          feedbackSafe: fb is Map && fb['safe'] is bool ? fb['safe'] as bool : null,
          locationSource: (d?['locationSource'] ?? 'gps').toString(),
        );
      }).handleError((_) {});

  /// The newest question from dispatch that has not been answered. null when there is none.
  Stream<CheckinQuestion?> watchCheckin(String incidentId) => _incident(incidentId)
      .collection('checkins')
      .orderBy('sentAt', descending: true)
      .limit(5)
      .snapshots()
      .map((q) {
        for (final d in q.docs) {
          final m = d.data();
          if (m['reply'] == null) return CheckinQuestion(id: d.id, text: (m['text'] ?? '').toString());
        }
        return null;
      })
      .handleError((_) {});

  /// The caller answers a dispatcher's question. firestore.rules allow ONLY reply + repliedAt, once.
  Future<bool> replyCheckin(String incidentId, String checkinId, String reply) async {
    try {
      await _incident(incidentId).collection('checkins').doc(checkinId).update({
        'reply': reply,
        'repliedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Landmark (in words) and how precise the fix was. firestore.rules allow ONLY these three keys, while the alert is open.
  Future<bool> saveContext(String incidentId, {String? landmark, double? accuracyM, String? source}) async {
    try {
      await _incident(incidentId).update({
        if (landmark != null) 'landmark': landmark.length > 120 ? landmark.substring(0, 120) : landmark,
        if (accuracyM != null) 'locationAccuracyM': accuracyM,
        if (source != null) 'locationSource': source,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Are you safe now?" answered once after the alert closed. Never required.
  Future<bool> saveFeedback(String incidentId, {required bool safe, int? rating}) async {
    try {
      await _incident(incidentId).update({
        'residentFeedback': {'safe': safe, if (rating != null) 'rating': rating},
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves a late or corrected location. firestore.rules allow ONLY location + updatedAt, and only while the alert is active.
  Future<bool> saveLocation(String incidentId, double lat, double lng) async {
    try {
      await _incident(incidentId).update({'location': GeoPoint(lat, lng), 'updatedAt': FieldValue.serverTimestamp()});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The resident closes their own alert. firestore.rules allow ONLY status/cancelledAt/updatedAt, and only while it is active.
  Future<bool> cancelIncident(String incidentId) async {
    try {
      await _incident(incidentId).update({
        'status': 'Cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

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

  /// Street label for "You are at ...". null when the server key is not set or Google has nothing.
  Future<String?> geocode(double lat, double lng) async {
    try {
      final r = await _fn.httpsCallable('help_geocode').call<dynamic>({'lat': lat, 'lng': lng});
      final m = Map<String, dynamic>.from(r.data as Map);
      final label = (m['label'] ?? '').toString();
      return m['ok'] == true && label.isNotEmpty ? label : null;
    } catch (_) {
      return null;
    }
  }

  /// Route from the resident to a place, drawn inside the app. Falls back to a straight-line estimate on the server.
  Future<RouteInfo?> directions(double fromLat, double fromLng, double toLat, double toLng) async {
    try {
      final r = await _fn.httpsCallable('help_directions').call<dynamic>({'fromLat': fromLat, 'fromLng': fromLng, 'toLat': toLat, 'toLng': toLng});
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
