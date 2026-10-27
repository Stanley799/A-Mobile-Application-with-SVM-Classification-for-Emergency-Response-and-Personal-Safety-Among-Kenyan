// "Help" map for the resident: up to three ranked options, live tracking of the unit that accepted, and calm fallbacks when a unit cannot come.
// Data comes ONLY from what the dispatch Cloud Function wrote (options, tracks). This screen decides nothing about who is sent.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'help_models.dart';
import 'help_repository.dart';

class _C {
  static const ink = Color(0xFF1A1A1A);
  static const mute = Color(0xFF5F5F5F);
  static const brand = Color(0xFF0F766E);
  static const line = Color(0xFFE5E1DA);
  static const danger = Color(0xFFB33A3A);
  static const bg = Color(0xFFF4F2EE);
}

/// Phones dial. A desktop browser cannot dial, so on the web the number is also copied and always printed on the button.
Future<void> _call(String number) async {
  final n = number.replaceAll(' ', '');
  if (kIsWeb) {
    try {
      await Clipboard.setData(ClipboardData(text: n));
    } catch (_) {/* clipboard blocked: the number is still on screen */}
  }
  await launchUrl(Uri(scheme: 'tel', path: n));
}
Future<void> _directions(double lat, double lng) => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'), mode: LaunchMode.externalApplication);

double _hue(HelpOption o) {
  if (o.isLive) return BitmapDescriptor.hueGreen;
  return switch (o.orgType) {
    'police' => BitmapDescriptor.hueAzure,
    'fire' => BitmapDescriptor.hueOrange,
    'ambulance_operator' => BitmapDescriptor.hueViolet,
    _ => BitmapDescriptor.hueRed,
  };
}

IconData _icon(HelpOption o) => switch (o.orgType) {
  'police' => Icons.shield_outlined,
  'fire' => Icons.local_fire_department_outlined,
  'helpline' => Icons.support_agent_outlined,
  'Fire' => Icons.local_fire_department_outlined,
  'Police' => Icons.shield_outlined,
  _ => Icons.local_hospital_outlined,
};

class HelpMapScreen extends StatefulWidget {
  const HelpMapScreen({super.key, required this.incidentId, HelpRepository? repo}) : _repo = repo;
  final String incidentId;
  final HelpRepository? _repo;

  @override
  State<HelpMapScreen> createState() => _HelpMapScreenState();
}

class _HelpMapScreenState extends State<HelpMapScreen> with SingleTickerProviderStateMixin {
  late final HelpRepository repo = widget._repo ?? HelpRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  GoogleMapController? _map;
  HelpState _state = const HelpState();
  ({double lat, double lng})? _me;
  final Map<String, List<LatLng>> _routes = {};
  final Map<String, double> _etaSeconds = {};
  Timer? _routeTimer;
  String? _selected;
  String? _busyId;
  bool _hidden = false;
  String _fitKey = '';

