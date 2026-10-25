// While a responder is on duty, tell dispatch where they are every 30 seconds. Foreground only (see the report's limits).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'responder_repository.dart';

class DutyHeartbeat {
  DutyHeartbeat(this._repo);

  final ResponderRepository _repo;
  Timer? _timer;

  /// Shows a short message when location is unavailable (null = fine).
  final ValueNotifier<String?> problem = ValueNotifier<String?>(null);

  bool get running => _timer != null;

  Future<bool> start() async {
    final ok = await _ensurePermission();
    if (!ok) return false;
    await _beat();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _beat());
    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      problem.value = 'Turn on location (GPS) to go on duty.';
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      problem.value = 'Allow location for this app to go on duty.';
      return false;
    }
    problem.value = null;
    return true;
  }

  Future<void> _beat() async {
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      await _repo.heartbeat(pos.latitude, pos.longitude);
      problem.value = null;
    } catch (e) {
      problem.value = 'Could not read your location. Dispatch may not see you.';
    }
  }

  void dispose() {
    stop();
    problem.dispose();
  }
}
