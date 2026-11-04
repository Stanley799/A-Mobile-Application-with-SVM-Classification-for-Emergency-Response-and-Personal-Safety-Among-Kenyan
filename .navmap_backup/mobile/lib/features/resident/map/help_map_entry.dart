// A card for the "Help is being sent" screen that opens the map. Shows a one-line live summary and never errors.
import 'package:flutter/material.dart';

import 'help_map_screen.dart';
import 'help_models.dart';
import 'help_repository.dart';

class HelpMapEntry extends StatelessWidget {
  const HelpMapEntry({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HelpState>(
      stream: HelpRepository().watchOptions(incidentId),
      builder: (context, snap) {
        final s = snap.data;
        final n = s?.options.length ?? 0;
        final live = s?.options.where((o) => o.isLive).length ?? 0;
        final best = s?.options.map((o) => o.etaMin).whereType<double>().fold<double?>(null, (a, b) => a == null || b < a ? b : a);
        final line = s == null || !s.loaded
            ? 'Opening the map…'
            : n == 0
                ? 'See emergency numbers and nearby help'
                : '$n option${n == 1 ? '' : 's'}${live > 0 ? ' · $live live' : ''}${best != null ? ' · nearest about ${best.round().clamp(1, 999)} min' : ''}';
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HelpMapScreen(incidentId: incidentId))),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF0F766E), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const Icon(Icons.map_outlined, color: Colors.white, size: 30),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('See help on the map', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(line, style: const TextStyle(color: Color(0xFFD7F0EC), fontSize: 13)),
              ])),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        );
      },
    );
  }
}
