// "Glass" for FLOATING CONTROLS over a map or photo only (top bar, chips, small round buttons). Never for body content, never glass over glass.
// Why: Apple's own guidance keeps glass in the control layer and uses standard solid materials for content, because text on translucent
// layers loses contrast. Here the tint is 86% white, which keeps ink text >= 11:1 and secondary text >= 5.5:1 over the worst map colours
// (verified, see design document). With "high contrast" or "reduce transparency" accessibility on, it turns fully solid.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'tokens.dart';

class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 22, this.padding, this.tint, this.alpha = 0.86, this.blur = 18, this.elevated = true});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint; // defaults to white
  final double alpha;
  final double blur;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final solid = mq?.highContrast ?? false;
    final base = tint ?? Colors.white;
    final shape = BorderRadius.circular(radius);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: shape,
        color: solid ? base : base.withValues(alpha: alpha),
        border: Border.all(color: Colors.white.withValues(alpha: solid ? 1 : 0.65), width: 1),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: elevated ? const [BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6))] : null),
      child: ClipRRect(borderRadius: shape, child: solid ? body : BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: body)),
    );
  }
}

/// Round glass icon button (back, move pin, hide).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 24,
    child: SizedBox(width: 46, height: 46, child: IconButton(tooltip: tooltip, icon: Icon(icon, color: Tk.ink, size: 20), onPressed: onPressed)),
  );
}

/// Small pulsing dot: "we are working on it". Calm, not flashy.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.color = Tk.brand, this.size = 12});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size * 2.4,
    height: widget.size * 2.4,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Stack(alignment: Alignment.center, children: [
        Container(width: widget.size * (1 + 1.4 * _c.value), height: widget.size * (1 + 1.4 * _c.value), decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)))),
        Container(width: widget.size, height: widget.size, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
      ]),
    ),
  );
}
