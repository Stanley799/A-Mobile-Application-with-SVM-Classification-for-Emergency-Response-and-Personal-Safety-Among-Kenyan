// Shares a responder's live position with the resident ONLY while they hold a job (accepted / en route / arrived).
// On Android this runs as a foreground service (a visible notification) so the system does not stop it. Stops by itself when the job ends.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/models/dispatch_models.dart';

class TrackPublisher {
  TrackPublisher._();
  static final TrackPublisher instance = TrackPublisher._();

  StreamSubscription<Position>? _sub;
  Timer? _keepAlive;
  Set<String> _incidents = {};
  Position? _last;

  /// Shown to the responder if tracking cannot run (null = fine).
  final ValueNotifier<String?> problem = ValueNotifier<String?>(null);

  bool get running => _sub != null;

  /// Call with the responder's full offers list every time it changes.
  void sync(Iterable<Offer> offers) {
    final want = <String>{for (final o in offers) if (o.status == 'accepted' || o.status == 'enroute' || o.status == 'arrived') o.incidentId};
    if (setEquals(want, _incidents)) return;
    _incidents = want;
    if (want.isEmpty) {
      stop();
    } else if (_sub == null) {
      _start();
    } else {
      _write(_last); // a second job started: publish immediately for it too
    }
  }

  Future<void> _start() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever || !await Geolocator.isLocationServiceEnabled()) {
        problem.value = 'Turn on location so the person you are helping can see you coming.';
        return;
      }
      final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
              intervalDuration: const Duration(seconds: 5),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'Emergency job in progress',
                notificationText: 'Sharing your live location with the person you are helping.',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);
      _sub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
        _last = pos;
        _write(pos);
      }, onError: (Object _) => problem.value = 'Lost your location signal.');
      _keepAlive = Timer.periodic(const Duration(seconds: 15), (_) => _write(_last)); // standing still still counts as "live"
      problem.value = null;
    } catch (_) {
      problem.value = 'Could not start live location.';
    }
  }

  Future<void> _write(Position? pos) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (pos == null || uid == null) return;
    for (final iid in _incidents) {
      try {
        await FirebaseFirestore.instance.collection('incidents').doc(iid).collection('tracks').doc(uid).set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'heading': pos.heading,
          'speed': pos.speed,
          'accuracy': pos.accuracy,
          'at': FieldValue.serverTimestamp(),
        });
      } catch (_) {/* offline or just finished: the next fix tries again */}
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _keepAlive?.cancel();
    _keepAlive = null;
    _incidents = {};
    _last = null;
  }
}
