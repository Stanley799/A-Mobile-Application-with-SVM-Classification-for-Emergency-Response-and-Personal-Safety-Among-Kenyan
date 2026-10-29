// Gets the resident's position in a careful order and says WHY when it cannot. Works on Android and in a browser. Never throws.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum LocFail { serviceOff, denied, deniedForever, timeout, unavailable }

class ResolvedLocation {
  const ResolvedLocation({required this.latitude, required this.longitude, this.accuracyMeters, this.source = 'gps'});
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String source; // gps | manual
}

class LocationResult {
  const LocationResult.ok(ResolvedLocation this.location) : fail = null;
  const LocationResult.failed(LocFail this.fail) : location = null;
  final ResolvedLocation? location;
  final LocFail? fail;
  bool get ok => location != null;
}

String locFailMessage(LocFail f) => switch (f) {
  LocFail.serviceOff => 'Location is switched off on this device.',
  LocFail.denied => 'Location access was not allowed.',
  LocFail.deniedForever => 'Location access is blocked for this app.',
  LocFail.timeout => 'We could not get a location fix in time.',
  LocFail.unavailable => 'Your device could not work out where you are.',
};

String locFailHelp(LocFail f) {
  if (kIsWeb) {
    return switch (f) {
      LocFail.deniedForever || LocFail.denied => 'Click the padlock next to the web address, open Site settings, set Location to Allow, then press Try again.',
      _ => 'Check that Windows or your device allows your browser to use location, then press Try again.',
    };
  }
  return switch (f) {
    LocFail.serviceOff => 'Turn on Location (GPS) in your phone settings, then press Try again.',
    LocFail.deniedForever => 'Open the app settings, allow Location, then press Try again.',
    LocFail.denied => 'Press Try again and choose Allow.',
    _ => 'Move to an open area or turn on Wi-Fi, then press Try again.',
  };
}

Future<LocationResult> resolveLocation({bool askPermission = true}) async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) return const LocationResult.failed(LocFail.serviceOff);
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied && askPermission) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) return const LocationResult.failed(LocFail.deniedForever);
    if (p == LocationPermission.denied) return const LocationResult.failed(LocFail.denied);
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));
    } on TimeoutException {
      pos = null;
    } catch (_) {
      pos = null;
    }
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)));
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null && !kIsWeb) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null) return const LocationResult.failed(LocFail.timeout);
    return LocationResult.ok(ResolvedLocation(latitude: pos.latitude, longitude: pos.longitude, accuracyMeters: pos.accuracy));
  } catch (_) {
    return const LocationResult.failed(LocFail.unavailable);
  }
}

Future<void> openLocationHelp(LocFail f) async {
  try {
    if (kIsWeb) return;
    if (f == LocFail.serviceOff) {
      await Geolocator.openLocationSettings();
    } else if (f == LocFail.deniedForever) {
      await Geolocator.openAppSettings();
    }
  } catch (_) {/* nothing to do */}
}
