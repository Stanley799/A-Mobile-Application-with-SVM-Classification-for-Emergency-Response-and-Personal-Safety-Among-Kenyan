// Small shared pieces for the admin dashboard.
import 'package:flutter/material.dart';

class AC {
  static const bg = Color(0xFFF4F2EE);
  static const card = Colors.white;
  static const ink = Color(0xFF1A1A1A);
  static const mute = Color(0xFF5F5F5F);
  static const line = Color(0xFFE5E1DA);
  static const brand = Color(0xFF0F766E);
  static const high = Color(0xFFB33A3A);
  static const medium = Color(0xFFB26A00);
  static const low = Color(0xFF3A6EA5);

  static Color priority(String p) => switch (p) { 'High' => high, 'Medium' => medium, _ => low };

  static (Color, Color) stateColors(String s) => switch (s) {
    'unfilled' || 'no_location' => (const Color(0xFFFDE8E8), const Color(0xFF9B1C1C)),
    'needs_review' => (const Color(0xFFFFF3E0), const Color(0xFF9C3700)),
    'assigned' || 'enroute' || 'arrived' || 'completed' => (const Color(0xFFE8F5E9), const Color(0xFF1B5E20)),
    'cancelled' || 'support_only' => (const Color(0xFFEDEDED), const Color(0xFF444444)),
    _ => (const Color(0xFFE3F2FD), const Color(0xFF0D47A1)),
  };
}

String stateLabel(String s) => switch (s) {
  'none' => 'Not started',
  'awaiting_details' => 'Waiting for details',
  'waiting_location' => 'Waiting for GPS',
  'dispatching' => 'Asking responders',
  'partially_assigned' => 'Partly assigned',
  'assigned' => 'Assigned',
  'enroute' => 'On the way',
  'arrived' => 'Arrived',
  'completed' => 'Completed',
  'unfilled' => 'NO RESPONDER',
  'no_location' => 'NO LOCATION',
  'support_only' => 'Support only',
  'needs_review' => 'Needs review',
  'cancelled' => 'Cancelled',
  _ => s,
};

String ago(DateTime? t, [DateTime? now]) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds < 0 ? 0 : d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String clock(DateTime? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

class Pill extends StatelessWidget {
  const Pill(this.text, this.bg, this.fg, {super.key});
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
  );
}

class PriorityPill extends StatelessWidget {
  const PriorityPill(this.priority, {super.key});
  final String priority;
  @override
  Widget build(BuildContext context) => Pill(priority.toUpperCase(), AC.priority(priority), Colors.white);
}

class StatePill extends StatelessWidget {
  const StatePill(this.state, {super.key});
  final String state;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = AC.stateColors(state);
    return Pill(stateLabel(state), bg, fg);
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: AC.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AC.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AC.ink))), if (trailing != null) trailing!]),
      const SizedBox(height: 12),
      child,
    ]),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.hint, this.alert = false});
  final String label;
  final String value;
  final String? hint;
  final bool alert;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: alert ? const Color(0xFFFDE8E8) : AC.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: alert ? const Color(0xFFF2C4C4) : AC.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AC.mute)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1, color: alert ? const Color(0xFF9B1C1C) : AC.ink)),
      if (hint != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(hint!, style: const TextStyle(fontSize: 12, color: AC.mute))),
    ]),
  );
}

/// A horizontal bar row: label, a bar scaled to [max], and the number.
class BarRow extends StatelessWidget {
  const BarRow({super.key, required this.label, required this.value, required this.max, this.color = AC.brand});
  final String label;
  final int value;
  final int max;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AC.ink))),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final w = max == 0 ? 0.0 : c.maxWidth * (value / max);
          return Stack(children: [
            Container(height: 12, decoration: BoxDecoration(color: AC.line, borderRadius: BorderRadius.circular(6))),
            Container(height: 12, width: w, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
          ]);
        }),
      ),
      SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AC.ink))),
    ]),
  );
}
