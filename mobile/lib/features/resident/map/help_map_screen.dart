// Emergency help map (v3). Order of events: 1) find the resident (LocationGate) 2) show ONLY places that matter for THIS emergency
// 3) the engine's top-3 options on top, then nearby places by type, 4) live tracking of the unit that accepted.
// Data: options/tracks written by Cloud Functions; directory places read from Firestore. This screen decides nothing about who is sent.
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/glass.dart';
import '../../../core/ui/tokens.dart';
import 'emergency_layers.dart';
import 'help_models.dart';
import 'help_repository.dart';
import 'location_gate.dart';
import 'location_resolver.dart';
import 'map_style.dart';
import 'maps_available.dart';
import 'nearby_places.dart';
import 'pin_factory.dart';

class _C {
  static const ink = Color(0xFF1A1A1A);
  static const mute = Color(0xFF5F5F5F);
  static const brand = Color(0xFF0F766E);
  static const line = Color(0xFFE5E1DA);
  static const danger = Tk.danger;
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

IconData _typeIcon(String key) => kPinStyles[key]?.icon ?? Icons.place;
Color _typeColor(String key) => kPinStyles[key]?.color ?? _C.mute;

/// Where the resident is heading (a listed place, a registered unit's base, or a directory entry). Directions are drawn inside the app.
class _Dest {
  const _Dest({required this.id, required this.name, required this.typeKey, required this.lat, required this.lng, this.phone = ''});
  final String id;
  final String name;
  final String typeKey;
  final double lat;
  final double lng;
  final String phone;
}

class HelpMapScreen extends StatefulWidget {
  const HelpMapScreen({super.key, required this.incidentId, this.repo, this.nearbyRepo});
  final String incidentId;
  final HelpRepository? repo;
  final NearbyRepository? nearbyRepo;

  @override
  State<HelpMapScreen> createState() => _HelpMapScreenState();
}

class _HelpMapScreenState extends State<HelpMapScreen> with SingleTickerProviderStateMixin {
  late final HelpRepository repo = widget.repo ?? HelpRepository();
  late final NearbyRepository nearbyRepo = widget.nearbyRepo ?? NearbyRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  GoogleMapController? _map;

  IncidentInfo _info = const IncidentInfo();
  bool _infoLoaded = false;
  ResolvedLocation? _local;
  HelpState _state = const HelpState();
  List<NearbyPlace> _nearby = const [];
  bool _nearbyLoaded = false;
  String _nearbyFor = '';
  Set<PlaceType> _active = {};
  bool _activeInit = false;
  final Map<String, BitmapDescriptor> _pins = {};

  final Map<String, List<LatLng>> _routes = {};
  final Map<String, double> _etaSeconds = {};
  Timer? _routeTimer;
  String? _selected;
  bool _selFromMap = false;
  String? _busyId;
  bool _hidden = false;
  String _fitKey = '';
  String? _address;
  String _addrFor = '';
  bool _needConfirm = false;
  _Dest? _dest;
  RouteInfo? _destRoute;
  bool _routeBusy = false;

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..addListener(() => setState(() {}));
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};

  double? get _lat => _local?.latitude ?? _info.latitude;
  double? get _lng => _local?.longitude ?? _info.longitude;
  EmergencyLayers get _layers => layersFor(_info.category, _info.subtype);

