// Everything the administrator dashboard reads and writes. Writes use only what firestore.rules allows
// (responder verification + capabilities) or call the admin Cloud Functions.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/models/dispatch_models.dart';

class AuditEntry {
  const AuditEntry(this.action, this.at, this.detail);
  final String action;
  final DateTime? at;
  final String detail;
}

class AdminRepository {
  AdminRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
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

  Stream<List<Offer>> watchOffers() => _db
      .collection('offers')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((q) => [for (final d in q.docs) Offer.fromMap(d.id, d.data())]);

  Stream<IncidentRecord?> watchIncident(String id) => _db.collection('incidents').doc(id).snapshots().map((s) => s.exists ? IncidentRecord.fromMap(s.id, s.data()!) : null);

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

  /// Needs the composite index auditLogs(incidentId ASC, at ASC) from firestore.indexes.json.
  Future<List<AuditEntry>> auditFor(String incidentId) async {
    final q = await _db.collection('auditLogs').where('incidentId', isEqualTo: incidentId).orderBy('at').get();
    return [
      for (final d in q.docs)
        AuditEntry(
          (d.data()['action'] ?? '') as String,
          (d.data()['at'] as Timestamp?)?.toDate(),
          [for (final k in ['role', 'wave', 'reason', 'responderId']) if (d.data()[k] != null) '$k: ${d.data()[k]}'].join(' · '),
        ),
    ];
  }

  Future<Map<String, dynamic>?> residentOf(String userId) async {
    final s = await _db.collection('users').doc(userId).get();
    return s.data();
  }

  /// status: Verified | Rejected | Suspended | Pending.  Allowed keys only (see firestore.rules).
  Future<void> review(String responderId, String status, {String? notes, List<String>? capabilities}) => _db.collection('responders').doc(responderId).update({
    'verificationStatus': status,
    'verificationNotes': notes,
    'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
    'verifiedAt': FieldValue.serverTimestamp(),
    if (capabilities != null) 'capabilities': capabilities,
  });

  Future<void> setCapabilities(String responderId, List<String> capabilities) => _db.collection('responders').doc(responderId).update({'capabilities': capabilities});

  Future<void> assign(String incidentId, String responderId, {String? role}) =>
      _fn.httpsCallable('admin_assign_responder').call<dynamic>({'incidentId': incidentId, 'responderId': responderId, if (role != null) 'role': role});

  Future<void> close(String incidentId, String note) => _fn.httpsCallable('admin_close_incident').call<dynamic>({'incidentId': incidentId, 'note': note});
}
