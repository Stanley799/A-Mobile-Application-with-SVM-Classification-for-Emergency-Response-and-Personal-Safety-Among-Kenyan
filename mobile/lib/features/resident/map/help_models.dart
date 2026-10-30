// Data classes for the resident help map. Parsing is defensive: missing or odd fields never crash the screen.
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

double? _d(Object? v) => v is num ? v.toDouble() : null;
List<String> _list(Object? v) => [for (final x in (v as List? ?? const [])) x.toString()];

/// One card on the resident's help screen (written by the dispatch Cloud Function into incidents/{id}/options/rN).
class HelpOption {
  const HelpOption({
    required this.rank,
    required this.kind,
    required this.refId,
    required this.name,
    required this.orgType,
    required this.status,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.etaMin,
    this.etaIsRoad = false,
    this.phone = '',
    this.phones = const [],
    this.is24h,
    this.verified = false,
    this.address = '',
    this.caps = const [],
    this.why = const [],
  });

  final int rank;
  final String kind; // live | place | hotline
  final String refId;
  final String name;
  final String orgType;
  final String status; // live: available | asking | accepted | enroute | arrived   place: directions   hotline: call
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final double? etaMin;
  final bool etaIsRoad;
  final String phone;
  final List<String> phones;
  final bool? is24h;
  final bool verified;
  final String address;
  final List<String> caps;
  final List<String> why;

  bool get isLive => kind == 'live';
  bool get hasPosition => latitude != null && longitude != null;
  bool get holdsJob => status == 'accepted' || status == 'enroute' || status == 'arrived';
  bool get canRequest => isLive && status == 'available';

  /// "6 min" for road times, "about 6 min" for estimates.
  String? get etaText {
    final e = etaMin;
    if (e == null) return null;
    final m = e.round().clamp(1, 999);
    return etaIsRoad ? '$m min' : 'about $m min';
  }

  factory HelpOption.fromMap(String id, Map<String, dynamic> m) => HelpOption(
    rank: (m['rank'] as num?)?.toInt() ?? int.tryParse(id.replaceAll(RegExp('[^0-9]'), '')) ?? 9,
    kind: (m['kind'] ?? 'place').toString(),
    refId: (m['refId'] ?? id).toString(),
    name: (m['name'] ?? '').toString(),
    orgType: (m['orgType'] ?? '').toString(),
    status: (m['status'] ?? '').toString(),
    latitude: _d(m['lat']),
    longitude: _d(m['lng']),
    distanceKm: _d(m['distanceKm']),
    etaMin: _d(m['etaMin']),
    etaIsRoad: m['etaSource'] == 'road',
    phone: (m['phone'] ?? '').toString(),
    phones: _list(m['phones']),
    is24h: m['is24h'] is bool ? m['is24h'] as bool : null,
    verified: m['verified'] == true,
    address: (m['address'] ?? '').toString(),
    caps: _list(m['caps']),
    why: _list(m['why']),
  );
}

/// options/meta: what the banner at the top should say.
class HelpMeta {
  const HelpMeta({this.mode = 'map', this.state = '', this.failedCount = 0, this.asking = const [], this.held = false, this.suggestCall = false, this.showNumbers = false, this.noLive = true, this.sensitive = false});
  final String mode; // map | helplines
  final String state;
  final int failedCount;
  final List<String> asking;
  final bool held;
  final bool suggestCall;
  final bool showNumbers;
  final bool noLive;
  final bool sensitive;

  factory HelpMeta.fromMap(Map<String, dynamic>? m) => m == null
      ? const HelpMeta()
      : HelpMeta(
          mode: (m['mode'] ?? 'map').toString(),
          state: (m['state'] ?? '').toString(),
          failedCount: (m['failedCount'] as num?)?.toInt() ?? 0,
          asking: _list(m['asking']),
          held: m['held'] == true,
          suggestCall: m['suggestCall'] == true,
          showNumbers: m['showNumbers'] == true,
          noLive: m['noLive'] != false,
          sensitive: m['sensitive'] == true,
        );
}

class HelpState {
  const HelpState({this.options = const [], this.meta = const HelpMeta(), this.loaded = false});
  final List<HelpOption> options;
  final HelpMeta meta;
  final bool loaded;
}

/// Live position of one unit that holds the job (incidents/{id}/tracks/{responderId}).
class TrackPoint {
  const TrackPoint({required this.latitude, required this.longitude, this.heading, this.speed, this.at});
  final double latitude;
  final double longitude;
  final double? heading;
  final double? speed;
  final DateTime? at;

  static TrackPoint? tryParse(Map<String, dynamic>? m) {
    final la = _d(m?['lat']);
    final lo = _d(m?['lng']);
    if (la == null || lo == null) return null;
    final at = m?['at'];
    return TrackPoint(latitude: la, longitude: lo, heading: _d(m?['heading']), speed: _d(m?['speed']), at: at is Timestamp ? at.toDate() : (at is DateTime ? at : null));
  }
}

class RouteInfo {
  const RouteInfo({required this.points, required this.etaSeconds, required this.distanceMeters, this.estimate = false});
  final List<({double lat, double lng})> points;
  final double etaSeconds;
  final int distanceMeters;
  final bool estimate;
}

/// Decodes a Google encoded polyline (precision 5). Returns [] for empty or malformed input.
List<({double lat, double lng})> decodePolyline(String encoded) {
  final out = <({double lat, double lng})>[];
  var index = 0, lat = 0, lng = 0;
  try {
    while (index < encoded.length) {
      for (var axis = 0; axis < 2; axis++) {
        var shift = 0, result = 0, b = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (axis == 0) {
          lat += delta;
        } else {
          lng += delta;
        }
      }
      out.add((lat: lat / 1e5, lng: lng / 1e5));
    }
  } catch (_) {
    return const [];
  }
  return out;
}

/// Straight-line distance in km (used only for the arrival check on the phone).
double haversineKm(double la1, double lo1, double la2, double lo2) {
  const r = 6371.0;
  final dLa = (la2 - la1) * math.pi / 180, dLo = (lo2 - lo1) * math.pi / 180;
  final a = math.pow(math.sin(dLa / 2), 2) + math.cos(la1 * math.pi / 180) * math.cos(la2 * math.pi / 180) * math.pow(math.sin(dLo / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Emergency numbers always available to the resident. Verify them with the providers before publishing.
const List<({String label, String number})> kEmergencyNumbers = [
  (label: 'Police / general emergency', number: '999'),
  (label: 'General emergency', number: '112'),
  (label: 'Kenya Red Cross', number: '1199'),
  (label: 'Emergency line', number: '922'),
];

const Map<String, String> kOrgLabels = {
  'hospital': 'Hospital',
  'clinic': 'Clinic',
  'police': 'Police',
  'fire': 'Fire & rescue',
  'ambulance_operator': 'Ambulance service',
  'helpline': 'Helpline',
  'Ambulance': 'Ambulance',
  'Fire': 'Fire & rescue',
  'Police': 'Police',
  'Hospital': 'Hospital',
  'Community': 'Community responder',
  'Maritime': 'Maritime rescue',
  'Other': 'Responder',
};