  @override
  void initState() {
    super.initState();
    _loadPins();
    _subs.add(repo.watchIncident(widget.incidentId).listen((i) {
      if (!mounted) return;
      setState(() {
        _info = i;
        _infoLoaded = true;
        if (!_activeInit && (i.category != null)) {
          _active = _layers.primary.toSet();
          _activeInit = true;
        }
      });
      _loadNearby();
    }));
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
    _routeTimer = Timer.periodic(const Duration(seconds: 40), (_) => _syncRoutes(force: true));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _routeTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadPins() async {
    for (final k in kPinStyles.keys) {
      for (final big in [false, true]) {
        final p = await PinFactory.pin(k, big: big);
        if (p != null) _pins[big ? '$k!' : k] = p;
      }
    }
    if (mounted) setState(() {});
  }

  BitmapDescriptor _icon(String key, {bool big = false}) => _pins[big ? '$key!' : key] ?? PinFactory.fallback(key);

  Future<void> _loadNearby() async {
    final la = _lat, lo = _lng;
    if (la == null || lo == null) return;
    final key = '${la.toStringAsFixed(3)},${lo.toStringAsFixed(3)}';
    if (key == _nearbyFor) return;
    _nearbyFor = key;
    final list = await nearbyRepo.load(la, lo);
    if (!mounted) return;
    setState(() {
      _nearby = list;
      _nearbyLoaded = true;
    });
    _fit();
  }

  void _onResolved(ResolvedLocation loc, {bool confirm = false}) {
    setState(() {
      _local = loc;
      _needConfirm = confirm;
      _dest = null;
      _destRoute = null;
    });
    repo.saveLocation(widget.incidentId, loc.latitude, loc.longitude); // lets dispatch start; the screen already works without it
    _loadAddress();
    _loadNearby();
  }

  Future<void> _loadAddress() async {
    final la = _lat, lo = _lng;
    if (la == null || lo == null) return;
    final key = '${la.toStringAsFixed(4)},${lo.toStringAsFixed(4)}';
    if (key == _addrFor) return;
    _addrFor = key;
    final a = await repo.geocode(la, lo);
    if (mounted && key == _addrFor) setState(() => _address = a);
  }

  Future<void> _showRoute(_Dest d) async {
    final la = _lat, lo = _lng;
    if (la == null || lo == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dest = d;
      _destRoute = null;
      _routeBusy = true;
      _selected = d.id;
    });
    _fitPoints([LatLng(la, lo), LatLng(d.lat, d.lng)], 'route:${d.id}');
    final r = await repo.directions(la, lo, d.lat, d.lng);
    if (!mounted || _dest?.id != d.id) return;
    setState(() {
      _destRoute = r;
      _routeBusy = false;
    });
    final pts = [LatLng(la, lo), LatLng(d.lat, d.lng), if (r != null) for (final p in r.points) LatLng(p.lat, p.lng)];
    _fitPoints(pts, 'route2:${d.id}:${r?.points.length ?? 0}');
  }

  void _closeRoute() {
    setState(() {
      _dest = null;
      _destRoute = null;
      _routeBusy = false;
      _fitKey = '';
    });
    _fit();
  }

