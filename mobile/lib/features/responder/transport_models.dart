// Hospitals and clinics a unit can transport a patient to. Read from `facilities`; parsing and sorting are pure so they can be tested.
import '../resident/map/help_models.dart' show haversineKm;

class TransportDestination {
  const TransportDestination({
    required this.id,
    required this.name,
    required this.type,
    this.latitude,
    this.longitude,
    this.phone = '',
    this.distanceKm,
    this.verified = false,
    this.is24h,
    this.address = '',
  });

  final String id;
  final String name;
  final String type; // hospital | clinic
  final double? latitude;
  final double? longitude;
  final String phone;
  final double? distanceKm;
  final bool verified;
  final bool? is24h;
  final String address;

  bool get hasPosition => latitude != null && longitude != null;

  String get typeLabel => switch (type) {
    'hospital' => 'Hospital',
    'clinic' => 'Clinic',
    _ => 'Facility',
  };

  TransportDestination withDistance(double? km) => TransportDestination(
    id: id,
    name: name,
    type: type,
    latitude: latitude,
    longitude: longitude,
    phone: phone,
    distanceKm: km,
    verified: verified,
    is24h: is24h,
    address: address,
  );

  /// Null for anything that is not an active hospital or clinic, or has no name.
  static TransportDestination? fromMap(String id, Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString();
    if (type != 'hospital' && type != 'clinic') return null;
    if ((m['status'] ?? 'active') != 'active') return null;
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final phones = [
      for (final p in (m['phones'] as List? ?? const [])) p.toString(),
    ];
    final single = (m['phone'] ?? '').toString();
    return TransportDestination(
      id: id,
      name: name,
      type: type,
      latitude: (m['lat'] as num?)?.toDouble(),
      longitude: (m['lng'] as num?)?.toDouble(),
      phone: phones.isNotEmpty ? phones.first : single,
      verified: m['verified'] == true,
      is24h: m['is24h'] is bool ? m['is24h'] as bool : null,
      address: (m['address'] ?? '').toString(),
    );
  }
}

/// Verified facilities first, then by distance; unpositioned entries last. At most [limit] results.
List<TransportDestination> rankDestinations(
  Iterable<TransportDestination> all,
  double lat,
  double lng, {
  double radiusKm = 25,
  int limit = 10,
}) {
  final scored = <TransportDestination>[];
  for (final d in all) {
    if (!d.hasPosition) {
      scored.add(d.withDistance(null));
      continue;
    }
    final km = haversineKm(lat, lng, d.latitude!, d.longitude!);
    if (km <= radiusKm) scored.add(d.withDistance(km));
  }
  scored.sort((a, b) {
    if (a.verified != b.verified) return a.verified ? -1 : 1;
    if (a.distanceKm == null && b.distanceKm == null) {
      return a.name.compareTo(b.name);
    }
    if (a.distanceKm == null) return 1;
    if (b.distanceKm == null) return -1;
    return a.distanceKm!.compareTo(b.distanceKm!);
  });
  return scored.take(limit).toList();
}
