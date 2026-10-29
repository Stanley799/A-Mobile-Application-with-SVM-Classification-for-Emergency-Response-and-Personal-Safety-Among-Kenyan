// All Firestore access for the responder side. Every write uses ONLY the keys that firestore.rules allows.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/models/dispatch_models.dart';
import 'transport_models.dart';

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
  ResponderRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _db = db ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  FirebaseFunctions? _functions;

  /// Created on first use: screens that never call a Cloud Function work without a Firebase app (tests, previews).
  FirebaseFunctions get _fn =>
      _functions ??= FirebaseFunctions.instanceFor(region: 'europe-west1');

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

  // ---- Part 2: the four side-writes allowed on the unit's own offer ----

  /// Marks the first time the incoming alert was displayed. Rules accept this once, while the offer is open.
  Future<void> markSeen(String offerId) =>
      _db.collection('offers').doc(offerId).update({'seenAt': FieldValue.serverTimestamp()});

  /// After arriving at the scene: the unit starts taking the patient to a listed facility.
  Future<void> startTransport(
    String offerId, {
    required String destinationId,
    required String destinationName,
  }) => _db.collection('offers').doc(offerId).update({
    'transport': {
      'destinationId': destinationId,
      'destinationName': destinationName,
      'startedAt': FieldValue.serverTimestamp(),
    },
  });

  /// After reaching the hospital. Rules accept this once, on top of the existing transport map.
  Future<void> arriveAtHospital(String offerId) => _db
      .collection('offers')
      .doc(offerId)
      .update({'transport.arrivedAt': FieldValue.serverTimestamp()});

  /// Asks dispatch for another unit of one role. Rules accept this once per offer.
  Future<void> requestMoreUnits(
    String offerId, {
    required String role,
    required int count,
    String note = '',
  }) => _db.collection('offers').doc(offerId).update({
    'moreUnits': {
      'role': role,
      'count': count,
      'note': note,
      'requestedAt': FieldValue.serverTimestamp(),
    },
  });

  /// The unit's own notes, saved when the field loses focus. Never shared with the caller.
  Future<void> saveNote(String offerId, String note) => _db
      .collection('offers')
      .doc(offerId)
      .update({'note': note, 'noteUpdatedAt': FieldValue.serverTimestamp()});

  // ---- chat with dispatch ----

  Stream<List<JobMessage>> watchMessages(String incidentId) => _db
      .collection('incidents')
      .doc(incidentId)
      .collection('messages')
      .orderBy('at')
      .snapshots()
      .map((q) => [for (final d in q.docs) JobMessage.fromMap(d.id, d.data())]);

  Future<void> sendMessage(String incidentId, String text) =>
      _db.collection('incidents').doc(incidentId).collection('messages').add({
        'senderUid': uid,
        'senderRole': 'responder',
        'text': text,
        'at': FieldValue.serverTimestamp(),
      });

  // ---- SOS ----

  /// Creates a server-side SOS alert visible to dispatchers and administrators right away.
  Future<void> sendSos({String? incidentId}) => _fn
      .httpsCallable('responder_sos')
      .call<dynamic>({'incidentId': ?incidentId});

  // ---- transport destinations ----

  /// Hospitals and clinics within about 25 km of the scene, verified first.
  Future<List<TransportDestination>> hospitalsNear(double lat, double lng) async {
    const d = 0.25; // ~27 km band; the exact radius is applied on the phone
    try {
      final q = await _db
          .collection('facilities')
          .where('lat', isGreaterThanOrEqualTo: lat - d)
          .where('lat', isLessThanOrEqualTo: lat + d)
          .get();
      final all = <TransportDestination>{
        for (final s in q.docs) ?TransportDestination.fromMap(s.id, s.data()),
      };
      return rankDestinations(all, lat, lng);
    } catch (_) {
      return const [];
    }
  }

  Future<TransportDestination?> facility(String id) async {
    try {
      final s = await _db.collection('facilities').doc(id).get();
      final d = s.data();
      return d == null ? null : TransportDestination.fromMap(s.id, d);
    } catch (_) {
      return null;
    }
  }
}
