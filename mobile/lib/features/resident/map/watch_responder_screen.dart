// The resident watches the unit that accepted their alert: its live position glides along the road, the route still to go is drawn,
// and the arrival time updates as it gets closer. Read-only. Positions and routes come from the same sources as the help map
// (incidents/{id}/tracks and the incident_route function); nothing here changes the alert.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/tokens.dart';
import '../../tracking/nav_logic.dart';
import '../../tracking/nav_map_view.dart';
import '../../tracking/nav_widgets.dart';
import '../../tracking/route_logic.dart';
import '../../tracking/track_logic.dart';
import 'help_models.dart' show HelpOption, HelpState, RouteInfo, TrackPoint;
import 'help_repository.dart';

class WatchResponderScreen extends StatefulWidget {
  const WatchResponderScreen({super.key, required this.incidentId, this.repo});

  final String incidentId;
  final HelpRepository? repo;

  @override
  State<WatchResponderScreen> createState() => _WatchResponderScreenState();
}

class _WatchResponderScreenState extends State<WatchResponderScreen> with SingleTickerProviderStateMixin {
  late final HelpRepository _repo = widget.repo ?? HelpRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _tick;

  HelpState _help = const HelpState();
  Map<String, TrackPoint> _tracks = const {};
  IncidentInfo _info = const IncidentInfo();

  RouteInfo? _route;
  bool _routeBusy = false;
  DateTime? _routeAt;
  String _routeFor = '';

