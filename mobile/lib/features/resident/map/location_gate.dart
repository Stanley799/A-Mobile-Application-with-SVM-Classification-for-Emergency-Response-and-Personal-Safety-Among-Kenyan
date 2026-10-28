// Shown BEFORE the map when the alert has no location yet: finds the resident, explains any problem in plain words, and always offers
// "Place me on the map" and the emergency numbers. Calls onResolved exactly once with a position.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'location_resolver.dart';
import 'map_style.dart';
import 'maps_available.dart';

const _ink = Color(0xFF1A1A1A);
const _mute = Color(0xFF5F5F5F);
const _brand = Color(0xFF0F766E);
const _danger = Color(0xFFB33A3A);

class LocationGate extends StatefulWidget {
  const LocationGate({super.key, required this.onResolved, this.fallbackCenter = const LatLng(-1.2921, 36.8219)});
  final void Function(ResolvedLocation) onResolved;
  final LatLng fallbackCenter;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate> {
  bool _working = true;
  LocFail? _fail;

  @override
  void initState() {
    super.initState();
    _try();
  }

  Future<void> _try() async {
    setState(() {
      _working = true;
      _fail = null;
    });
    final r = await resolveLocation();
    if (!mounted) return;
    if (r.ok) {
      widget.onResolved(r.location!);
    } else {
      setState(() {
        _working = false;
        _fail = r.fail;
      });
    }
  }

  Future<void> _manual() async {
    final picked = await Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => ManualPinPage(start: widget.fallbackCenter)));
    if (picked != null && mounted) widget.onResolved(ResolvedLocation(latitude: picked.latitude, longitude: picked.longitude, source: 'manual'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F2EE),
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: _ink, elevation: 0, title: const Text('Finding you', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Center(child: Container(width: 96, height: 96, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE0F2F1)), child: Icon(_working ? Icons.my_location : Icons.location_off_outlined, size: 44, color: _working ? _brand : _danger))),
          const SizedBox(height: 24),
          Text(_working ? 'Finding your location…' : locFailMessage(_fail!), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 10),
          Text(_working ? 'This takes a few seconds. If your browser or phone asks, choose Allow.' : locFailHelp(_fail!), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: _mute, height: 1.45)),
          const SizedBox(height: 28),
          if (_working) const Center(child: CircularProgressIndicator()),
          if (!_working) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _brand, minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () async {
                if (!kIsWeb && (_fail == LocFail.serviceOff || _fail == LocFail.deniedForever)) await openLocationHelp(_fail!);
                await _try();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: _manual,
              icon: const Icon(Icons.push_pin_outlined),
              label: const Text('Place me on the map', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
          const SizedBox(height: 28),
          const Text('Need help right now? Call:', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _mute)),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final n in const ['999', '112', '1199', '922'])
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _danger, minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: n)),
                icon: const Icon(Icons.call, size: 18),
                label: Text(n),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Drag the map so the pin is where you are. Returns the chosen point.
class ManualPinPage extends StatefulWidget {
  const ManualPinPage({super.key, required this.start});
  final LatLng start;

  @override
  State<ManualPinPage> createState() => _ManualPinPageState();
}

class _ManualPinPageState extends State<ManualPinPage> {
  late LatLng _center = widget.start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: _ink, elevation: 0, title: const Text('Where are you?', style: TextStyle(fontWeight: FontWeight.w800))),
      body: hasGoogleMapsRuntime()
          ? Stack(children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: widget.start, zoom: 15),
                style: kEmergencyMapStyle,
                onCameraMove: (p) => _center = p.target,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                mapToolbarEnabled: false,
              ),
              const IgnorePointer(child: Center(child: Padding(padding: EdgeInsets.only(bottom: 36), child: Icon(Icons.location_pin, size: 48, color: _danger)))),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: const Text('Move the map until the red pin is exactly where you are.', style: TextStyle(fontSize: 14, color: _ink))),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _brand, minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () => Navigator.of(context).pop(_center),
                    child: const Text('Use this location', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ])
          : MapsUnavailableView(
              title: 'Map unavailable',
              message: 'The browser cannot load Google Maps because the Maps API key is missing. You can still continue by selecting a rough location manually.',
              primaryAction: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brand, minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.of(context).pop(widget.start),
                child: const Text('Use a fallback location'),
              ),
            ),
    );
  }
}
