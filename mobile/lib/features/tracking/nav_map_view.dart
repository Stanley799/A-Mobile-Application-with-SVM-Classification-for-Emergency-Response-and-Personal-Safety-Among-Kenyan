// The shared live map. It draws what it is given (markers, the route, accuracy circles) and looks after the camera:
// it follows a point with a speed-aware zoom, or frames a set of points, and it swaps between a calm and a detailed map look as you zoom.
// It decides nothing about who is where: the screens do that. Touching the map tells the screen (onUserGesture) so the camera stops fighting the finger.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../resident/map/maps_available.dart';
import 'nav_logic.dart';
import 'nav_pins.dart';
import 'nav_styles.dart';
import 'nav_widgets.dart';
import 'route_logic.dart' show LatLngPoint;

/// One thing to draw. [kind] is `unit`, `caller` or `dest`.
class NavMarkerData {
  const NavMarkerData({required this.id, required this.kind, required this.position, this.heading, this.accuracyM, this.title, this.snippet});

  final String id;
  final String kind;
  final LatLngPoint position;
  final double? heading;
  final double? accuracyM;
  final String? title;
  final String? snippet;
}

class NavMapView extends StatefulWidget {
  const NavMapView({
    super.key,
    required this.markers,
    this.traveled = const <LatLngPoint>[],
    this.remaining = const <LatLngPoint>[],
    this.follow = false,
    this.followPoint,
    this.followHeading,
    this.followZoom = 16.5,
    this.headingUp = false,
    this.fitPoints = const <LatLngPoint>[],
    this.fitKey = '',
    this.padding = EdgeInsets.zero,
    this.onUserGesture,
    this.showRecenter = false,
    this.onRecenter,
    this.recenterIcon = Icons.my_location,
    this.recenterTooltip = 'Recenter',
  });

  final List<NavMarkerData> markers;

  /// The part of the route already driven (grey) and the part still to go (bold blue).
  final List<LatLngPoint> traveled;
  final List<LatLngPoint> remaining;

  /// When [follow] is true the camera keeps [followPoint] in view at [followZoom] (and turns with [followHeading] when [headingUp]).
  final bool follow;
  final LatLngPoint? followPoint;
  final double? followHeading;
  final double followZoom;
  final bool headingUp;

  /// When not following, the camera frames [fitPoints] each time [fitKey] changes. An empty key means: leave the camera alone.
  final List<LatLngPoint> fitPoints;
  final String fitKey;

  /// Space covered by the screen's own header and bottom card, so the map centres in what is left.
  final EdgeInsets padding;
  final VoidCallback? onUserGesture;
  final bool showRecenter;
  final VoidCallback? onRecenter;
  final IconData recenterIcon;
  final String recenterTooltip;

  @override
  State<NavMapView> createState() => _NavMapViewState();
}

class _NavMapViewState extends State<NavMapView> {
  final Map<String, BitmapDescriptor> _pins = {};
  GoogleMapController? _map;
  NavMapStyle _style = NavMapStyle.overview;
  bool _satellite = false;
  DateTime _lastCamera = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastFitKey = '';

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    for (final k in const ['unit', 'caller', 'dest']) {
      final p = await NavPins.pin(k);
      if (p != null) _pins[k] = p;
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant NavMapView old) {
    super.didUpdateWidget(old);
    if (_map == null) return;
    if (widget.follow) {
      if (!old.follow) _lastCamera = DateTime.fromMillisecondsSinceEpoch(0);
      final p = widget.followPoint;
      if (p != null) _follow(p);
    } else if (widget.fitKey.isNotEmpty && widget.fitKey != _lastFitKey) {
      _fit();
    }
  }