  Future<void> _fixLocation() async {
    final la = _lat, lo = _lng;
    if (la == null || lo == null) return;
    final picked = await Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => ManualPinPage(start: LatLng(la, lo))));
    if (picked != null && mounted) {
      _fitKey = '';
      _onResolved(ResolvedLocation(latitude: picked.latitude, longitude: picked.longitude, source: 'manual'));
      _addrFor = '';
      _loadAddress();
    }
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

  List<NearbyPlace> _visibleNearby() {
    final optionIds = {for (final o in _state.options) o.refId};
    return [for (final p in _nearby) if (_active.contains(p.type) && !optionIds.contains(p.id)) p];
  }

  void _fit() {
    final la = _lat, lo = _lng;
    if (la == null || lo == null || _map == null || _dest != null) return;
    final pts = <LatLng>[LatLng(la, lo)];
    for (final o in _state.options.take(3)) {
      if (o.hasPosition) pts.add(LatLng(o.latitude!, o.longitude!));
    }
    final seen = <PlaceType>{};
    for (final p in _visibleNearby()) {
      if (p.hasPosition && (p.distanceKm ?? 99) <= 6 && seen.add(p.type)) pts.add(LatLng(p.latitude!, p.longitude!));
    }
    _fitPoints(pts, '${la.toStringAsFixed(4)}:${pts.length}:${_state.options.map((o) => o.refId).join(',')}:${_active.length}');
  }

  /// Frames the points but never shows the whole city or the world. The zoom is computed here (not by the map plugin) so it behaves the same
  /// on Android and in a browser, where newLatLngBounds is unreliable before the first layout.
  void _fitPoints(List<LatLng> pts, String key) {
    if (_map == null || key == _fitKey || !mounted) return;
    _fitKey = key;
    if (pts.length < 2) {
      _move(pts.first, 15.5);
      return;
    }
    var minLa = pts.first.latitude, maxLa = minLa, minLo = pts.first.longitude, maxLo = minLo;
    for (final p in pts) {
      if (p.latitude < minLa) minLa = p.latitude;
      if (p.latitude > maxLa) maxLa = p.latitude;
      if (p.longitude < minLo) minLo = p.longitude;
      if (p.longitude > maxLo) maxLo = p.longitude;
    }
    final size = MediaQuery.of(context).size;
    final usableH = (size.height - 120 - (_dest != null ? 210 : 270)).clamp(160.0, 4000.0);
    final usableW = (size.width - 80).clamp(160.0, 4000.0);
    double y(double lat) {
      final sn = math.sin(lat * math.pi / 180);
      return math.log((1 + sn) / (1 - sn)) / 2;
    }
    final dLo = math.max((maxLo - minLo).abs(), 0.0004);
    final dY = math.max((y(maxLa) - y(minLa)).abs(), 0.0000075);
    final zLo = math.log(usableW * 360 / (256 * dLo)) / math.ln2;
    final zLa = math.log(usableH * 2 * math.pi / (256 * dY)) / math.ln2;
    final zoom = (math.min(zLo, zLa) - 0.25).clamp(11.0, 17.0);
    _move(LatLng((minLa + maxLa) / 2, (minLo + maxLo) / 2), zoom);
  }

  /// On the web the plugin ignores GoogleMap.padding, so the centre is nudged up by hand so the pins sit above the bottom sheet.
  Future<void> _move(LatLng c, double zoom) async {
    var target = c;
    if (kIsWeb) {
      final h = MediaQuery.of(context).size.height;
      final shiftPx = ((_dest != null ? 210 : 270) - 120) / 2;
      final degPerPx = 360 / (256 * math.pow(2, zoom)) * math.cos(c.latitude * math.pi / 180);
      target = LatLng(c.latitude - shiftPx * degPerPx * (h > 0 ? 1 : 0), c.longitude);
    }
    for (var i = 0; i < 3; i++) {
      try {
        await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  String _keyOfOption(HelpOption o) => o.isLive ? 'live' : (placeTypeOf(o.orgType)?.name ?? 'hospital');

  Set<Marker> _markers() {
    final out = <Marker>{};
    final la = _lat, lo = _lng;
    if (la != null && lo != null) {
      out.add(Marker(markerId: const MarkerId('me'), position: LatLng(la, lo), icon: _icon('me', big: true), anchor: const Offset(0.5, 0.5), infoWindow: InfoWindow(title: _local?.source == 'manual' ? 'You (placed by you)' : 'You'), zIndexInt: 5));
    }
    final d = _dest;
    if (d != null) {
      out.add(Marker(markerId: MarkerId('dest_${d.id}'), position: LatLng(d.lat, d.lng), icon: _icon(d.typeKey, big: true), anchor: const Offset(0.5, 0.5), infoWindow: InfoWindow(title: d.name), zIndexInt: 4));
      return out;
    }
    for (final o in _state.options) {
      final pos = _positionOf(o.refId) ?? (o.hasPosition ? LatLng(o.latitude!, o.longitude!) : null);
      if (pos == null) continue;
      out.add(Marker(
        markerId: MarkerId('o_${o.refId}'),
        position: pos,
        icon: _icon(_keyOfOption(o), big: true),
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: o.name, snippet: o.isLive ? 'Registered unit' : 'Listed place'),
        zIndexInt: o.holdsJob ? 4 : 3,
        onTap: () => setState(() {
          _selected = o.refId;
          _selFromMap = true;
        }),
      ));
    }
    for (final p in _visibleNearby()) {
      if (!p.hasPosition) continue;
      final sel = p.id == _selected;
      out.add(Marker(
        markerId: MarkerId('n_${p.id}'),
        position: LatLng(p.latitude!, p.longitude!),
        icon: _icon(p.type.name, big: sel),
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: p.name, snippet: placeTypeLabel(p.type)),
        zIndexInt: sel ? 3 : 1,
        onTap: () => setState(() {
          _selected = p.id;
          _selFromMap = true;
        }),
      ));
    }
    return out;
  }

  Set<Polyline> _lines() {
    final out = <Polyline>{};
    final d = _dest, la = _lat, lo = _lng;
    if (d != null && la != null && lo != null) {
      final pts = _destRoute?.points ?? const [];
      if (pts.length > 1) {
        out.add(Polyline(polylineId: const PolylineId('dest_casing'), points: [for (final p in pts) LatLng(p.lat, p.lng)], color: Colors.white, width: 10, startCap: Cap.roundCap, endCap: Cap.roundCap, jointType: JointType.round));
        out.add(Polyline(polylineId: const PolylineId('dest'), points: [for (final p in pts) LatLng(p.lat, p.lng)], color: const Color(0xFF1A73E8), width: 6, startCap: Cap.roundCap, endCap: Cap.roundCap, jointType: JointType.round));
      } else if (!_routeBusy) {
        out.add(Polyline(polylineId: const PolylineId('dest_est'), points: [LatLng(la, lo), LatLng(d.lat, d.lng)], color: const Color(0xFF1A73E8), width: 4, patterns: [PatternItem.dash(18), PatternItem.gap(12)]));
      }
      return out;
    }
    for (final e in _routes.entries) {
      if (e.value.length > 1) out.add(Polyline(polylineId: PolylineId('r_${e.key}'), points: e.value, color: _C.brand, width: 6, startCap: Cap.roundCap, endCap: Cap.roundCap));
    }
    return out;
  }

  Set<Circle> _circles() {
    final la = _lat, lo = _lng;
    if (la == null || lo == null) return const {};
    final c = <Circle>{
      Circle(circleId: const CircleId('ring'), center: LatLng(la, lo), radius: 3000, fillColor: const Color(0x0A0F766E), strokeColor: const Color(0x550F766E), strokeWidth: 1),
    };
    final acc = _local?.accuracyMeters;
    if (acc != null && acc > 40) {
      c.add(Circle(circleId: const CircleId('acc'), center: LatLng(la, lo), radius: acc, fillColor: const Color(0x221A73E8), strokeColor: const Color(0x551A73E8), strokeWidth: 1));
    }
    return c;
  }

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

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (!_infoLoaded) {
      return const Scaffold(backgroundColor: _C.bg, body: Center(child: CircularProgressIndicator()));
    }
    if (_lat == null) return LocationGate(onResolved: (l) => _onResolved(l, confirm: true));
    if (!hasGoogleMapsRuntime() && kIsWeb) {
      return Scaffold(
        backgroundColor: _C.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _C.ink,
          elevation: 0,
          title: const Text('Map unavailable'),
        ),
        body: MapsUnavailableView(
          title: 'Map unavailable',
          message: 'Google Maps is not available in this browser because the JavaScript API key is missing. You can still continue with the emergency details and use your current location text.',
          primaryAction: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _C.brand, minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ),
      );
    }
    if (_needConfirm) return _confirmView();
    final meta = _state.meta;
    if (_hidden) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(onTap: () => setState(() => _hidden = false), child: const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('Notes\n\nTap anywhere to go back.', style: TextStyle(fontSize: 22, color: _C.ink))))),
      );
    }
    if (meta.mode == 'helplines') {
      return Scaffold(backgroundColor: _C.bg, appBar: AppBar(backgroundColor: Colors.white, foregroundColor: _C.ink, elevation: 0, title: Text(_layers.title)), body: _helplines());
    }
    final routing = _dest != null;
    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: LatLng(_lat!, _lng!), zoom: 15),
            style: kEmergencyMapStyle,
            markers: _markers(),
            polylines: _lines(),
            circles: routing ? const {} : _circles(),
            minMaxZoomPreference: const MinMaxZoomPreference(11, 19),
            onMapCreated: (c) {
              _map = c;
              _fit();
              Future<void>.delayed(const Duration(milliseconds: 700), () {
                if (mounted) {
                  _fitKey = '';
                  _fit();
                }
              });
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            trafficEnabled: false,
            buildingsEnabled: false,
            indoorViewEnabled: false,
            onTap: (_) => setState(() => _selFromMap = false),
            padding: kIsWeb ? EdgeInsets.zero : EdgeInsets.only(top: 120, bottom: routing ? 210 : 270),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(children: [
              _topBar(meta),
              if (!routing) _banner(meta),
              if (!routing) _chips(),
            ]),
          ),
        ),
        if (routing) _routeCard() else _sheet(meta),
        if (!routing) _mapSelectionCard(),
      ]),
    );
  }

  /// Floating detail card for the pin the resident just tapped on the map: name, facts, call and directions.
  /// Sits above the collapsed sheet; the full list with the same item highlighted stays in the sheet.
  Widget _mapSelectionCard() {
    if (!_selFromMap) return const SizedBox.shrink();
    final sel = _selected;
    if (sel == null) return const SizedBox.shrink();

    for (final o in _state.options) {
      if (o.refId != sel) continue;
      final key = _keyOfOption(o);
      final phone = o.phone.isNotEmpty ? o.phone : (o.phones.isNotEmpty ? o.phones.first : '');
      final facts = [kOrgLabels[o.orgType] ?? '', o.etaText, if (o.distanceKm != null) '${o.distanceKm!.toStringAsFixed(1)} km'].where((e) => e != null && e.isNotEmpty).join(' · ');
      final Widget action;
      if (o.isLive && o.holdsJob) {
        action = Expanded(child: Container(height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(14)), child: Text({'accepted': 'Accepted', 'enroute': 'On the way', 'arrived': 'Arrived'}[o.status] ?? o.status, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1B5E20)))));
      } else if (o.isLive) {
        final asking = o.status == 'asking';
        action = Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: asking || _busyId != null ? null : () => _request(o),
              child: _busyId == o.refId ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(asking ? 'Asked, waiting…' : 'Request this unit', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        );
      } else {
        action = const SizedBox.shrink();
      }
      return Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).size.height * 0.36 + 8,
        child: _selShell(
          iconKey: key,
          title: o.name,
          facts: facts,
          children: [
            if (o.isLive) action,
            if (o.isLive && phone.isNotEmpty) const SizedBox(width: 10),
            if (phone.isNotEmpty) Expanded(child: SizedBox(height: 48, child: OutlinedButton.icon(onPressed: () => _call(phone), icon: const Icon(Icons.call, size: 18), label: Text(kIsWeb ? phone : 'Call'), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))))),
            if (!o.isLive && o.hasPosition) ...[
              if (phone.isNotEmpty) const SizedBox(width: 10),
              Expanded(child: SizedBox(height: 48, child: FilledButton.icon(onPressed: () => _showRoute(_Dest(id: o.refId, name: o.name, typeKey: key, lat: o.latitude!, lng: o.longitude!, phone: phone)), icon: const Icon(Icons.directions_outlined, size: 18), label: const Text('Directions'), style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))))),
            ],
          ],
        ),
      );
    }

    for (final p in _visibleNearby()) {
      if (p.id != sel) continue;
      final key = p.type.name;
      final facts = [placeTypeLabel(p.type), if (p.distanceKm != null) '${p.distanceKm!.toStringAsFixed(1)} km', if (p.is24h == true) 'Open 24 h'].join(' · ');
      return Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).size.height * 0.36 + 8,
        child: _selShell(
          iconKey: key,
          title: p.name,
          facts: facts,
          unverified: p.phone.isNotEmpty && !p.verified,
          children: [
            if (p.phone.isNotEmpty) Expanded(child: SizedBox(height: 48, child: FilledButton.icon(onPressed: () => _call(p.phone), icon: const Icon(Icons.call, size: 18), label: Text(kIsWeb ? 'Call ${p.phone}' : 'Call now'), style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))))),
            if (p.phone.isNotEmpty) const SizedBox(width: 10),
            if (p.hasPosition) Expanded(child: SizedBox(height: 48, child: OutlinedButton.icon(onPressed: () => _showRoute(_Dest(id: p.id, name: p.name, typeKey: key, lat: p.latitude!, lng: p.longitude!, phone: p.phone)), icon: const Icon(Icons.directions_outlined, size: 18), label: const Text('Directions'), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))))),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _selShell({required String iconKey, required String title, required String facts, required List<Widget> children, bool unverified = false}) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    elevation: 6,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: _typeColor(iconKey), shape: BoxShape.circle), child: Icon(_typeIcon(iconKey), color: Colors.white, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.ink)),
            if (facts.isNotEmpty) Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _C.mute, fontWeight: FontWeight.w600)),
            if (unverified) const Padding(padding: EdgeInsets.only(top: 4), child: _UnverifiedPhoneTag()),
          ])),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _selFromMap = false)),
        ]),
        if (children.where((w) => w is! SizedBox).isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: children),
        ],
      ]),
    ),
  );

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) => GlassIconButton(icon: icon, tooltip: tip, onPressed: onTap);

  /// Back button, "You are at <street>" glass pill (the way to check the GPS got it right), and move-pin.
  Widget _topBar(HelpMeta meta) {
    final acc = _local?.accuracyMeters;
    final where = _address ?? (_lat != null ? '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}' : '');
    return Row(children: [
      _roundBtn(Icons.arrow_back_ios_new, 'Back', () => Navigator.of(context).maybePop()),
      const SizedBox(width: 10),
      Expanded(
        child: Glass(
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            const Icon(Icons.my_location, size: 18, color: Tk.you),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_layers.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Tk.mute, letterSpacing: .8)),
                Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Tk.ink)),
              ]),
            ),
            if (acc != null) Text('±${acc.round()} m', style: const TextStyle(fontSize: 11, color: Tk.mute)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      _roundBtn(Icons.edit_location_alt_outlined, 'Move my pin', _fixLocation),
      if (meta.sensitive) ...[const SizedBox(width: 8), _roundBtn(Icons.visibility_off_outlined, 'Hide screen', () => setState(() => _hidden = true))],
    ]);
  }

  /// Shown once after the GPS is captured: the resident checks the street name before anything else.
  Widget _confirmView() {
    final la = _lat!, lo = _lng!;
    final acc = _local?.accuracyMeters;
    final rough = acc != null && acc > 100;
    if (!hasGoogleMapsRuntime()) {
      return Scaffold(
        backgroundColor: _C.bg,
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: _C.ink, elevation: 0, title: const Text('Confirm location')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Map unavailable', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _C.ink)),
                const SizedBox(height: 12),
                Text(
                  'The Google Maps JavaScript API is not available in this browser. You can still confirm the location textually and continue.',
                  style: const TextStyle(fontSize: 16, color: _C.mute, height: 1.5),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _C.brand, minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: LatLng(la, lo), zoom: 16.5),
                style: kEmergencyMapStyle,
                markers: {Marker(markerId: const MarkerId('me'), position: LatLng(la, lo), icon: _icon('me', big: true), anchor: const Offset(0.5, 0.5))},
                circles: {if (acc != null) Circle(circleId: const CircleId('acc'), center: LatLng(la, lo), radius: acc, fillColor: const Color(0x221A73E8), strokeColor: const Color(0x551A73E8), strokeWidth: 1)},
                minMaxZoomPreference: const MinMaxZoomPreference(11, 19),
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                buildingsEnabled: false,
                indoorViewEnabled: false,
              ),
            ),
            SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.topLeft, child: _roundBtn(Icons.arrow_back_ios_new, 'Back', () => Navigator.of(context).maybePop())))),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28)), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16)]),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('YOU ARE AT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _C.mute, letterSpacing: .8)),
              const SizedBox(height: 4),
              Text(_address ?? 'Location found', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _C.ink)),
              const SizedBox(height: 4),
              Text(
                _address == null ? 'We could not get the street name, but the pin shows where your phone says you are.${acc != null ? ' Accuracy about ${acc.round()} m.' : ''}' : (acc != null ? 'Accurate to about ${acc.round()} m.' : ''),
                style: const TextStyle(fontSize: 13, color: _C.mute, height: 1.4),
              ),
              if (rough) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Your GPS is rough right now. If the pin is wrong, move it.', style: TextStyle(fontSize: 13, color: _C.danger, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _needConfirm = false;
                      _fitKey = '';
                    });
                  },
                  child: const Text("Yes, that's where I am", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _fixLocation,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('No, move the pin', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// In-app directions: where, how long, how far. Call or close. No other website.
  Widget _routeCard() {
    final d = _dest!;
    final r = _destRoute;
    final mins = r == null ? null : (r.etaSeconds / 60).round().clamp(1, 999);
    final km = r == null ? null : r.distanceMeters / 1000.0;
    final facts = _routeBusy ? 'Finding the route…' : (r == null ? 'Route unavailable. Showing a straight line.' : '$mins min · ${km!.toStringAsFixed(1)} km${r.estimate ? ' (estimate)' : ''}');
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28)), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16)]),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: _typeColor(d.typeKey), shape: BoxShape.circle), child: Icon(_typeIcon(d.typeKey), color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _C.ink)),
                Text(facts, style: const TextStyle(fontSize: 14, color: _C.mute, fontWeight: FontWeight.w600)),
              ])),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: _closeRoute),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              if (d.phone.isNotEmpty) Expanded(child: SizedBox(height: 50, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () => _call(d.phone), icon: const Icon(Icons.call, size: 18), label: Text(kIsWeb ? 'Call ${d.phone}' : 'Call', style: const TextStyle(fontWeight: FontWeight.w800))))),
              if (d.phone.isNotEmpty) const SizedBox(width: 10),
              Expanded(child: SizedBox(height: 50, child: OutlinedButton(style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _closeRoute, child: const Text('Back to options', style: TextStyle(fontWeight: FontWeight.w700))))),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _directions(d.lat, d.lng), child: const Text('Turn-by-turn in Google Maps', style: TextStyle(fontSize: 12, color: _C.mute))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chips() {
    final all = _layers.all;
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: ListView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), clipBehavior: Clip.none, children: [
        for (final t in all)
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 10),
            child: _typeChip(t),
          ),
      ]),
    );
  }

  Widget _typeChip(PlaceType t) {
    final on = _active.contains(t);
    final c = _typeColor(t.name);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          on ? _active.remove(t) : _active.add(t);
          _fitKey = '';
        });
        _fit();
      },
      child: AnimatedContainer(
        duration: Tk.fast,
        curve: Tk.settle,
        child: on
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(Tk.rPill), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_typeIcon(t.name), size: 16, color: Colors.white), const SizedBox(width: 6), Text(placeTypeLabel(t), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 13))]),
              )
            : Glass(
                radius: Tk.rPill,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_typeIcon(t.name), size: 16, color: c), const SizedBox(width: 6), Text(placeTypeLabel(t), style: const TextStyle(fontWeight: FontWeight.w700, color: Tk.ink, fontSize: 13))]),
              ),
      ),
    );
  }

  Widget _sheet(HelpMeta meta) {
    final visible = _visibleNearby();
    return DraggableScrollableSheet(
      initialChildSize: 0.36,
      minChildSize: 0.16,
      maxChildSize: 0.88,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(color: _C.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28)), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16)]),
        child: ListView(controller: scroll, physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _C.line, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          if (!_state.loaded && !_nearbyLoaded) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_state.options.isNotEmpty) ...[
            _heading('Best options for you now'),
            for (final o in _state.options) _card(o),
          ],
          for (final t in _layers.all)
            if (_active.contains(t)) ..._section(t, [for (final p in visible) if (p.type == t) p]),
          if (_nearbyLoaded && _state.loaded && _state.options.isEmpty && visible.isEmpty) _emptyNote(),
          const SizedBox(height: 8),
          _heading(meta.showNumbers || meta.suggestCall ? 'Call now if you cannot wait' : 'Emergency numbers'),
          _numbers(prominent: meta.showNumbers || meta.suggestCall),
          const Padding(padding: EdgeInsets.only(top: 12), child: Text('Map © Google · Places © OpenStreetMap contributors. Distances are straight-line; times are estimates. Check phone numbers before relying on them.', style: TextStyle(fontSize: 11, color: _C.mute, height: 1.4))),
        ]),
      ),
    );
  }

  Widget _heading(String t) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _C.ink, letterSpacing: .2)));

  List<Widget> _section(PlaceType t, List<NearbyPlace> rows) => [
    _heading('${placeTypeLabel(t)} near you'),
    if (rows.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('None found within 12 km in our directory.', style: const TextStyle(fontSize: 13, color: _C.mute))),
    for (final p in rows.take(3)) _row(p),
  ];

  Widget _emptyNote() => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
    child: const Text('We found no listed places near you for this emergency yet. Please call an emergency number below. We keep looking while you call.', style: TextStyle(fontSize: 14, color: _C.mute, height: 1.4)),
  );

  Widget _row(NearbyPlace p) {
    final key = p.type.name;
    final facts = [if (p.distanceKm != null) '${p.distanceKm!.toStringAsFixed(1)} km', if (p.is24h == true) 'Open 24 h'].join(' · ');
    return GestureDetector(
      onTap: () {
        setState(() {
          _selected = p.id;
          _selFromMap = false;
        });
        if (p.hasPosition) _map?.animateCamera(CameraUpdate.newLatLng(LatLng(p.latitude!, p.longitude!)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.id == _selected ? _C.brand : Colors.transparent, width: 2)),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: _typeColor(key), shape: BoxShape.circle), child: Icon(_typeIcon(key), color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.ink))),
              if (p.phone.isNotEmpty && !p.verified) const Padding(padding: EdgeInsets.only(left: 6), child: _UnverifiedPhoneTag()),
            ]),
            if (facts.isNotEmpty) Text(facts, style: const TextStyle(fontSize: 12, color: _C.mute)),
          ])),
          if (p.phone.isNotEmpty) IconButton(tooltip: kIsWeb ? 'Copy ${p.phone}' : 'Call', icon: const Icon(Icons.call, color: _C.brand), onPressed: () => _call(p.phone)),
          if (p.hasPosition) IconButton(tooltip: 'Directions', icon: const Icon(Icons.directions, color: _C.brand), onPressed: () => _showRoute(_Dest(id: p.id, name: p.name, typeKey: p.type.name, lat: p.latitude!, lng: p.longitude!, phone: p.phone))),
        ]),
      ),
    );
  }

  /// One calm status line under the top bar: what the system is doing right now. Solid (a status, not a control), so it never stacks glass on glass.
  Widget _banner(HelpMeta meta) {
    String? text;
    var warn = false, working = false;
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
      working = true;
    } else if (meta.asking.isNotEmpty) {
      text = 'Asking ${meta.asking.join(' and ')}…';
      working = true;
    } else if (_state.loaded && meta.noLive && (meta.state == 'unfilled' || meta.suggestCall)) {
      text = _state.options.isEmpty ? 'No registered responder is free right now. Use the emergency numbers below.' : 'No registered responder is free right now. Call a place below, or tap Directions.';
      warn = true;
    }
    if (text == null) return const SizedBox.shrink();
    final fg = warn ? Tk.warnInk : Tk.ink;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AnimatedSwitcher(
        duration: Tk.normal,
        switchInCurve: Tk.settle,
        child: Container(
          key: ValueKey(text),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: warn ? Tk.warnTint : Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4))]),
          child: Row(children: [
            if (working) const PulseDot(size: 9) else Icon(held.isNotEmpty ? Icons.directions_car_filled_outlined : Icons.info_outline, size: 20, color: warn ? Tk.warnInk : Tk.brand),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg, height: 1.3))),
          ]),
        ),
      ),
    );
  }

  Widget _numbers({bool prominent = false}) => Wrap(spacing: 8, runSpacing: 8, children: [
    for (final n in kEmergencyNumbers)
      prominent
          ? FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: n.number == '999' || n.number == '112' ? _C.danger : const Color(0xFF8E3030), minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => _call(n.number),
              icon: const Icon(Icons.call, size: 18),
              label: Text('${n.number}  ${n.label}'),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: _C.danger, minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => _call(n.number),
              icon: const Icon(Icons.call, size: 16),
              label: Text('${n.number}  ${n.label}'),
            ),
  ]);

  Widget _helplines() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text("You're not alone", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _C.ink)),
    const SizedBox(height: 8),
    const Text('Talking to someone can help. These lines are free to call.', style: TextStyle(fontSize: 15, color: _C.mute, height: 1.45)),
    const SizedBox(height: 18),
    FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _C.brand, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () => _call('1199'), icon: const Icon(Icons.call), label: Text(kIsWeb ? 'Call 1199 (copied)' : 'Call 1199 (Kenya Red Cross)')),
    const SizedBox(height: 12),
    _numbers(),
  ]);

  Widget _statusChip(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg, letterSpacing: .3)),
  );

  Widget _card(HelpOption o) {
    final selected = o.refId == _selected;
    final key = _keyOfOption(o);
    final label = o.isLive ? _statusChip('LIVE', const Color(0xFFE8F5E9), const Color(0xFF1B5E20)) : (o.kind == 'hotline' ? _statusChip('CALL ONLY', const Color(0xFFEDE7F6), const Color(0xFF4527A0)) : _statusChip('LISTED', const Color(0xFFEDEDED), const Color(0xFF444444)));
    final eta = _etaSeconds[o.refId] != null ? '${(_etaSeconds[o.refId]! / 60).round().clamp(1, 999)} min' : o.etaText;
    final dist = o.distanceKm == null ? null : '${o.distanceKm!.toStringAsFixed(1)} km';
    final facts = [if (eta != null) eta, if (dist != null) dist, if (o.is24h == true) 'Open 24 h'].join(' · ');
    final phone = o.phone.isNotEmpty ? o.phone : (o.phones.isNotEmpty ? o.phones.first : '');
    return GestureDetector(
      onTap: () {
        setState(() {
          _selected = o.refId;
          _selFromMap = false;
        });
        if (o.hasPosition) _map?.animateCamera(CameraUpdate.newLatLng(LatLng(o.latitude!, o.longitude!)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? _C.brand : Colors.transparent, width: 2), boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: _typeColor(key), shape: BoxShape.circle), child: Icon(_typeIcon(key), color: Colors.white)),
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
      if (o.hasPosition) ...[if (callBtn != null) const SizedBox(width: 10), OutlinedButton.icon(onPressed: () => _showRoute(_Dest(id: o.refId, name: o.name, typeKey: _keyOfOption(o), lat: o.latitude!, lng: o.longitude!, phone: phone)), icon: const Icon(Icons.directions_outlined, size: 18), label: const Text('Directions'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))],
    ]);
  }
}

/// A small red tag shown next to a facility whose phone number an administrator has not verified.
class _UnverifiedPhoneTag extends StatelessWidget {
  const _UnverifiedPhoneTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE8B4B4))),
    child: const Text('Unverified phone', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF9B1C1C))),
  );
}
