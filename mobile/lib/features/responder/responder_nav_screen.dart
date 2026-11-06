// In-app navigation for a unit that holds a job: its own position glides along the road, the route and the next turn are drawn
// on the map, and the caller's live dot moves as they move. The server only supplies routes (help_directions); nothing here decides
// who is sent or changes the job. If GPS, the route or the caller's position is missing, the screen says so and keeps working.
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart' show Offer;
import '../tracking/maneuver_icons.dart';
import '../tracking/nav_logic.dart';
import '../tracking/nav_map_view.dart';
import '../tracking/nav_repository.dart';
import '../tracking/nav_widgets.dart';
import '../tracking/route_logic.dart';
import '../tracking/track_logic.dart';
import 'incoming_alert_screen.dart' show openInMaps;
import 'responder_theme.dart' show RC;

class ResponderNavScreen extends StatefulWidget {
  const ResponderNavScreen({super.key, required this.offer, this.repo});

  final Offer offer;
  final NavRepository? repo;

  @override
  State<ResponderNavScreen> createState() => _ResponderNavScreenState();
}

class _ResponderNavScreenState extends State<ResponderNavScreen> with SingleTickerProviderStateMixin {
  late final NavRepository _repo = widget.repo ?? NavRepository();
  StreamSubscription<Map<String, NavTrack>>? _trackSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _tick;

  LatLngPoint? _me;
  LatLngPoint? _meFrom;
  double? _meAccuracy;
  double _meHeading = 0;
  double _meSpeed = 0;
  String? _gpsNote;

  NavTrack? _caller;
  LatLngPoint? _callerFrom;

  NavRoute? _route;
  DateTime? _routeAt;
  LatLngPoint? _routeDest;
  bool _routeBusy = false;
  bool _routeFailed = false;
  bool _offRoute = false;
  final OffRouteMonitor _monitor = OffRouteMonitor();

