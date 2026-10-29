// Colours taken from the approved "Responder: incoming alert" design.
import 'package:flutter/material.dart';

class RC {
  static const bg = Color(0xFF14181B);
  static const card = Color(0xFF1F262B);
  static const line = Color(0xFF3A444B);
  static const outline = Color(0xFF4A565E);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFA9B1B7);
  static const soft = Color(0xFFC9D1D6);
  static const alert = Color(0xFFB33A3A);
  static const accept = Color(0xFF2E7D32);
  static const dangerChipBg = Color(0xFF5A2A2A);
  static const dangerChipFg = Color(0xFFFFD9D9);
  static const infoChipBg = Color(0xFF2A333A);
  static const infoChipFg = Color(0xFFE3E8EB);
  static const needBg = Color(0xFF1D3B36);
  static const needFg = Color(0xFFBFEDE6);

  static Color priority(String p) => switch (p) {
    'High' => const Color(0xFFB33A3A),
    'Medium' => const Color(0xFFB26A00),
    _ => const Color(0xFF3A6EA5),
  };
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
