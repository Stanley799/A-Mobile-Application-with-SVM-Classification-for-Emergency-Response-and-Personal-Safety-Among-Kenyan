// All Firestore access for the responder side. Every write uses ONLY the keys that firestore.rules allows.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/models/dispatch_models.dart';

class ResponderOfferFeed {
  const ResponderOfferFeed({
    required this.offers,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final List<Offer> offers;
  final bool isFromCache;
  final bool hasPendingWrites;
}

class ResponderRepository {
  ResponderRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get uid => _auth.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _me =>
      _db.collection('responders').doc(uid);

  Future<String?> firstName() async {
    final snapshot = await _db.collection('users').doc(uid).get();
    final value = snapshot.data()?['firstName'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  Stream<ResponderRecord?> watchMe() => _me.snapshots().map(
    (s) => s.exists ? ResponderRecord.fromMap(s.id, s.data()!) : null,
  );

  /// Newest first. Needs the composite index offers(responderId ASC, createdAt DESC) from firestore.indexes.json.
  Stream<List<Offer>> watchOffers() => _db
      .collection('offers')
      .where('responderId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots()
      .map((q) => [for (final d in q.docs) Offer.fromMap(d.id, d.data())]);

  Stream<ResponderOfferFeed> watchOfferFeed() => _db
      .collection('offers')
      .where('responderId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots(includeMetadataChanges: true)
      .map(
        (q) => ResponderOfferFeed(
          offers: [for (final d in q.docs) Offer.fromMap(d.id, d.data())],
          isFromCache: q.metadata.isFromCache,
          hasPendingWrites: q.metadata.hasPendingWrites,
        ),
      );

  Stream<Offer?> watchOffer(String id) => _db
      .collection('offers')
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Offer.fromMap(s.id, s.data()!) : null);

  /// status: Available | Offline  (the server sets Busy and Available again around a job)
  Future<void> setAvailability(String status) => _me.update({
    'availabilityStatus': status,
    'lastSeenAt': FieldValue.serverTimestamp(),
  });

  Future<void> heartbeat(double lat, double lng) => _me.update({
    'currentLatitude': lat,
    'currentLongitude': lng,
    'lastSeenAt': FieldValue.serverTimestamp(),
  });

  /// status: accepted | declined | enroute | arrived | completed | withdrawn
  /// withdrawReason is required by the rules when standing down from a job the unit has taken.
  Future<void> respond(String offerId, String status, {String? withdrawReason}) {
    final data = <String, Object?>{
      'status': status,
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'withdrawReason': ?withdrawReason,
    };
    return _db.collection('offers').doc(offerId).update(data);
  }
}
