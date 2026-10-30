// Everything the administrator monitor reads and writes. Reads use the administrator claim; decisions
// the caller could forge go through Cloud Functions.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/models/dispatch_models.dart';

class OpsEvent {
  const OpsEvent({required this.id, required this.type, required this.at, required this.actorRole, required this.actorId, required this.data});
  final String id;
  final String type;
  final DateTime? at;
  final String actorRole;
  final String actorId;
  final Map<String, dynamic> data;

  factory OpsEvent.fromMap(String id, Map<String, dynamic> m) => OpsEvent(
    id: id,
    type: (m['type'] ?? '').toString(),
    at: _dt(m['at']),
    actorRole: (m['actorRole'] ?? '').toString(),
    actorId: (m['actorId'] ?? '').toString(),
    data: m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : const {},
  );
}

class SosAlert {
  const SosAlert({required this.id, required this.responderId, required this.orgName, required this.incidentId, required this.at, required this.status, required this.note});
  final String id;
  final String responderId;
  final String orgName;
  final String? incidentId;
  final DateTime? at;
  final String status;
  final String note;

  factory SosAlert.fromMap(String id, Map<String, dynamic> m) => SosAlert(
    id: id,
    responderId: (m['responderId'] ?? '').toString(),
    orgName: (m['orgName'] ?? 'Responder').toString(),
    incidentId: m['incidentId']?.toString(),
    at: _dt(m['at']),
    status: (m['status'] ?? 'open').toString(),
    note: (m['note'] ?? '').toString(),
  );
}

class TrackPoint {
  const TrackPoint({required this.ownerId, required this.latitude, required this.longitude, required this.at});
  final String ownerId;
  final double latitude;
  final double longitude;
  final DateTime? at;

  factory TrackPoint.fromMap(String id, Map<String, dynamic> m) => TrackPoint(
    ownerId: id,
    latitude: (m['lat'] as num?)?.toDouble() ?? 0,
    longitude: (m['lng'] as num?)?.toDouble() ?? 0,
    at: _dt(m['at']),
  );
}

class OpsAuditEntry {
  const OpsAuditEntry({required this.id, required this.action, required this.incidentId, required this.at, required this.detail});
  final String id;
  final String action;
  final String incidentId;
  final DateTime? at;
  final Map<String, dynamic> detail;

  factory OpsAuditEntry.fromMap(String id, Map<String, dynamic> m) => OpsAuditEntry(
    id: id,
    action: (m['action'] ?? '').toString(),
    incidentId: (m['incidentId'] ?? '').toString(),
    at: _dt(m['at']),
    detail: {
      for (final e in m.entries)
        if (e.key != 'action' && e.key != 'incidentId' && e.key != 'at' && e.value != null) e.key: e.value,
    },
  );
}

class OpsFacility {
  OpsFacility({required this.id, required this.name, required this.type, required this.phones, required this.address, required this.is24h, required this.status, required this.verified, required this.verifiedBy, required this.verifiedAt, required this.kind, required this.latitude, required this.longitude});
  final String id;
  final String name;
  final String type;
  final List<String> phones;
  final String address;
  final bool? is24h;
  final String status; // active | hidden
  final bool verified;
  final String verifiedBy;
  final DateTime? verifiedAt;
  final String kind; // place | hotline
  final double? latitude;
  final double? longitude;

  String get phone => phones.isEmpty ? '' : phones.first;

  factory OpsFacility.fromMap(String id, Map<String, dynamic> m) => OpsFacility(
    id: id,
    name: (m['name'] ?? '').toString(),
    type: (m['type'] ?? '').toString(),
    phones: [for (final p in (m['phones'] as List? ?? const [])) p.toString()],
    address: (m['address'] ?? '').toString(),
    is24h: m['is24h'] is bool ? m['is24h'] as bool : null,
    status: (m['status'] ?? 'active').toString(),
    verified: m['verified'] == true,
    verifiedBy: (m['verifiedBy'] ?? '').toString(),
    verifiedAt: _dt(m['verifiedAt']),
    kind: (m['kind'] ?? 'place').toString(),
    latitude: (m['lat'] as num?)?.toDouble(),
    longitude: (m['lng'] as num?)?.toDouble(),
  );
}

