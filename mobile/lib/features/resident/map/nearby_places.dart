// Directory places near the resident, read straight from Firestore (the `facilities` collection, readable by signed-in users).
// Filtering and sorting are pure functions so they can be tested. The query is a latitude band; the rest is done on the phone.
import 'package:cloud_firestore/cloud_firestore.dart';

import 'emergency_layers.dart';
import 'help_models.dart' show haversineKm;

class NearbyPlace {
  const NearbyPlace({required this.id, required this.name, required this.type, this.latitude, this.longitude, this.phones = const [], this.is24h, this.verified = false, this.address = '', this.distanceKm});
  final String id;
  final String name;
  final PlaceType type;
  final double? latitude;
  final double? longitude;
  final List<String> phones;
  final bool? is24h;
  final bool verified;
  final String address;
  final double? distanceKm;

  bool get hasPosition => latitude != null && longitude != null;
  String get phone => phones.isEmpty ? '' : phones.first;

  NearbyPlace withDistance(double? km) => NearbyPlace(id: id, name: name, type: type, latitude: latitude, longitude: longitude, phones: phones, is24h: is24h, verified: verified, address: address, distanceKm: km);

  static NearbyPlace? fromMap(String id, Map<String, dynamic> m) {
    final type = placeTypeOf(m['type']?.toString());
    if (type == null || (m['status'] ?? 'active') != 'active') return null;
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    return NearbyPlace(
      id: id,
      name: name,
      type: type,
      latitude: (m['lat'] as num?)?.toDouble(),
      longitude: (m['lng'] as num?)?.toDouble(),
      phones: [for (final p in (m['phones'] as List? ?? const [])) p.toString()],
      is24h: m['is24h'] is bool ? m['is24h'] as bool : null,
      verified: m['verified'] == true,
      address: (m['address'] ?? '').toString(),
    );
  }
}

/// Keeps places inside [radiusKm], adds distances, sorts nearest first (call-only places without coordinates go last), and keeps at most
/// [perType] of each kind.
List<NearbyPlace> rankNearby(List<NearbyPlace> all, double lat, double lng, {double radiusKm = 12, int perType = 6}) {
  final withDist = <NearbyPlace>[];
  for (final p in all) {
    if (p.hasPosition) {
      final d = haversineKm(lat, lng, p.latitude!, p.longitude!);
      if (d <= radiusKm) withDist.add(p.withDistance(d));
    } else {
      withDist.add(p.withDistance(null));
    }
  }
  withDist.sort((a, b) {
    if (a.distanceKm == null && b.distanceKm == null) return a.name.compareTo(b.name);
    if (a.distanceKm == null) return 1;
    if (b.distanceKm == null) return -1;
    return a.distanceKm!.compareTo(b.distanceKm!);
  });
  final count = <PlaceType, int>{};
  final out = <NearbyPlace>[];
  for (final p in withDist) {
    final n = count[p.type] ?? 0;
    if (n >= perType) continue;
    count[p.type] = n + 1;
    out.add(p);
  }
  return out;
}

class NearbyRepository {
  NearbyRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  /// About 700 small reads for a 12 km band of Nairobi. Called once per screen open, not on every move.
  Future<List<NearbyPlace>> load(double lat, double lng, {double radiusKm = 12}) async {
    final d = radiusKm / 111.0;
    final out = <String, NearbyPlace>{};
    try {
      final band = await _db.collection('facilities').where('lat', isGreaterThanOrEqualTo: lat - d).where('lat', isLessThanOrEqualTo: lat + d).get();
      for (final s in band.docs) {
        final p = NearbyPlace.fromMap(s.id, s.data());
        if (p != null) out[s.id] = p;
      }
      final calls = await _db.collection('facilities').where('kind', isEqualTo: 'hotline').get();
      for (final s in calls.docs) {
        final p = NearbyPlace.fromMap(s.id, s.data());
        if (p != null) out[s.id] = p;
      }
    } catch (_) {
      return const [];
    }
    return rankNearby(out.values.toList(), lat, lng, radiusKm: radiusKm, perType: 8);
  }
}