  // smooth marker movement
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..addListener(() => setState(() {}));
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};

  @override
  void initState() {
    super.initState();
    _subs.add(repo.watchOptions(widget.incidentId).listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      _fit();
      _syncRoutes();
    }));
    _subs.add(repo.watchTracks(widget.incidentId).listen((t) {
      if (!mounted) return;
      for (final e in t.entries) {
        final now = _positionOf(e.key) ?? LatLng(e.value.latitude, e.value.longitude);
        _from[e.key] = now;
        _to[e.key] = LatLng(e.value.latitude, e.value.longitude);
      }
      _anim.forward(from: 0);
    }));
    _subs.add(repo.watchIncidentLocation(widget.incidentId).listen((l) {
      if (!mounted) return;
      setState(() => _me = l);
      _fit();
    }));
    _routeTimer = Timer.periodic(const Duration(seconds: 40), (_) => _syncRoutes(force: true));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _routeTimer?.cancel();
    _anim.dispose();
    _map?.dispose();
    super.dispose();
  }

  LatLng? _positionOf(String id) {
    final a = _from[id], b = _to[id];
    if (b == null) return null;
    if (a == null) return b;
    final t = Curves.easeOut.transform(_anim.value);
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  Future<void> _syncRoutes({bool force = false}) async {
    for (final o in _state.options) {
      if (!o.holdsJob) continue;
      if (!force && _routes.containsKey(o.refId)) continue;
      final r = await repo.route(widget.incidentId, o.refId);
      if (r == null || !mounted) continue;
      setState(() {
        if (r.points.isNotEmpty) _routes[o.refId] = [for (final p in r.points) LatLng(p.lat, p.lng)];
        _etaSeconds[o.refId] = r.etaSeconds;
      });
    }
  }

  void _fit() {
    final pts = <LatLng>[if (_me != null) LatLng(_me!.lat, _me!.lng), for (final o in _state.options) if (o.hasPosition) LatLng(o.latitude!, o.longitude!)];
    final key = '${pts.length}:${_state.options.map((o) => o.refId).join(',')}';
    if (pts.length < 2 || key == _fitKey || _map == null) return;
    _fitKey = key;
    var minLa = pts.first.latitude, maxLa = minLa, minLo = pts.first.longitude, maxLo = minLo;
    for (final p in pts) {
      if (p.latitude < minLa) minLa = p.latitude;
      if (p.latitude > maxLa) maxLa = p.latitude;
      if (p.longitude < minLo) minLo = p.longitude;
      if (p.longitude > maxLo) maxLo = p.longitude;
    }
    if ((maxLa - minLa).abs() < 1e-5 && (maxLo - minLo).abs() < 1e-5) return;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      try {
        _map?.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(minLa, minLo), northeast: LatLng(maxLa, maxLo)), 70));
      } catch (_) {/* the map is not laid out yet; the next update tries again */}
    });
  }

  Set<Marker> _markers() {
    final out = <Marker>{};
    final m = _me;
    if (m != null) out.add(Marker(markerId: const MarkerId('me'), position: LatLng(m.lat, m.lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue), infoWindow: const InfoWindow(title: 'You'), zIndex: 3));
    for (final o in _state.options) {
      final live = _positionOf(o.refId);
      final pos = live ?? (o.hasPosition ? LatLng(o.latitude!, o.longitude!) : null);
      if (pos == null) continue;
      out.add(Marker(
        markerId: MarkerId(o.refId),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(_hue(o)),
        alpha: o.refId == _selected || _selected == null ? 1.0 : 0.65,
        infoWindow: InfoWindow(title: o.name, snippet: o.isLive ? 'Registered unit' : 'Listed place'),
        zIndex: o.holdsJob ? 2 : 1,
        onTap: () => setState(() => _selected = o.refId),
      ));
    }
    return out;
  }

  Set<Polyline> _lines() => {
    for (final e in _routes.entries)
      if (e.value.length > 1) Polyline(polylineId: PolylineId('r_${e.key}'), points: e.value, color: _C.brand, width: 6, startCap: Cap.roundCap, endCap: Cap.roundCap),
  };

  Future<void> _request(HelpOption o) async {
    setState(() => _busyId = o.refId);
    try {
      await repo.requestUnit(widget.incidentId, o.refId);
      if (mounted) _snack('Request sent to ${o.name}. They have 45 seconds to answer.');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _snack(e.message ?? 'Could not send the request. Try another option or call.');
    } catch (_) {
      if (mounted) _snack('Could not send the request. Check your connection, or call.');
    }
    if (mounted) setState(() => _busyId = null);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final meta = _state.meta;
    final start = _me != null ? LatLng(_me!.lat, _me!.lng) : const LatLng(-1.2921, 36.8219);
    if (_hidden) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(
          onTap: () => setState(() => _hidden = false),
          child: const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('Notes\n\nTap anywhere to go back.', style: TextStyle(fontSize: 22, color: _C.ink)))),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _C.ink,
        elevation: 0,
        title: const Text('Help near you', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [if (meta.sensitive) TextButton.icon(onPressed: () => setState(() => _hidden = true), icon: const Icon(Icons.visibility_off_outlined, size: 18), label: const Text('Hide'))],
      ),
      body: meta.mode == 'helplines'
          ? _helplines()
          : Stack(children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: start, zoom: 13.5),
                markers: _markers(),
                polylines: _lines(),
                onMapCreated: (c) {
                  _map = c;
                  _fit();
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                padding: const EdgeInsets.only(bottom: 250),
              ),
              Positioned(left: 12, right: 12, top: 10, child: _banner(meta)),
              DraggableScrollableSheet(
                initialChildSize: 0.38,
                minChildSize: 0.16,
                maxChildSize: 0.86,
                builder: (context, scroll) => Container(
                  decoration: const BoxDecoration(color: _C.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(24)), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16)]),
                  child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _C.line, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 12),
                    if (!_state.loaded) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                    if (_state.loaded && _state.options.isEmpty) _empty(meta),
                    for (final o in _state.options) _card(o),
                    if (meta.showNumbers || meta.suggestCall) _numbers(),
                    const Padding(padding: EdgeInsets.only(top: 8), child: Text('Map © Google · Places © OpenStreetMap contributors. Times are estimates.', style: TextStyle(fontSize: 11, color: _C.mute))),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _banner(HelpMeta meta) {
    String? text;
    var warn = false;
    final held = _state.options.where((o) => o.holdsJob).toList();
    if (held.isNotEmpty) {
      final o = held.first;
      final eta = _etaSeconds[o.refId];
      final mins = eta != null ? (eta / 60).round().clamp(1, 999) : null;
      text = switch (o.status) {
        'arrived' => '${o.name} has arrived.',
        'enroute' => mins != null ? '${o.name} is on the way · about $mins min' : '${o.name} is on the way.',
        _ => '${o.name} accepted. They are getting ready to come.',
      };
    } else if (meta.failedCount > 0 && meta.asking.isEmpty) {
      text = "That unit couldn't take it. Trying the next one…";
      warn = true;
    } else if (meta.asking.isNotEmpty) {
      text = 'Asking ${meta.asking.join(' and ')}…';
    } else if (_state.loaded && _state.options.isEmpty && meta.state != '') {
      text = meta.state == 'no_location' ? 'We could not get your location. Call now.' : 'Looking for help near you…';
      warn = meta.state == 'no_location';
    }
    if (text == null) return const SizedBox.shrink();
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: warn ? const Color(0xFFFFF3E0) : Colors.white,
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        Icon(held.isNotEmpty ? Icons.directions_car_filled_outlined : (warn ? Icons.info_outline : Icons.hourglass_top), color: warn ? const Color(0xFF9C3700) : _C.brand),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.ink))),
      ])),
    );
  }

  Widget _empty(HelpMeta meta) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('No nearby options found yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.ink)),
      const SizedBox(height: 6),
      const Text('Call an emergency number now. We keep looking while you call.', style: TextStyle(fontSize: 14, color: _C.mute, height: 1.4)),
      const SizedBox(height: 12),
      _numbers(),
    ]),
  );

  Widget _numbers() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Wrap(spacing: 8, runSpacing: 8, children: [
      for (final n in kEmergencyNumbers)
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: n.number == '999' || n.number == '112' ? _C.danger : const Color(0xFF8E3030), minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => _call(n.number),
          icon: const Icon(Icons.call, size: 18),
          label: Text('${n.number}  ${n.label}'),
        ),
    ]),
  );

  Widget _helplines() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text("You're not alone", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _C.ink)),
    const SizedBox(height: 8),
    const Text('Talking to someone can help. These lines are free to call.', style: TextStyle(fontSize: 15, color: _C.mute, height: 1.45)),
    const SizedBox(height: 18),
    FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _C.brand, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () => _call('1199'), icon: const Icon(Icons.call), label: const Text('Call 1199 (Kenya Red Cross)')),
    const SizedBox(height: 12),
    _numbers(),
  ]);

  Widget _chip(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg, letterSpacing: .3)),
  );

  Widget _card(HelpOption o) {
    final selected = o.refId == _selected;
    final label = o.isLive ? _chip('LIVE', const Color(0xFFE8F5E9), const Color(0xFF1B5E20)) : (o.kind == 'hotline' ? _chip('CALL ONLY', const Color(0xFFEDE7F6), const Color(0xFF4527A0)) : _chip('LISTED', const Color(0xFFEDEDED), const Color(0xFF444444)));
    final eta = _etaSeconds[o.refId] != null ? '${(_etaSeconds[o.refId]! / 60).round().clamp(1, 999)} min' : o.etaText;
    final dist = o.distanceKm == null ? null : '${o.distanceKm!.toStringAsFixed(1)} km';
    final facts = [if (eta != null) eta, if (dist != null) dist, if (o.is24h == true) 'Open 24 h'].join(' · ');
    final phone = o.phone.isNotEmpty ? o.phone : (o.phones.isNotEmpty ? o.phones.first : '');
    return GestureDetector(
      onTap: () {
        setState(() => _selected = o.refId);
        if (o.hasPosition) _map?.animateCamera(CameraUpdate.newLatLng(LatLng(o.latitude!, o.longitude!)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? _C.brand : Colors.transparent, width: 2), boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: o.isLive ? const Color(0xFFE8F5E9) : const Color(0xFFF4F2EE), borderRadius: BorderRadius.circular(13)), child: Icon(_icon(o), color: o.isLive ? const Color(0xFF2E7D32) : _C.mute)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.ink))), const SizedBox(width: 8), label]),
              const SizedBox(height: 3),
              Text([kOrgLabels[o.orgType] ?? '', if (facts.isNotEmpty) facts].where((e) => e.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 13, color: _C.mute)),
            ])),
          ]),
          if (o.why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(o.why.join(' · '), style: const TextStyle(fontSize: 12, color: _C.mute))),
          const SizedBox(height: 12),
          _actions(o, phone),
        ]),
      ),
    );
  }

  Widget _actions(HelpOption o, String phone) {
    final callBtn = phone.isEmpty ? null : OutlinedButton.icon(onPressed: () => _call(phone), icon: const Icon(Icons.call, size: 18), label: Text(kIsWeb ? phone : 'Call'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
    if (o.isLive && o.holdsJob) {
      return Row(children: [
        Expanded(child: Container(height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(14)), child: Text({'accepted': 'Accepted', 'enroute': 'On the way', 'arrived': 'Arrived'}[o.status] ?? o.status, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))))),
        if (callBtn != null) ...[const SizedBox(width: 10), callBtn],
      ]);
    }
    if (o.isLive) {
      final asking = o.status == 'asking';
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: asking || _busyId != null ? null : () => _request(o),
          child: _busyId == o.refId ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(asking ? 'Asked, waiting for an answer…' : 'Request this unit', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      );
    }
    return Row(children: [
      if (callBtn != null) Expanded(child: SizedBox(height: 48, child: FilledButton.icon(onPressed: () => _call(phone), icon: const Icon(Icons.call, size: 18), label: Text(kIsWeb ? 'Call $phone (copied)' : 'Call now'), style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))))),
      if (o.hasPosition) ...[if (callBtn != null) const SizedBox(width: 10), OutlinedButton.icon(onPressed: () => _directions(o.latitude!, o.longitude!), icon: const Icon(Icons.directions_outlined, size: 18), label: const Text('Directions'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))],
    ]);
  }
}
