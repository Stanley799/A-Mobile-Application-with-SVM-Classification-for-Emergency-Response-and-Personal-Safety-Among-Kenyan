// Shares the resident's live position with the unit that took their alert (Uber-style mutual tracking).
// Runs only while the alert is open. firestore.rules stop accepting writes the moment the alert closes.
// Tracking is a bonus, never a blocker: any failure here is silent.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class ResidentTrackPublisher {
  ResidentTrackPublisher._();
  static final ResidentTrackPublisher instance = ResidentTrackPublisher._();

  final Set<String> _holders = {};
  StreamSubscription<Position>? _sub;
  Timer? _keepAlive;
  Position? _last;

  bool get running => _sub != null;

  /// Each open screen (alert sheet, help map) holds a reference; tracking runs while at least one is open.
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
    for (final iid in _holders) {
      try {
        await FirebaseFirestore.instance.collection('incidents').doc(iid).collection('tracks').doc(uid).set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'heading': pos.heading,
          'speed': pos.speed,
          'accuracy': pos.accuracy,
          'at': FieldValue.serverTimestamp(),
        });
      } catch (_) {/* offline, or the alert just closed: rules rejected it, which is fine */}
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _keepAlive?.cancel();
    _keepAlive = null;
    _holders.clear();
    _last = null;
  }
}
