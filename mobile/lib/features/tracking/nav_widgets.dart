// Small, calm pieces for the navigation screens: the turn banner, the ETA card, round map buttons and the freshness chip.
import 'package:flutter/material.dart';

import '../../core/ui/tokens.dart';

/// "In 120 m · Turn left onto Waiyaki Way", big enough to read at a glance in a moving vehicle.
class TurnBanner extends StatelessWidget {
  const TurnBanner({super.key, required this.icon, required this.distance, required this.text});

  final IconData icon;
  final String distance;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tk.brandDeep,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(distance, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 2),
              Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD7F0EC), fontSize: 14.5, height: 1.25)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The card at the bottom: the big ETA, one detail line, an optional note, and the action buttons.
class NavBottomCard extends StatelessWidget {
  const NavBottomCard({super.key, required this.title, required this.subtitle, this.note, this.badge, this.actions = const <Widget>[]});

  final String title;
  final String subtitle;
  final String? note;
  final Widget? badge;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Tk.ink, height: 1.1))),
            if (badge != null) badge!,
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.mute)),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: const TextStyle(fontSize: 12.5, color: Tk.faint, height: 1.3)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: actions[i]),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

/// A round white map button (satellite, recenter, back).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({super.key, required this.icon, required this.onTap, required this.tooltip, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Tk.brand : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 22, color: active ? Colors.white : Tk.ink),
        onPressed: onTap,
      ),
    );
  }
}

/// The small pill that says "Live", "Last seen 3 min ago", and so on.
class FreshChip extends StatelessWidget {
  const FreshChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}
