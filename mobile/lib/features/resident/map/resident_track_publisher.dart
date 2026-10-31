// Shares the resident's live position with the unit that took their alert (Uber-style mutual tracking).
// Runs only while the alert is open. firestore.rules stop accepting writes the moment the alert closes.
// Tracking is a bonus, never a blocker: any failure here is silent.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class ResidentTrackPublisher {
  ResidentTrackPublisher._();
  static final ResidentTrackPublisher instance = ResidentTrackPublisher._();

  final Set<String> _holders = {};
  StreamSubscription<Position>? _sub;
  Timer? _keepAlive;
  Position? _last;

  bool get running => _sub != null;

  /// True while this incident's position is being shared.
  bool holds(String incidentId) => _holders.contains(incidentId);

  /// The resident shell holds one reference per open alert; the help map keeps none of its own.
  void acquire(String incidentId) {
    _holders.add(incidentId);
    if (_sub == null) _start();
  }

  void release(String incidentId) {
    _holders.remove(incidentId);
    if (_holders.isEmpty) stop();
  }

  Future<void> _start() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever || !await Geolocator.isLocationServiceEnabled()) return;
      _sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15)).listen((pos) {
        _last = pos;
        _write(pos);
      });
      _keepAlive = Timer.periodic(const Duration(seconds: 20), (_) => _write(_last)); // standing still still counts as "live"
    } catch (_) {/* never block the alert on tracking */}
  }

  Future<void> _write(Position? pos) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (pos == null || uid == null || _holders.isEmpty) return;
    await _forEachHolder((iid) async {
      await FirebaseFirestore.instance.collection('incidents').doc(iid).collection('tracks').doc(uid).set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'heading': pos.heading,
        'speed': pos.speed,
        'accuracy': pos.accuracy,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Runs [action] for each open alert. It walks a COPY of the holders, because
  /// release() can remove one while an earlier write is still in flight
  /// (that crashed with "Concurrent modification during iteration").
  Future<void> _forEachHolder(Future<void> Function(String incidentId) action) async {
    for (final iid in List<String>.of(_holders)) {
      if (!_holders.contains(iid)) continue; // released while we were busy: its alert is closed
      try {
        await action(iid);
      } catch (e) {
        // offline, or the alert just closed: rules rejected it, which is fine
        if (kDebugMode) debugPrint('track write skipped for $iid: ${e.runtimeType}');
      }
    }
  }

  @visibleForTesting
  Future<void> forEachHolderForTest(Future<void> Function(String incidentId) action) => _forEachHolder(action);

  void stop() {
    _sub?.cancel();
    _sub = null;
    _keepAlive?.cancel();
    _keepAlive = null;
    _holders.clear();
    _last = null;
  }
}
