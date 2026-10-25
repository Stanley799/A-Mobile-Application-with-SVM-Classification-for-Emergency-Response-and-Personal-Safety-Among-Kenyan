import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'admin_stats.dart';
import 'admin_widgets.dart';

class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key, required this.incidents, required this.offers, required this.responders, required this.onOpen, required this.goTo});
  final List<IncidentRecord> incidents;
  final List<Offer> offers;
  final List<ResponderRecord> responders;
  final void Function(IncidentRecord) onOpen;
  final void Function(int) goTo;

  @override
  Widget build(BuildContext context) {
    final s = AdminStats.compute(incidents, offers, responders, DateTime.now());
    final maxCat = s.byCategory.values.fold<int>(0, (a, b) => a > b ? a : b);
    final maxPri = s.byPriority.values.fold<int>(0, (a, b) => a > b ? a : b);
    final avg = s.avgFirstAcceptSeconds;
    return ListView(padding: const EdgeInsets.all(20), children: [
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : 2;
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        Widget t(Widget x) => SizedBox(width: w, child: x);
        return Wrap(spacing: 12, runSpacing: 12, children: [
          t(StatTile(label: 'OPEN ALERTS', value: '${s.open.length}', hint: 'being handled now')),
          t(StatTile(label: 'NEED ATTENTION', value: '${s.attention.length}', hint: 'no responder, no GPS or review', alert: s.attention.isNotEmpty)),
          t(StatTile(label: 'ALERTS TODAY', value: '${s.today}')),
          t(StatTile(label: 'RESPONDERS READY', value: '${s.available}', hint: '${s.busy} busy · ${s.verified} verified')),
          t(StatTile(label: 'AVG TIME TO FIRST ACCEPT', value: avg == null ? '-' : '${avg.round()} s', hint: 'from first offer to first yes')),
          t(StatTile(label: 'AWAITING VERIFICATION', value: '${s.pendingVerification}', hint: 'responder accounts')),
        ]);
      }),
      const SizedBox(height: 16),
      Panel(
        title: 'Needs attention now',
        trailing: TextButton(onPressed: () => goTo(1), child: const Text('All incidents')),
        child: s.attention.isEmpty
            ? const Text('Nothing needs attention. Every open alert has a responder or is being handled.', style: TextStyle(color: AC.mute))
            : Column(children: [for (final i in s.attention) _row(i)]),
      ),
      LayoutBuilder(builder: (context, c) {
        final two = c.maxWidth >= 800;
        final byCat = Panel(
          title: 'Alerts today by category',
          child: s.byCategory.isEmpty ? const Text('No alerts today.', style: TextStyle(color: AC.mute)) : Column(children: [for (final e in (s.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) BarRow(label: e.key, value: e.value, max: maxCat)]),
        );
        final byPri = Panel(
          title: 'Alerts today by priority',
          child: s.byPriority.isEmpty ? const Text('No alerts today.', style: TextStyle(color: AC.mute)) : Column(children: [for (final p in const ['High', 'Medium', 'Low']) if (s.byPriority[p] != null) BarRow(label: p, value: s.byPriority[p]!, max: maxPri, color: AC.priority(p))]),
        );
        return two ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: byCat), const SizedBox(width: 16), Expanded(child: byPri)]) : Column(children: [byCat, byPri]);
      }),
      const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Text('Priorities shown are the ones decided by the server. Distances are straight-line estimates. Figures use the latest 200 alerts.', style: TextStyle(fontSize: 12, color: AC.mute)),
      ),
    ]);
  }

  Widget _row(IncidentRecord i) => InkWell(
    onTap: () => onOpen(i),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        PriorityPill(i.priority),
        const SizedBox(width: 10),
        Expanded(child: Text('${i.category}${i.subtype == null ? '' : ' · ${i.subtype!.replaceAll('_', ' ')}'}', style: const TextStyle(fontWeight: FontWeight.w700, color: AC.ink))),
        StatePill(i.dispatchState),
        const SizedBox(width: 10),
        Text(ago(i.createdAt), style: const TextStyle(fontSize: 12, color: AC.mute)),
      ]),
    ),
  );
}