  bool _follow = true;

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
    ..addListener(() {
      if (mounted) setState(() {});
    });

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _watchCaller();
    _startGps();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeReroute();
    });
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _gpsSub?.cancel();
    _tick?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _watchCaller() {
    _trackSub = _repo.watchTracks(widget.offer.incidentId).listen((m) {
      NavTrack? other;
      for (final e in m.entries) {
        if (e.key == _uid) continue; // that one is my own unit
        other = e.value;
        break;
      }
      final o = other;
      if (o == null || !mounted) return;
      setState(() {
        _callerFrom = _callerShown ?? o.position;
        _caller = o;
      });
      _anim.forward(from: 0);
      _maybeReroute();
    }, onError: (Object _) {/* rules or offline: the map keeps the last known point */});
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _gpsNote = 'Turn on location to navigate.');
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsNote = 'Allow location for Nusuru to navigate.');
        return;
      }
      _gpsSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 4)).listen(
        _onPosition,
        onError: (Object _) {
          if (mounted) setState(() => _gpsNote = 'Waiting for GPS…');
        },
      );
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && _me == null) _onPosition(last);
      } catch (_) {/* not supported everywhere: the stream will deliver the first fix */}
    } catch (_) {
      if (mounted) setState(() => _gpsNote = 'Waiting for GPS…');
    }
  }

  void _onPosition(Position p) {
    if (!mounted || !validCoordinate(p.latitude, p.longitude)) return;
    final now = DateTime.now();
    final next = LatLngPoint(p.latitude, p.longitude);
    final speed = p.speed.isFinite && p.speed >= 0 ? p.speed : 0.0;
    setState(() {
      _meFrom = _meShown ?? next;
      _me = next;
      _meAccuracy = p.accuracy.isFinite ? p.accuracy : null;
      _meSpeed = speed;
      _gpsNote = null;
      final h = effectiveHeading(lastHeading: _meHeading, newHeading: p.heading.isFinite ? p.heading : null, speedMps: speed);
      _meHeading = smoothBearing(_meHeading, h);
    });
    _anim.forward(from: 0);
    final route = _route;
    if (route != null && route.points.length >= 2) {
      final snap = snapToRoute(route.points, next.lat, next.lng);
      if (snap != null) _offRoute = _monitor.onFix(now: now, crossTrackM: snap.crossTrackM, accuracyM: _meAccuracy);
    }
    _maybeReroute();
  }

  LatLngPoint? get _offerPoint {
    final la = widget.offer.latitude;
    final lo = widget.offer.longitude;
    if (la == null || lo == null || !validCoordinate(la, lo)) return null;
    return LatLngPoint(la, lo);
  }

  LatLngPoint? get _callerShown {
    final c = _caller;
    if (c == null) return null;
    return glidePoint(from: _callerFrom ?? c.position, to: c.position, t: _anim.value);
  }

  LatLngPoint? get _meShown {
    final to = _me;
    if (to == null) return null;
    return glidePoint(from: _meFrom ?? to, to: to, t: _anim.value, route: _route?.points ?? const <LatLngPoint>[]);
  }

  TrackFreshness get _callerFreshness {
    final c = _caller;
    if (c == null) return TrackFreshness.none;
    return freshnessOf(DateTime.now(), c.at, c.sharing);
  }

  /// Where to navigate: the caller's phone when it is fresh and accurate, otherwise the place that was reported.
  LatLngPoint? get _dest {
    final c = _caller;
    final o = _offerPoint;
    final target = chooseDefaultTarget(callerFreshness: _callerFreshness, callerAccuracyM: c?.accuracy);
    if (c != null && (target == FollowTarget.caller || o == null)) return c.position;
    return o;
  }

  /// A route is only shown while it still leads to where we are going. If the destination has moved a long way
  /// (for example the caller's live position replaced the reported place), the old route is dropped, never drawn.
  bool _routeUsable(LatLngPoint dest) {
    final r = _route;
    final at = _routeDest;
    return r != null && r.points.length >= 2 && at != null && distanceMeters(at, dest) < 500;
  }

  void _maybeReroute() {
    final me = _me;
    final dest = _dest;
    if (me == null || dest == null || _routeBusy) return;
    final usable = _routeUsable(dest);
    if (!usable && _route != null) _route = null;
    final last = _routeDest;
    final moved = usable && last != null ? distanceMeters(last, dest) : 0.0;
    final ask = needReroute(
      hasRoute: usable,
      offRoute: _offRoute,
      destMovedM: moved,
      now: DateTime.now(),
      lastRouteAt: _routeAt,
    );
    if (ask) _fetchRoute(me, dest);
  }

  Future<void> _fetchRoute(LatLngPoint me, LatLngPoint dest) async {
    _routeBusy = true;
    _routeAt = DateTime.now(); // rate-limited even when the call fails
    final r = await _repo.directions(me, dest);
    _routeBusy = false;
    if (!mounted) return;
    // A route must start near me and end near the destination, otherwise it is ignored.
    final good = r != null && r.points.length >= 2 && distanceMeters(r.points.last, dest) < 1500 && distanceMeters(r.points.first, me) < 1500;
    setState(() {
      if (good) {
        _route = r;
        _routeDest = dest;
      }
      _routeFailed = !good;
      _offRoute = false;
    });
    _monitor.markRerouted(DateTime.now());
  }

  RouteProgress? _progressNow(LatLngPoint dest) {
    final r = _route;
    final me = _me;
    if (r == null || me == null || !_routeUsable(dest)) return null;
    final p = _progressUnchecked(r, me);
    if (p == null) return null;
    // A route far longer than the straight line is wrong for this trip: show the straight-line distance instead.
    if (p.remainingM > math.max(3000.0, distanceMeters(me, dest) * 4)) return null;
    return p;
  }

  RouteProgress? _progressUnchecked(NavRoute r, LatLngPoint me) {
    return progressOnRoute(
      route: r.points,
      steps: r.steps,
      lat: me.lat,
      lng: me.lng,
      routeDistM: r.distanceM > 0 ? r.distanceM : routeLengthM(r.points),
      routeDurSec: r.durationSec,
    );
  }

  Widget _noLocation() => Scaffold(
        backgroundColor: RC.bg,
        appBar: AppBar(backgroundColor: RC.bg, foregroundColor: RC.text, elevation: 0, title: const Text('Live tracking')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('The caller’s location is not available for this job. Call them to confirm where to go.', textAlign: TextAlign.center, style: TextStyle(color: RC.soft, height: 1.5)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dest = _dest;
    if (dest == null) return _noLocation();
    final now = DateTime.now();
    final me = _me;
    final progress = _progressNow(dest);
    final meShown = _meShown;
    final callerShown = _callerShown;
    final offerPoint = _offerPoint;
    final straightM = me == null ? null : distanceMeters(me, dest);
    final freshness = _callerFreshness;
    final name = (widget.offer.residentFirstName ?? '').trim();
    final phone = (widget.offer.residentPhone ?? '').trim();
    final size = MediaQuery.sizeOf(context);

    final speedZoom = zoomForSpeed(speedMps: _meSpeed, distToTargetM: straightM, distToStepEndM: progress?.next?.distToStepEndM);
    var followZoom = speedZoom;
    if (me != null && straightM != null && straightM > 400) {
      final fitZ = fitView(points: [me, dest], widthPx: size.width, heightPx: size.height).zoom;
      followZoom = math.min(speedZoom, math.max(11.0, fitZ - 1.0));
    }

    final markers = <NavMarkerData>[
      if (offerPoint != null) NavMarkerData(id: 'dest', kind: 'dest', position: offerPoint, title: 'Reported location'),
      if (callerShown != null)
        NavMarkerData(
          id: 'caller',
          kind: 'caller',
          position: callerShown,
          accuracyM: _caller?.accuracy,
          title: name.isEmpty ? 'Caller' : name,
          snippet: freshnessLabel(freshness, _caller?.at, now),
        ),
      if (meShown != null) NavMarkerData(id: 'unit', kind: 'unit', position: meShown, heading: _meHeading, accuracyM: _meAccuracy, title: 'Your unit'),
    ];

    final next = progress?.next;
    final near = straightM != null && arrivalSuggested(distToTargetM: straightM, speedMps: _meSpeed, accuracyM: _meAccuracy);
    final rerouting = _routeBusy && _route != null;

    String title;
    String subtitle;
    if (progress != null) {
      title = bigEtaText(progress.etaSec);
      subtitle = '${distanceText(progress.remainingM)} · arrive about ${arrivalClock(now, progress.etaSec)}';
    } else if (me != null && straightM != null) {
      title = distanceText(straightM);
      subtitle = 'straight-line distance';
    } else {
      title = 'Finding your position…';
      subtitle = _gpsNote ?? 'Waiting for GPS';
    }
    String? note;
    if (near) {
      note = 'You look close to the caller. Mark yourself arrived on the job screen.';
    } else if (_gpsNote != null && me != null) {
      note = _gpsNote;
    } else if ((_meAccuracy ?? 0) > 300) {
      note = 'Your location is only approximate (a computer or weak GPS). Use a phone outdoors for accurate navigation.';
    } else if (_routeFailed && progress == null && me != null) {
      note = 'The road route is not available right now. Showing the straight-line distance.';
    } else if (freshness == TrackFreshness.stale || freshness == TrackFreshness.none) {
      note = 'The caller’s live position is not updating. Navigating to the reported location.';
    }

    final chipColor = switch (freshness) {
      TrackFreshness.live => const Color(0xFF1B5E20),
      TrackFreshness.delayed => const Color(0xFF9C3700),
      _ => const Color(0xFF6B6B6B),
    };

    final card = NavBottomCard(
      title: title,
      subtitle: subtitle,
      note: note,
      actions: [
        if (phone.isNotEmpty)
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: RC.accept, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Call caller', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => openInMaps(dest.lat, dest.lng),
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: const Text('Google Maps', style: TextStyle(fontWeight: FontWeight.w700)),
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
                markers: markers,
                traveled: progress?.traveled ?? const <LatLngPoint>[],
                remaining: progress?.remaining ?? const <LatLngPoint>[],
                follow: _follow && me != null,
                followPoint: _me,
                followHeading: _meHeading,
                followZoom: followZoom,
                headingUp: _meSpeed >= 1.0,
                fitPoints: [?me, dest],
                fitKey: me == null ? 'dest' : '',
                padding: EdgeInsets.only(top: next != null ? 190 : 120, bottom: 8),
                onUserGesture: () {
                  if (_follow) setState(() => _follow = false);
                },
                showRecenter: !_follow && me != null,
                onRecenter: () => setState(() => _follow = true),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    MapRoundButton(icon: Icons.arrow_back_ios_new, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))]),
                        child: Row(children: [
                          const Icon(Icons.person_pin_circle_outlined, size: 20, color: RC.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name.isEmpty ? 'Caller' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: RC.text),
                            ),
                          ),
                          FreshChip(label: freshnessLabel(freshness, _caller?.at, now), color: chipColor),
                        ]),
                      ),
                    ),
                  ]),
                  if (next != null) ...[
                    const SizedBox(height: 10),
                    TurnBanner(
                      icon: maneuverIcon(next.step.maneuver),
                      distance: turnDistanceText(next.distToStepEndM),
                      text: next.step.instruction.isEmpty ? 'Continue' : next.step.instruction,
                    ),
                  ],
                  if (rerouting || _offRoute) ...[
                    const SizedBox(height: 8),
                    const FreshChip(label: 'Finding a new route…', color: Color(0xFF9C3700)),
                  ],
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
