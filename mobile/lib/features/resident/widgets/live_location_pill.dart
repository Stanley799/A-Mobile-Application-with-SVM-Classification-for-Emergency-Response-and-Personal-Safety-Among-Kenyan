// "Live location" pill for the home screen. Finds the position BEFORE any emergency, shows the street name, and says plainly if it cannot.
// This is how a person verifies that the phone knows where they are. Tap to retry.
import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../map/help_repository.dart';
import '../map/location_resolver.dart';

class LiveLocationPill extends StatefulWidget {
  const LiveLocationPill({super.key, this.repo});
  final HelpRepository? repo;

  @override
  State<LiveLocationPill> createState() => _LiveLocationPillState();
}

enum _Loc { finding, found, failed }

class _LiveLocationPillState extends State<LiveLocationPill> {
  _Loc _s = _Loc.finding;
  String _text = 'Finding your location…';
  String? _sub;
  LocFail? _fail;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _s = _Loc.finding;
      _text = 'Finding your location…';
      _sub = null;
    });
    final r = await resolveLocation();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _s = _Loc.failed;
        _fail = r.fail;
        _text = locFailMessage(r.fail!);
        _sub = 'Tap to fix';
      });
      return;
    }
    final loc = r.location!;
    setState(() {
      _s = _Loc.found;
      _text = 'Location found';
      _sub = loc.accuracyMeters == null ? null : '±${loc.accuracyMeters!.round()} m';
    });
    final street = await (widget.repo ?? HelpRepository()).geocode(loc.latitude, loc.longitude);
    if (!mounted) return;
    setState(() => _text = street ?? '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}');
  }

  @override
  Widget build(BuildContext context) {
    final failed = _s == _Loc.failed;
    return Semantics(
      button: true,
      label: 'Your location: $_text',
      child: Material(
        color: failed ? Tk.warnTint : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tk.rPill), side: const BorderSide(color: Tk.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tk.rPill),
          onTap: _s == _Loc.finding ? null : (failed && _fail != null && _fail != LocFail.timeout && _fail != LocFail.unavailable ? () async { await openLocationHelp(_fail!); await _locate(); } : _locate),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_s == _Loc.finding) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: Tk.brand)) else Icon(failed ? Icons.location_off_outlined : Icons.my_location, size: 18, color: failed ? Tk.warnInk : Tk.you),
              const SizedBox(width: 8),
              Flexible(child: Text(_text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: failed ? Tk.warnInk : Tk.ink))),
              if (_sub != null) ...[const SizedBox(width: 8), Text(_sub!, style: TextStyle(fontSize: 12, color: failed ? Tk.warnInk : Tk.mute, fontWeight: FontWeight.w600))],
            ]),
          ),
        ),
      ),
    );
  }
}
