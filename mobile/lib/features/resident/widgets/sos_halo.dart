// Calm breathing rings behind the SOS button: "this is ready". Wrap the existing SOS button with it. Off when the device asks to reduce motion.
import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';

class SosHalo extends StatefulWidget {
  const SosHalo({super.key, required this.child, this.size = 250, this.color = Tk.danger});
  final Widget child;
  final double size; // diameter of the button being wrapped
  final Color color;

  @override
  State<SosHalo> createState() => _SosHaloState();
}

class _SosHaloState extends State<SosHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return widget.child;
    final box = widget.size * 1.5;
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Stack(alignment: Alignment.center, children: [
          for (final phase in const [0.0, 0.5])
            Builder(builder: (_) {
              final t = (_c.value + phase) % 1.0;
              final d = widget.size * (1 + 0.45 * t);
              return Container(width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color.withValues(alpha: 0.28 * (1 - t)), width: 2)));
            }),
          child!,
        ]),
        child: widget.child,
      ),
    );
  }
}
