// Draws round map pins (coloured disc + white icon) once and caches them. If anything fails (for example the icon font did not load)
// the caller gets null and uses the standard coloured marker instead, so the map never breaks.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'emergency_layers.dart';

class PinStyle {
  const PinStyle(this.color, this.icon, this.hue);
  final Color color;
  final IconData icon;
  final double hue;
}

const Map<String, PinStyle> kPinStyles = {
  'hospital': PinStyle(Color(0xFFC62828), Icons.local_hospital, BitmapDescriptor.hueRed),
  'clinic': PinStyle(Color(0xFFC2185B), Icons.medical_services, BitmapDescriptor.hueRose),
  'ambulance': PinStyle(Color(0xFF2E7D32), Icons.emergency, BitmapDescriptor.hueGreen),
  'police': PinStyle(Color(0xFF1565C0), Icons.local_police, BitmapDescriptor.hueAzure),
  'fire': PinStyle(Color(0xFFBF360C), Icons.local_fire_department, BitmapDescriptor.hueOrange),
  'helpline': PinStyle(Color(0xFF6A1B9A), Icons.support_agent, BitmapDescriptor.hueViolet),
  'live': PinStyle(Color(0xFF00695C), Icons.directions_car, BitmapDescriptor.hueGreen),
  'me': PinStyle(Color(0xFF1A73E8), Icons.circle, BitmapDescriptor.hueBlue),
};

String pinKeyFor(PlaceType t) => t.name;

class PinFactory {
  static final Map<String, BitmapDescriptor> _cache = {};

  /// Returns a custom pin or null (use [fallback] instead).
  static Future<BitmapDescriptor?> pin(String key, {bool big = false}) async {
    final id = big ? '$key!' : key;
    final hit = _cache[id];
    if (hit != null) return hit;
    final style = kPinStyles[key];
    if (style == null) return null;
    try {
      final logical = big ? 54.0 : 40.0;
      const scale = 2.0;
      final size = logical * scale;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final center = Offset(size / 2, size / 2);
      c.drawCircle(center + const Offset(0, 2), size / 2 - 3, Paint()..color = const Color(0x33000000));
      c.drawCircle(center, size / 2 - 3, Paint()..color = Colors.white);
      c.drawCircle(center, size / 2 - 8, Paint()..color = style.color);
      if (key != 'me') {
        final tp = TextPainter(
          text: TextSpan(text: String.fromCharCode(style.icon.codePoint), style: TextStyle(fontSize: size * 0.48, fontFamily: style.icon.fontFamily, package: style.icon.fontPackage, color: Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
      }
      final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final bytes = Uint8List.view(data.buffer);
      final d = BitmapDescriptor.bytes(bytes, width: logical, height: logical);
      _cache[id] = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  static BitmapDescriptor fallback(String key) => BitmapDescriptor.defaultMarkerWithHue((kPinStyles[key] ?? kPinStyles['hospital']!).hue);
}
