// Design tokens. Every text/background pair below was checked with WCAG 2 contrast and APCA (see Phase 4 design document).
// Rule of thumb: body text >= 4.5:1, large text and icons >= 3:1. Change a colour only after re-checking it.
import 'package:flutter/material.dart';

class Tk {
  Tk._();
  // text
  static const ink = Color(0xFF111111); // 18.9:1 on white
  static const mute = Color(0xFF4A4A4A); // 7.9:1 on the page background, >= 5.5:1 on glass
  static const faint = Color(0xFF6B6B6B); // 5.3:1 on white: captions only
  // surfaces
  static const bg = Color(0xFFF4F2EE);
  static const card = Colors.white;
  static const line = Color(0xFFE5E1DA);
  // brand and status
  static const brand = Color(0xFF0F766E); // white text 5.47:1
  static const brandDeep = Color(0xFF0B5F58); // brand-coloured text: 7.5:1 on white, >= 4.7:1 on glass
  static const brandTint = Color(0xFFE0F2F1);
  static const danger = Color(0xFFB33A3A); // white text 5.86:1
  static const dangerTint = Color(0xFFFFF4F4);
  static const warnInk = Color(0xFF9C3700); // on warnTint 6.5:1
  static const warnTint = Color(0xFFFFF3E0);
  static const okInk = Color(0xFF1B5E20);
  static const okTint = Color(0xFFE8F5E9);
  static const you = Color(0xFF1A73E8);
  // place kinds: white icon/text on each is >= 4.5:1
  static const hospital = Color(0xFFC62828);
  static const clinic = Color(0xFFC2185B);
  static const ambulance = Color(0xFF2E7D32);
  static const police = Color(0xFF1565C0);
  static const fire = Color(0xFFBF360C);
  static const helpline = Color(0xFF6A1B9A);
  static const live = Color(0xFF00695C);

  // shape and motion
  static const rCard = 20.0;
  static const rSheet = 28.0;
  static const rPill = 999.0;
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 320);
  static const spring = Curves.easeOutBack; // gentle overshoot, never linear
  static const settle = Curves.easeOutCubic;
}