  void _follow(LatLngPoint p) {
    final now = DateTime.now();
    if (now.difference(_lastCamera) < const Duration(milliseconds: 700)) return;
    _lastCamera = now;
    final heading = widget.followHeading;
    final up = widget.headingUp && heading != null;
    _animate(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(p.lat, p.lng), zoom: widget.followZoom, bearing: up ? (heading ?? 0) : 0, tilt: up ? 35 : 0)));
  }

  void _fit() {
    if (widget.fitPoints.isEmpty || !mounted) return;
    _lastFitKey = widget.fitKey;
    final size = context.size ?? const Size(400, 800);
    final v = fitView(
      points: widget.fitPoints,
      widthPx: size.width - widget.padding.horizontal,
      heightPx: size.height - widget.padding.vertical,
    );
    _animate(CameraUpdate.newLatLngZoom(LatLng(v.lat, v.lng), v.zoom));
  }

  Future<void> _animate(CameraUpdate u) async {
    for (var i = 0; i < 3; i++) {
      try {
        await _map?.animateCamera(u);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  void _onCameraMove(CameraPosition p) {
    final next = styleForZoom(p.zoom, _style);
    if (next != _style && mounted) setState(() => _style = next);
  }

  void _settle() {
    if (!mounted) return;
    _lastCamera = DateTime.fromMillisecondsSinceEpoch(0);
    final p = widget.followPoint;
    if (widget.follow && p != null) {
      _follow(p);
    } else {
      _lastFitKey = '';
      _fit();
    }
  }

  List<LatLng> _ll(List<LatLngPoint> pts) => [for (final p in pts) LatLng(p.lat, p.lng)];

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !hasGoogleMapsRuntime()) {
      return const MapsUnavailableView(message: 'The Google Maps JavaScript API key is not configured for this browser. Positions and times still work.');
    }
    final markers = <Marker>{
      for (final m in widget.markers)
        Marker(
          markerId: MarkerId(m.id),
          position: LatLng(m.position.lat, m.position.lng),
          icon: _pins[m.kind] ?? NavPins.fallback(m.kind),
          anchor: const Offset(0.5, 0.5),
          flat: m.heading != null,
          rotation: m.heading ?? 0,
          zIndexInt: m.kind == 'unit' ? 6 : (m.kind == 'caller' ? 5 : 3),
          infoWindow: m.title == null ? InfoWindow.noText : InfoWindow(title: m.title, snippet: m.snippet),
        ),
    };
    final dotted = useDottedRoute(widget.remaining);
    final polylines = <Polyline>{
      if (widget.traveled.length >= 2)
        Polyline(
          polylineId: const PolylineId('traveled'),
          points: _ll(widget.traveled),
          color: const Color(0xFF9AA0A6),
          width: 6,
          zIndex: 1,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      if (dotted)
        Polyline(
          polylineId: const PolylineId('dots'),
          points: _ll(widget.remaining),
          color: const Color(0xFF1A73E8),
          width: 9,
          zIndex: 3,
          patterns: [PatternItem.dot, PatternItem.gap(10)],
          jointType: JointType.round,
        ),
      if (widget.remaining.length >= 2 && !dotted) ...[
        Polyline(
          polylineId: const PolylineId('casing'),
          points: _ll(widget.remaining),
          color: Colors.white,
          width: 11,
          zIndex: 2,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
        Polyline(
          polylineId: const PolylineId('remaining'),
          points: _ll(widget.remaining),
          color: const Color(0xFF1A73E8),
          width: 7,
          zIndex: 3,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      ],
    };
    final circles = <Circle>{
      for (final m in widget.markers)
        if (accuracyRadiusM(m.accuracyM) != null)
          Circle(
            circleId: CircleId('acc_${m.id}'),
            center: LatLng(m.position.lat, m.position.lng),
            radius: accuracyRadiusM(m.accuracyM)!,
            fillColor: NavPins.colorOf(m.kind).withValues(alpha: 0.13),
            strokeColor: NavPins.colorOf(m.kind).withValues(alpha: 0.35),
            strokeWidth: 1,
          ),
    };
    final first = widget.followPoint ?? (widget.fitPoints.isNotEmpty ? widget.fitPoints.first : (widget.markers.isNotEmpty ? widget.markers.first.position : null));
    final start = first == null ? const LatLng(-1.2921, 36.8219) : LatLng(first.lat, first.lng);
    return Stack(children: [
      Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => widget.onUserGesture?.call(),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: start, zoom: 15),
            style: _satellite ? null : (_style == NavMapStyle.detail ? kNavStyleDetail : kNavStyleOverview),
            mapType: _satellite ? MapType.hybrid : MapType.normal,
            markers: markers,
            polylines: polylines,
            circles: circles,
            minMaxZoomPreference: const MinMaxZoomPreference(10, 20),
            buildingsEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: false,
            padding: widget.padding,
            onCameraMove: _onCameraMove,
            onMapCreated: (c) {
              _map = c;
              _settle();
              Future<void>.delayed(const Duration(milliseconds: 600), _settle);
            },
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: widget.padding.bottom + 12,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.showRecenter && widget.onRecenter != null) ...[
            MapRoundButton(icon: widget.recenterIcon, onTap: widget.onRecenter!, tooltip: widget.recenterTooltip, active: true),
            const SizedBox(height: 10),
          ],
          MapRoundButton(
            icon: _satellite ? Icons.map_outlined : Icons.satellite_alt,
            tooltip: _satellite ? 'Map view' : 'Satellite view',
            onTap: () => setState(() => _satellite = !_satellite),
          ),
        ]),
      ),
    ]);
  }
}