DateTime? _dt(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

class OpsRepository {
  OpsRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _fn = functions ?? FirebaseFunctions.instanceFor(region: region);

  /// Must equal REGION in functions/dispatch/config.py.
  static const region = 'europe-west1';
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  Stream<List<IncidentRecord>> watchIncidents() => _db
      .collection('incidents')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((q) => [for (final d in q.docs) IncidentRecord.fromMap(d.id, d.data())]);

  Stream<IncidentRecord?> watchIncident(String id) => _db.collection('incidents').doc(id).snapshots().map((s) => s.exists ? IncidentRecord.fromMap(s.id, s.data()!) : null);

  Stream<List<Offer>> watchOffers() => _db
      .collection('offers')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((q) => [for (final d in q.docs) Offer.fromMap(d.id, d.data())]);

  Stream<List<Offer>> watchOffersFor(String incidentId) => _db
      .collection('offers')
      .where('incidentId', isEqualTo: incidentId)
      .snapshots()
      .map((q) => [for (final d in q.docs) Offer.fromMap(d.id, d.data())]..sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000))));

  Stream<List<ResponderRecord>> watchResponders() => _db
      .collection('responders')
      .limit(300)
      .snapshots()
      .map((q) => [for (final d in q.docs) ResponderRecord.fromMap(d.id, d.data())]);

  Stream<List<SosAlert>> watchOpenSos() => _db
      .collection('sos_alerts')
      .where('status', isEqualTo: 'open')
      .snapshots()
      .map((q) => [for (final d in q.docs) SosAlert.fromMap(d.id, d.data())]..sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000))));

  Stream<List<OpsEvent>> watchEvents(String incidentId) => _db
      .collection('incidents')
      .doc(incidentId)
      .collection('events')
      .snapshots()
      .map((q) => [for (final d in q.docs) OpsEvent.fromMap(d.id, d.data())]);

  /// Administrator only (rules). The per-incident Timeline tab remains the detailed audit view.
  Stream<List<OpsAuditEntry>> watchAuditLogs() => _db
      .collection('auditLogs')
      .orderBy('at', descending: true)
      .limit(300)
      .snapshots()
      .map((q) => [for (final d in q.docs) OpsAuditEntry.fromMap(d.id, d.data())]);

  Stream<Map<String, TrackPoint>> watchTracks(String incidentId) => _db
      .collection('incidents')
      .doc(incidentId)
      .collection('tracks')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id: TrackPoint.fromMap(d.id, d.data())});

  Future<List<IncidentRecord>> closedIncidents({int limit = 500}) async {
    final q = await _db.collection('incidents').where('status', whereIn: ['Resolved', 'Cancelled']).orderBy('createdAt', descending: true).limit(limit).get();
    return [for (final d in q.docs) IncidentRecord.fromMap(d.id, d.data())];
  }

  Future<List<OpsFacility>> loadFacilities({int limit = 1000}) async {
    final q = await _db.collection('facilities').limit(limit).get();
    return [for (final d in q.docs) OpsFacility.fromMap(d.id, d.data())];
  }

  Future<void> updateFacility(String id, Map<String, dynamic> fields) => _db.collection('facilities').doc(id).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> addFacility(Map<String, dynamic> fields) => _db.collection('facilities').add({...fields, 'kind': 'place', 'source': 'admin', 'updatedAt': FieldValue.serverTimestamp()});

  /// Returns the caller's first name and phone (logged on the server). Never cache it beyond this screen.
  Future<({String firstName, String phone})> revealContact(String incidentId) async {
    final r = await _fn.httpsCallable('reveal_contact').call<dynamic>({'incidentId': incidentId});
    final d = Map<String, dynamic>.from(r.data as Map);
    return (firstName: (d['firstName'] ?? '').toString(), phone: (d['phone'] ?? '').toString());
  }

  Future<void> resolveSos(String sosId, String note) => _fn.httpsCallable('admin_resolve_sos').call<dynamic>({'sosId': sosId, 'note': note});


  Future<void> assign(String incidentId, String responderId, {String? role, required String reason}) => _fn
      .httpsCallable('admin_assign_responder')
      .call<dynamic>({'incidentId': incidentId, 'responderId': responderId, if (role != null) 'role': role, 'reason': reason});

  Future<void> close(String incidentId, String note) => _fn.httpsCallable('admin_close_incident').call<dynamic>({'incidentId': incidentId, 'note': note});

  /// Street label for the caller's coordinates (reverse geocode). Empty when the key is missing or the call fails.
  Future<String> streetLabel(double lat, double lng) async {
    try {
      final r = await _fn.httpsCallable('help_geocode').call<dynamic>({'lat': lat, 'lng': lng});
      final d = Map<String, dynamic>.from(r.data as Map);
      return d['ok'] == true ? (d['label'] ?? '').toString() : '';
    } catch (_) {
      return '';
    }
  }
}
