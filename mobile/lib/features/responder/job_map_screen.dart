// Live mutual tracking on the responder side, Uber-style: the caller's blue dot moves on the map as they
// (or their phone) move, and the unit sees itself as a car pin. Positions come from incidents/{id}/tracks,
// written by the resident's phone while the alert is open and by this unit while it holds the job.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import '../resident/map/help_models.dart' show TrackPoint, haversineKm;
import '../resident/map/map_style.dart';
import '../resident/map/pin_factory.dart';
import 'incoming_alert_screen.dart' show openInMaps;
import 'responder_theme.dart';

class JobMapScreen extends StatefulWidget {
  const JobMapScreen({super.key, required this.offer});
  final Offer offer;

  @override
  State<JobMapScreen> createState() => _JobMapScreenState();
}

class _JobMapScreenState extends State<JobMapScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _map;
  final Map<String, BitmapDescriptor> _pins = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _selfTimer;

  LatLng? _resident;
  LatLng? _me;
  double? _residentAccuracy;
  DateTime? _residentAt;
  bool _moving = false;
  String _fitKey = '';

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..addListener(() => setState(() {}));
  LatLng? _from;
  LatLng? _to;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadPins();
    _watchTracks();
    _readSelf();
    _selfTimer = Timer.periodic(const Duration(seconds: 10), (_) => _readSelf());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _selfTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadPins() async {
    for (final k in ['me', 'live']) {
      final p = await PinFactory.pin(k, big: true);
      if (p != null) _pins[k] = p;
    }
    if (mounted) setState(() {});
  }

  void _watchTracks() {
    _sub = FirebaseFirestore.instance
        .collection('incidents')
        .doc(widget.offer.incidentId)
        .collection('tracks')
        .snapshots()
        .listen((q) {
      for (final d in q.docs) {
        if (d.id == _uid) continue; // that one is my own unit
        final p = TrackPoint.tryParse(d.data());
        if (p == null) continue;
        final next = LatLng(p.latitude, p.longitude);
        if (!mounted) return;
        setState(() {
          _from = _resident ?? next;
          _to = next;
          _resident = next;
          _residentAccuracy = (d.data()['accuracy'] as num?)?.toDouble();
          _residentAt = p.at;
          _moving = (p.speed ?? 0) > 1.2;
        });
        _anim.forward(from: 0);
        _fit();
        return;
      }
    }, onError: (Object _) {/* rules / offline: the map still shows the last known point */});
  }

  Future<void> _readSelf() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)));
      if (!mounted) return;
      setState(() => _me = LatLng(pos.latitude, pos.longitude));
      _fit();
    } catch (_) {/* optional: the resident pin still shows */}
  }

  LatLng? get _residentNow {
    final b = _to;
    if (b == null) return null;
    final a = _from;
    if (a == null) return b;
    final t = Curves.easeOut.transform(_anim.value);
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  LatLng? get _offerPoint {
    final la = widget.offer.latitude, lo = widget.offer.longitude;
    return la != null && lo != null ? LatLng(la, lo) : null;
  }

  LatLng? get _destination => _resident ?? _offerPoint;

  double? get _km {
    final me = _me;
    final d = _destination;
    if (me == null || d == null) return null;
    return haversineKm(me.latitude, me.longitude, d.latitude, d.longitude);
  }

  void _fit() {
    final d = _destination;
    if (d == null) return;
    final pts = [?_me, d];
    final key = pts.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').join('|');
    if (key == _fitKey || _map == null) return;
    _fitKey = key;
    if (pts.length < 2) {
      _map?.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    var minLa = pts.first.latitude, maxLa = minLa, minLo = pts.first.longitude, maxLo = minLo;
    for (final p in pts) {
      if (p.latitude < minLa) minLa = p.latitude;
      if (p.latitude > maxLa) maxLa = p.latitude;
      if (p.longitude < minLo) minLo = p.longitude;
      if (p.longitude > maxLo) maxLo = p.longitude;
    }
    final center = LatLng((minLa + maxLa) / 2, (minLo + maxLo) / 2);
    final span = ((maxLa - minLa).abs() + (maxLo - minLo).abs()).clamp(0.002, 1.5);
    final zoom = (14.5 - (span * 40).clamp(0, 3.5)).clamp(11.0, 16.0);
    _map?.animateCamera(CameraUpdate.newLatLngZoom(center, zoom));
  }

  Set<Marker> _markers() {
    final resident = _residentNow;
    final fresh = _residentAt != null && DateTime.now().difference(_residentAt!).inMinutes < 3;
    final name = (widget.offer.residentFirstName ?? '').trim();
    return {
      if (resident != null)
        Marker(
          markerId: const MarkerId('caller'),
          position: resident,
          icon: _pins['me'] ?? PinFactory.fallback('me'),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: name.isEmpty ? 'Caller' : name, snippet: fresh ? 'Live location' : 'Last known location'),
          zIndexInt: 5,
        ),
      if (_me != null)
        Marker(
          markerId: const MarkerId('me'),
          position: _me!,
          icon: _pins['live'] ?? PinFactory.fallback('live'),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Your unit'),
          zIndexInt: 4,
        ),
    };
  }

  Set<Circle> _circles() {
    final resident = _resident;
    final acc = _residentAccuracy;
    if (resident == null || acc == null || acc <= 40) return const {};
    return {Circle(circleId: const CircleId('acc'), center: resident, radius: acc, fillColor: const Color(0x221A73E8), strokeColor: const Color(0x551A73E8), strokeWidth: 1)};
  }

  String? get _freshness {
    final at = _residentAt;
    if (at == null) return null;
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 90) return 'Live';
    final m = (s / 60).round();
    return 'Last seen $m min ago';
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destination;
    if (destination == null && _pins.isNotEmpty) {
      return Scaffold(
        backgroundColor: RC.bg,
        appBar: AppBar(backgroundColor: RC.bg, foregroundColor: RC.text, elevation: 0, title: const Text('Live tracking')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('The caller’s location is not available for this job. Call them to confirm where to go.', textAlign: TextAlign.center, style: TextStyle(color: RC.soft, height: 1.5)),
          ),
        ),
      );
    }
    final km = _km;
    final freshness = _freshness;
    return Scaffold(
      backgroundColor: RC.bg,
      body: Stack(children: [
        Positioned.fill(
          child: _pins.isEmpty || destination == null
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                  initialCameraPosition: CameraPosition(target: destination, zoom: 14.5),
                  style: kEmergencyMapStyle,
                  markers: _markers(),
                  circles: _circles(),
                  minMaxZoomPreference: const MinMaxZoomPreference(10, 19),
                  onMapCreated: (c) {
                    _map = c;
                    _fit();
                  },
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  buildingsEnabled: false,
                  padding: const EdgeInsets.only(top: 110, bottom: 190),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.of(context).maybePop()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))]),
                  child: Row(children: [
                    Icon(_moving ? Icons.directions_run : Icons.my_location, size: 18, color: RC.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        const Text('CALLER LOCATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: RC.muted, letterSpacing: .8)),
                        Text(
                          [if (_moving) 'Moving', ?freshness, if (km != null) '${km.toStringAsFixed(1)} km away'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: RC.text),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26)), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16)]),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  km == null ? 'Finding your position…' : '${km.toStringAsFixed(1)} km to the caller',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: RC.text),
                ),
                const SizedBox(height: 2),
                Text(
                  _moving ? 'The caller is moving. Their dot updates live.' : 'The caller’s dot is their live phone location.',
                  style: const TextStyle(fontSize: 13, color: RC.soft),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if ((widget.offer.residentPhone ?? '').isNotEmpty) ...[
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: RC.accept, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: widget.offer.residentPhone)),
                          icon: const Icon(Icons.call, size: 18),
                          label: const Text('Call caller', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => openInMaps(widget.offer.latitude, widget.offer.longitude),
                        icon: const Icon(Icons.navigation_outlined, size: 18),
                        label: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