  final Map<String, LatLngPoint> _from = {};
  final Map<String, LatLngPoint> _to = {};
  bool _autoFit = true;

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
    ..addListener(() {
      if (mounted) setState(() {});
    });

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _subs.add(_repo.watchOptions(widget.incidentId).listen((s) {
      if (!mounted) return;
      setState(() => _help = s);
      _maybeRoute();
    }));
    _subs.add(_repo.watchIncident(widget.incidentId).listen((i) {
      if (mounted) setState(() => _info = i);
    }));
    _subs.add(_repo.watchTracks(widget.incidentId).listen((t) {
      if (!mounted) return;
      for (final e in t.entries) {
        final now = LatLngPoint(e.value.latitude, e.value.longitude);
        _from[e.key] = _shownOf(e.key) ?? now;
        _to[e.key] = now;
      }
      setState(() => _tracks = t);
      _anim.forward(from: 0);
      _maybeRoute();
    }));
    _tick = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeRoute(force: true);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _tick?.cancel();
    _anim.dispose();
    super.dispose();
  }

  HelpOption? get _unit {
    for (final o in _help.options) {
      if (o.isLive && o.holdsJob) return o;
    }
    return null;
  }

  /// The track of the unit: the one the option points at, else any track that is not mine.
  String? get _unitId {
    final u = _unit;
    if (u == null) return null;
    if (_tracks.containsKey(u.refId)) return u.refId;
    for (final k in _tracks.keys) {
      if (k != _uid) return k;
    }
    return u.refId;
  }

  LatLngPoint? _shownOf(String id) {
    final to = _to[id];
    if (to == null) return null;
    return glidePoint(from: _from[id] ?? to, to: to, t: _anim.value);
  }

  LatLngPoint? get _unitShown {
    final id = _unitId;
    final u = _unit;
    if (id != null) {
      final s = _shownOf(id);
      if (s != null) return s;
    }
    if (u != null && u.hasPosition) return LatLngPoint(u.latitude!, u.longitude!);
    return null;
  }

  /// Where I am: my own live position when it is being written, otherwise where the alert was raised.
  LatLngPoint? get _mePoint {
    final own = _uid == null ? null : _tracks[_uid];
    if (own != null) return LatLngPoint(own.latitude, own.longitude);
    final la = _info.latitude;
    final lo = _info.longitude;
    return la != null && lo != null ? LatLngPoint(la, lo) : null;
  }

  Future<void> _maybeRoute({bool force = false}) async {
    final u = _unit;
    final id = _unitId;
    if (u == null || id == null || _routeBusy || u.status == 'arrived') return;
    final last = _routeAt;
    final stale = last == null || DateTime.now().difference(last) >= const Duration(seconds: 25);
    if (!force && !stale && _routeFor == id) return;
    _routeBusy = true;
    _routeAt = DateTime.now();
    final r = await _repo.route(widget.incidentId, id);
    _routeBusy = false;
    if (!mounted) return;
    setState(() {
      _route = r;
      _routeFor = id;
    });
  }

  List<LatLngPoint> get _routePoints {
    final r = _route;
    if (r == null || r.estimate) return const <LatLngPoint>[];
    return [for (final p in r.points) LatLngPoint(p.lat, p.lng)];
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unit;
    if (unit == null) {
      return Scaffold(
        backgroundColor: Tk.bg,
        appBar: AppBar(backgroundColor: Tk.bg, foregroundColor: Tk.ink, elevation: 0, title: const Text('Your responder')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No unit has accepted yet. As soon as one does, you will see it moving here.', textAlign: TextAlign.center, style: TextStyle(color: Tk.mute, height: 1.5, fontSize: 15)),
          ),
        ),
      );
    }
    final now = DateTime.now();
    final unitPoint = _unitShown;
    final me = _mePoint;
    final arrived = unit.status == 'arrived';
    final pts = _routePoints;
    final r = _route;
    RouteProgress? progress;
    if (!arrived && unitPoint != null && pts.length >= 2 && r != null) {
      progress = progressOnRoute(
        route: pts,
        steps: const <RouteStep>[],
        lat: unitPoint.lat,
        lng: unitPoint.lng,
        routeDistM: r.distanceMeters > 0 ? r.distanceMeters.toDouble() : routeLengthM(pts),
        routeDurSec: r.etaSeconds,
      );
    }
    final unitId = _unitId;
    final track = unitId == null ? null : _tracks[unitId];
    final freshness = freshnessOf(now, track?.at, null);
    final etaSec = progress?.etaSec ?? (unit.etaMin == null ? null : (unit.etaMin! * 60).round());

    String title;
    String subtitle;
    if (arrived) {
      title = 'Arrived';
      subtitle = '${unit.name} is with you';
    } else {
      title = bigEtaText(etaSec);
      final dist = progress == null ? null : distanceText(progress.remainingM);
      subtitle = [unit.name, ?dist, if (etaSec != null) 'arrive about ${arrivalClock(now, etaSec)}'].join(' · ');
    }
    final String? note = arrived ? null : (progress == null && unit.etaText != null ? 'Estimate: ${unit.etaText}. The road route will appear shortly.' : 'An estimate. Traffic can change it.');

    final fitPoints = <LatLngPoint>[?unitPoint, ?me];
    final fitKey = !_autoFit || fitPoints.isEmpty ? '' : fitPoints.map((p) => '${p.lat.toStringAsFixed(3)},${p.lng.toStringAsFixed(3)}').join('|');
    final chipColor = switch (freshness) {
      TrackFreshness.live => Tk.okInk,
      TrackFreshness.delayed => Tk.warnInk,
      _ => Tk.faint,
    };

    final card = NavBottomCard(
      title: title,
      subtitle: subtitle,
      note: note,
      actions: [
        if (unit.phone.isNotEmpty)
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Tk.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: unit.phone.replaceAll(' ', ''))),
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Call responder', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: NavMapView(
                markers: [
                  if (me != null) NavMarkerData(id: 'caller', kind: 'caller', position: me, accuracyM: _info.accuracyM, title: 'You'),
                  if (unitPoint != null)
                    NavMarkerData(id: 'unit', kind: 'unit', position: unitPoint, heading: track?.heading, title: unit.name, snippet: freshnessLabel(freshness, track?.at, now)),
                ],
                traveled: progress?.traveled ?? const <LatLngPoint>[],
                remaining: progress?.remaining ?? const <LatLngPoint>[],
                fitPoints: fitPoints,
                fitKey: fitKey,
                padding: const EdgeInsets.only(top: 100, bottom: 8),
                onUserGesture: () {
                  if (_autoFit) setState(() => _autoFit = false);
                },
                showRecenter: !_autoFit,
                onRecenter: () => setState(() => _autoFit = true),
                recenterIcon: Icons.zoom_out_map,
                recenterTooltip: 'Show both of us',
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  MapRoundButton(icon: Icons.arrow_back_ios_new, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))]),
                      child: Row(children: [
                        const Icon(Icons.local_hospital_outlined, size: 20, color: Tk.brand),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            arrived ? 'Your responder has arrived' : 'Your responder is on the way',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Tk.ink),
                          ),
                        ),
                        if (!arrived) FreshChip(label: freshnessLabel(freshness, track?.at, now), color: chipColor),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        card,
      ]),
    );
  }
}
