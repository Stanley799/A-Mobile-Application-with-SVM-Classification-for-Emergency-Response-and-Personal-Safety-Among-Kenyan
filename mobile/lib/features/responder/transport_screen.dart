// Transport leg: pick a listed hospital or clinic, then drive there with the route drawn inside the app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import '../resident/map/help_models.dart' show RouteInfo, haversineKm;
import '../resident/map/help_repository.dart';
import '../resident/map/map_style.dart';
import 'incoming_alert_screen.dart' show openInMaps;
import 'responder_theme.dart';
import 'transport_models.dart';

/// Destination picker. Returns the chosen facility, or null when dismissed.
Future<TransportDestination?> showTransportPicker(
  BuildContext context, {
  required Future<List<TransportDestination>> Function() load,
}) => showModalBottomSheet<TransportDestination>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => _TransportPicker(load: load),
);

class _TransportPicker extends StatefulWidget {
  const _TransportPicker({required this.load});
  final Future<List<TransportDestination>> Function() load;

  @override
  State<_TransportPicker> createState() => _TransportPickerState();
}

class _TransportPickerState extends State<_TransportPicker> {
  late final Future<List<TransportDestination>> _future = widget.load();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              'Where are you taking them?',
              style: ResponderTextStyles.title,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Nearest hospitals and clinics first.',
              style: ResponderTextStyles.caption,
            ),
          ),
          Flexible(
            child: FutureBuilder<List<TransportDestination>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final list = snap.data ?? const <TransportDestination>[];
                if (snap.hasError || list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Text(
                      'No hospital or clinic is listed near this scene. Take the patient to the nearest facility you know.',
                      style: ResponderTextStyles.body,
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _DestinationTile(place: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.place});
  final TransportDestination place;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).pop(place),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(
        children: [
          const Icon(Icons.local_hospital_outlined, color: RC.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: RC.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    place.typeLabel,
                    if (place.distanceKm != null)
                      '${place.distanceKm!.toStringAsFixed(1)} km',
                    if (place.is24h == true) 'Open 24 hours',
                    if (!place.verified) 'Phone not verified',
                  ].join(' · '),
                  style: ResponderTextStyles.caption,
                ),
              ],
            ),
          ),
          if (place.phone.isNotEmpty)
            IconButton(
              tooltip: 'Call ${place.name}',
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: place.phone)),
              icon: const Icon(Icons.call_outlined, color: RC.accept),
            ),
          const Icon(Icons.chevron_right, color: RC.muted),
        ],
      ),
    ),
  );
}

/// The in-app route to the chosen facility, with the drive visible under the map.
class TransportMapScreen extends StatefulWidget {
  const TransportMapScreen({
    super.key,
    required this.offer,
    required this.destination,
  });
  final Offer offer;
  final TransportDestination destination;

  @override
  State<TransportMapScreen> createState() => _TransportMapScreenState();
}

class _TransportMapScreenState extends State<TransportMapScreen> {
  final _help = HelpRepository();
  LatLng? _me;
  RouteInfo? _route;
  bool _loadingRoute = true;

  LatLng get _hospital =>
      LatLng(widget.destination.latitude!, widget.destination.longitude!);

  @override
  void initState() {
    super.initState();
    unawaited(_locate());
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() => _me = LatLng(pos.latitude, pos.longitude));
      unawaited(_loadRoute());
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _loadRoute() async {
    final me = _me;
    if (me == null) return;
    final route = await _help.directions(
      me.latitude,
      me.longitude,
      _hospital.latitude,
      _hospital.longitude,
    );
    if (mounted) {
      setState(() {
        _route = route;
        _loadingRoute = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final km = me == null
        ? null
        : haversineKm(
            me.latitude,
            me.longitude,
            _hospital.latitude,
            _hospital.longitude,
          );
    return Scaffold(
      backgroundColor: RC.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.destination.hasPosition
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _hospital,
                      zoom: 13.5,
                    ),
                    style: kEmergencyMapStyle,
                    markers: {
                      Marker(
                        markerId: const MarkerId('hospital'),
                        position: _hospital,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                        infoWindow: InfoWindow(
                          title: widget.destination.name,
                        ),
                      ),
                      if (me != null)
                        Marker(
                          markerId: const MarkerId('me'),
                          position: me,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure,
                          ),
                          infoWindow: const InfoWindow(title: 'Your unit'),
                        ),
                    },
                    polylines: {
                      if (_route != null && _route!.points.length > 1)
                        Polyline(
                          polylineId: const PolylineId('transport'),
                          points: [
                            for (final p in _route!.points)
                              LatLng(p.lat, p.lng),
                          ],
                          color: RC.accent,
                          width: 6,
                          startCap: Cap.roundCap,
                          endCap: Cap.roundCap,
                          jointType: JointType.round,
                        ),
                    },
                    onMapCreated: (_) {},
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    padding: const EdgeInsets.only(top: 90, bottom: 190),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'This facility has no map position. Use Google Maps to find it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: RC.soft),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        'Transporting to ${widget.destination.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: RC.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _loadingRoute
                          ? 'Finding the route…'
                          : _route == null || _route!.points.isEmpty
                          ? (km == null
                                ? 'Route unavailable'
                                : '${km.toStringAsFixed(1)} km away')
                          : '${((_route!.distanceMeters) / 1000).toStringAsFixed(1)} km · ${(_route!.etaSeconds / 60).round().clamp(1, 999)} min',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: RC.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.destination.address.isNotEmpty
                          ? widget.destination.address
                          : widget.destination.typeLabel,
                      style: const TextStyle(fontSize: 13, color: RC.soft),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (widget.destination.phone.isNotEmpty) ...[
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: RC.accept,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () => launchUrl(
                                  Uri(
                                    scheme: 'tel',
                                    path: widget.destination.phone,
                                  ),
                                ),
                                icon: const Icon(Icons.call, size: 18),
                                label: const Text(
                                  'Call facility',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => openInMaps(
                                widget.destination.latitude,
                                widget.destination.longitude,
                              ),
                              icon: const Icon(
                                Icons.navigation_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'Open in Maps',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
