// The control-room map: incident pins by priority, unit pins by state, and the selected incident's live
// positions (the caller and the units holding the job). Bounds are computed by hand, never newLatLngBounds.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/models/dispatch_models.dart';
import '../resident/map/maps_available.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

const String kOpsMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1a1e22"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8b959e"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#14181b"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2b3238"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#333b42"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3d454d"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#14262e"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]}
]
''';

IconData _categoryIcon(String category) => switch (category) {
  'Medical Emergency' => Icons.local_hospital_outlined,
  'Road Accident' => Icons.directions_car_outlined,
  'Fire & Rescue' => Icons.local_fire_department_outlined,
  'Security Threat' || 'Abduction' => Icons.shield_outlined,
  _ => Icons.warning_amber_rounded,
};

const Color _onJob = Color(0xFFFFB020);

class OpsMap extends StatefulWidget {
  const OpsMap({super.key, required this.incidents, required this.responders, required this.selectedId, required this.onSelect, this.tracks = const {}, this.residentUid});
  final List<IncidentRecord> incidents;
  final List<ResponderRecord> responders;
  final String? selectedId;
  final void Function(String id) onSelect;
  final Map<String, TrackPoint> tracks;
  final String? residentUid;

  @override
  State<OpsMap> createState() => _OpsMapState();
}

class _OpsMapState extends State<OpsMap> {
  final Map<String, BitmapDescriptor> _pins = {};
  GoogleMapController? _map;
  String _fitKey = '';

  IncidentRecord? get _selected {
    for (final i in widget.incidents) {
      if (i.id == widget.selectedId) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _ensurePins();
  }

  /// Pins are drawn once per priority+category and unit state, then reused (web-safe: no default marker glyphs).
  Future<void> _ensurePins() async {
    final wanted = <String, (Color, IconData)>{};
    for (final i in widget.incidents) {
      wanted['p_${i.priority}_${i.category}'] = (OT.priority(i.priority), _categoryIcon(i.category));
    }
    wanted['u_Available'] = (OT.accent, Icons.navigation_outlined);
    wanted['u_On a job'] = (_onJob, Icons.navigation_outlined);
    wanted['u_Stale GPS'] = (const Color(0xFF8A939B), Icons.navigation_outlined);
    wanted['u_Offline'] = (const Color(0xFF5A636B), Icons.navigation_outlined);
    wanted['live'] = (OT.accent, Icons.navigation);
    wanted['resident'] = (const Color(0xFFB388FF), Icons.person_pin_circle);
    var added = false;
    for (final e in wanted.entries) {
      if (_pins.containsKey(e.key)) continue;
      _pins[e.key] = await _pin(e.key, e.value.$1, e.value.$2);
      added = true;
    }
    if (added && mounted) setState(() {});
  }

  Future<BitmapDescriptor> _pin(String key, Color color, IconData icon) async {
    final hit = _pins[key];
    if (hit != null) return hit;
    const scale = 2.0;
    const logical = 38.0;
    final size = logical * scale;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final center = Offset(size / 2, size / 2);
    c.drawCircle(center + const Offset(0, 2), size / 2 - 3, Paint()..color = const Color(0x55000000));
    c.drawCircle(center, size / 2 - 3, Paint()..color = const Color(0xFFEDEFF1));
    c.drawCircle(center, size / 2 - 7, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: size * 0.42, fontFamily: icon.fontFamily, package: icon.fontPackage, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return BitmapDescriptor.defaultMarker;
    final d = BitmapDescriptor.bytes(Uint8List.view(data.buffer), width: logical, height: logical);
    _pins[key] = d;
    return d;
  }

  Set<Marker> _markers() {
    final out = <Marker>{};
    for (final i in widget.incidents) {
      if (i.latitude == null || i.longitude == null) continue;
      out.add(Marker(
        markerId: MarkerId('i_${i.id}'),
        position: LatLng(i.latitude!, i.longitude!),
        icon: _pins['p_${i.priority}_${i.category}'] ?? BitmapDescriptor.defaultMarkerWithHue(_hue(i.priority)),
        onTap: () => widget.onSelect(i.id),
        infoWindow: InfoWindow(title: '${i.priority} · ${i.category}', snippet: 'Tap to open'),
        zIndexInt: widget.selectedId == i.id ? 6 : 4,
      ));
    }
    final now = DateTime.now();
    for (final r in widget.responders) {
      if (r.latitude == null || r.longitude == null) continue;
      final group = unitGroup(r.availabilityStatus, r.lastSeenAt, now: now);
      out.add(Marker(
        markerId: MarkerId('u_${r.id}'),
        position: LatLng(r.latitude!, r.longitude!),
        icon: _pins['u_$group'] ?? BitmapDescriptor.defaultMarkerWithHue(_unitHue(group)),
        infoWindow: InfoWindow(title: r.organizationName, snippet: '$group · ${r.organizationType}${r.lastSeenAt == null ? '' : ' · seen ${_ago(r.lastSeenAt!)}'}'),
        zIndexInt: 2,
      ));
    }
    final sel = _selected;
    if (sel != null) {
      for (final t in widget.tracks.values) {
        final mine = t.ownerId == widget.residentUid;
        if (mine) continue;
        out.add(Marker(
          markerId: MarkerId('t_${t.ownerId}'),
          position: LatLng(t.latitude, t.longitude),
          icon: _pins['live'] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Live unit position'),
          zIndexInt: 7,
        ));
      }
      final home = widget.tracks[widget.residentUid];
      if (home != null) {
        out.add(Marker(
          markerId: const MarkerId('resident_live'),
          position: LatLng(home.latitude, home.longitude),
          icon: _pins['resident'] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(title: 'Caller (live position)'),
          zIndexInt: 8,
        ));
      }
    }
    return out;
  }

  static double _hue(String priority) => switch (priority) { 'High' => BitmapDescriptor.hueRed, 'Medium' => BitmapDescriptor.hueOrange, _ => BitmapDescriptor.hueBlue };
  static double _unitHue(String group) => switch (group) { 'Available' => BitmapDescriptor.hueGreen, 'On a job' => BitmapDescriptor.hueYellow, _ => BitmapDescriptor.hueRose };

  List<LatLng> _points() {
    final pts = <LatLng>[];
    for (final i in widget.incidents) {
      if (i.latitude != null && i.longitude != null) pts.add(LatLng(i.latitude!, i.longitude!));
    }
    final sel = _selected;
    if (sel != null) {
      for (final t in widget.tracks.values) {
        pts.add(LatLng(t.latitude, t.longitude));
      }
    }
    return pts;
  }

  /// Same manual zoom as the help map: frame the points, never the whole city, clamp 10..17.
  void _fit() {
    if (_map == null || !mounted) return;
    final pts = _points();
    if (pts.isEmpty) return;
    final key = '${widget.selectedId}|${pts.length}|${pts.first.latitude.toStringAsFixed(4)}';
    if (key == _fitKey) return;
    _fitKey = key;
    if (pts.length == 1) {
      _move(pts.first, 14.5);
      return;
    }
    var minLa = pts.first.latitude, maxLa = minLa, minLo = pts.first.longitude, maxLo = minLo;
    for (final p in pts) {
      minLa = math.min(minLa, p.latitude);
      maxLa = math.max(maxLa, p.latitude);
      minLo = math.min(minLo, p.longitude);
      maxLo = math.max(maxLo, p.longitude);
    }
    final box = context.size ?? const Size(800, 600);
    final usableH = (box.height - 40).clamp(200.0, 4000.0);
    final usableW = (box.width - 40).clamp(200.0, 4000.0);
    double y(double lat) {
      final sn = math.sin(lat * math.pi / 180);
      return math.log((1 + sn) / (1 - sn)) / 2;
    }
    final dLo = math.max((maxLo - minLo).abs(), 0.0006);
    final dY = math.max((y(maxLa) - y(minLa)).abs(), 0.00001);
    final zLo = math.log(usableW * 360 / (256 * dLo)) / math.ln2;
    final zLa = math.log(usableH * 2 * math.pi / (256 * dY)) / math.ln2;
    final zoom = (math.min(zLo, zLa) - 0.3).clamp(10.0, 17.0);
    _move(LatLng((minLa + maxLa) / 2, (minLo + maxLo) / 2), zoom);
  }

  Future<void> _move(LatLng c, double zoom) async {
    for (var i = 0; i < 3; i++) {
      try {
        await _map?.animateCamera(CameraUpdate.newLatLngZoom(c, zoom));
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  @override
  void didUpdateWidget(covariant OpsMap old) {
    super.didUpdateWidget(old);
    if (old.incidents.length != widget.incidents.length) _ensurePins();
    if (old.selectedId != widget.selectedId && widget.selectedId != null) {
      final sel = _selected;
      if (sel != null && sel.latitude != null && sel.longitude != null) _move(LatLng(sel.latitude!, sel.longitude!), 15.5);
    } else {
      _fit();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !hasGoogleMapsRuntime()) {
      return const EmptyState(icon: Icons.map_outlined, title: 'Map unavailable', message: 'The Google Maps JavaScript API key is not configured for this browser. Queue, units and incident details still work.');
    }
    final initial = _points();
    final sel = _selected;
    final start = sel?.latitude != null ? LatLng(sel!.latitude!, sel.longitude!) : (initial.isNotEmpty ? initial.first : const LatLng(-1.2921, 36.8219));
    return LayoutBuilder(builder: (context, c) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(OT.radius),
        child: Stack(children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: start, zoom: 13),
            style: kOpsMapStyle,
            markers: _markers(),
            minMaxZoomPreference: const MinMaxZoomPreference(10, 19),
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: false,
            onMapCreated: (m) {
              _map = m;
              _fit();
              Future<void>.delayed(const Duration(milliseconds: 600), () {
                if (mounted) {
                  _fitKey = '';
                  _fit();
                }
              });
            },
          ),
          Positioned(left: 10, bottom: 10, child: _legend()),
        ]),
      );
    });
  }

  Widget _legend() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: OT.panel.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(10), border: Border.all(color: OT.line)),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      _LegendDot(OT.alert, 'High'),
      SizedBox(width: 10),
      _LegendDot(Color(0xFFFFB020), 'Medium'),
      SizedBox(width: 10),
      _LegendDot(Color(0xFF5AB0FF), 'Low'),
      SizedBox(width: 10),
      _LegendDot(OT.accent, 'Unit ready'),
    ]),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10.5, color: OT.muted)),
  ]);
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}
