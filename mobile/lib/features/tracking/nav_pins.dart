// Round map pins for the navigation map, drawn once and cached. If anything fails (for example the icon font did not load)
// the caller gets null and uses [fallback], so the map never breaks. The unit's arrow points up and the marker is rotated to the heading.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class NavPins {
  NavPins._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static const Map<String, (Color, IconData)> _styles = {
    'unit': (Color(0xFF0F766E), Icons.navigation),
    'caller': (Color(0xFF1A73E8), Icons.person),
    'dest': (Color(0xFFB33A3A), Icons.flag),
  };

  static Color colorOf(String kind) => _styles[kind]?.$1 ?? const Color(0xFF1A73E8);

  static Future<BitmapDescriptor?> pin(String kind) async {
    final hit = _cache[kind];
    if (hit != null) return hit;
    final style = _styles[kind];
    if (style == null) return null;
    try {
      const logical = 44.0;
      const scale = 2.0;
      const size = logical * scale;
      const center = Offset(size / 2, size / 2);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawCircle(center + const Offset(0, 2), size / 2 - 3, Paint()..color = const Color(0x33000000));
      c.drawCircle(center, size / 2 - 3, Paint()..color = Colors.white);
      c.drawCircle(center, size / 2 - 9, Paint()..color = style.$1);
      final icon = style.$2;
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontSize: size * 0.46, fontFamily: icon.fontFamily, package: icon.fontPackage, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
      final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final d = BitmapDescriptor.bytes(Uint8List.view(data.buffer), width: logical, height: logical);
      _cache[kind] = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  static BitmapDescriptor fallback(String kind) => BitmapDescriptor.defaultMarkerWithHue(switch (kind) {
        'unit' => BitmapDescriptor.hueGreen,
        'dest' => BitmapDescriptor.hueRed,
        _ => BitmapDescriptor.hueAzure,
      });
}
