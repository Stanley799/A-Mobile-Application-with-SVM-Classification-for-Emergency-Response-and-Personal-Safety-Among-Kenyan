// Colours taken from the approved "Responder: incoming alert" design.
import 'package:flutter/material.dart';

class RC {
  static const bg = Color(0xFF0F1214);
  static const card = Color(0xFF171B1F);
  static const surface2 = Color(0xFF1F252B);
  static const line = Color(0xFF2A3138);
  static const outline = Color(0xFF76828D);
  static const text = Color(0xFFF3F5F7);
  static const muted = Color(0xFFA9B3BC);
  static const soft = Color(0xFFC9D1D6);
  static const alert = Color(0xFFFF6B5E);
  static const high = alert;
  static const accept = Color(0xFF2BD38F);
  static const danger = Color(0xFFC23B3B);
  static const accent = Color(0xFF34D3C0);
  static const medium = Color(0xFFFFB020);
  static const low = Color(0xFF5AB0FF);
  static const dangerChipBg = Color(0xFF3C2020);
  static const dangerChipFg = Color(0xFFFFB8B0);
  static const infoChipBg = surface2;
  static const infoChipFg = text;
  static const needBg = Color(0xFF15352F);
  static const needFg = Color(0xFF8FE8D8);

  static Color priority(String p) => switch (p) {
    'High' => high,
    'Medium' => medium,
    _ => low,
  };
}

class ResponderSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class ResponderRadius {
  static const chip = 12.0;
  static const card = 20.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

class ResponderTextStyles {
  static const title = TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: RC.text);
  static const section = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RC.text);
  static const body = TextStyle(fontSize: 15, color: RC.text, height: 1.4);
  static const caption = TextStyle(fontSize: 12.5, color: RC.muted, height: 1.35);
}

class Chip2 extends StatelessWidget {
  const Chip2(this.label, this.bg, this.fg, {super.key});
  final String label;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RC.muted, letterSpacing: 0.6));
}

class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onPressed, this.filled = true, this.color = RC.accept, this.height = 64});
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: filled
        ? FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            onPressed: onPressed,
            child: Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: RC.infoChipFg, side: const BorderSide(color: RC.outline), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: onPressed,
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
  );
}
