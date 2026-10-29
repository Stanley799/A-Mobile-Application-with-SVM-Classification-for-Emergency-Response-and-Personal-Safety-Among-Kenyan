// Analytics (administrators only): the latest 500 closed incidents with metrics. No chart package:
// simple bars, and every figure carries the number of records it was computed from.
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'ops_logic.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsAnalytics extends StatefulWidget {
  const OpsAnalytics({super.key, required this.repo, required this.incidents, required this.offers});
  final OpsRepository repo;
  final List<IncidentRecord> incidents;
  final List<Offer> offers;

  @override
  State<OpsAnalytics> createState() => _OpsAnalyticsState();
}

class _OpsAnalyticsState extends State<OpsAnalytics> {
  late Future<List<IncidentRecord>> _closed = widget.repo.closedIncidents();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<IncidentRecord>>(
      future: _closed,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const OpsSkeleton(rows: 8);
        if (s.hasError) {
          return ErrorState(
            message: 'Could not load closed incidents: ${s.error}',
            onRetry: () => setState(() => _closed = widget.repo.closedIncidents()),
          );
        }
        final list = s.data ?? const <IncidentRecord>[];
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.insights_outlined, title: 'No closed incidents yet', message: 'Figures appear after the first incident is resolved or cancelled.');
        }
        return ListView(padding: const EdgeInsets.fromLTRB(OT.pad, 8, OT.pad, 24), children: [
          OpsSectionHeader(
            'Analytics',
            subtitle: 'Up to the latest 500 closed incidents with metrics. Decline reasons come from the latest 500 offers on this device.',
            trailing: IconButton(tooltip: 'Refresh', onPressed: () => setState(() => _closed = widget.repo.closedIncidents()), icon: const Icon(Icons.refresh, size: 19)),
          ),
          const SizedBox(height: 6),
          _panel('Response times', _responseTimes(list)),
          const SizedBox(height: 10),
          _panel('Outcomes', _outcomes(list)),
          const SizedBox(height: 10),
          _panel('Decline reasons', _declines()),
          const SizedBox(height: 10),
          _panel('By category', _categories(list)),
          const SizedBox(height: 10),
          _panel('Incidents per day, last 14 days', _days(list)),
          const SizedBox(height: 10),
          const Text(
            'Times use the metrics the server writes once when an incident closes. A step that never happened is left out of its median and its sample is smaller. Figures never mix a guess into a missing value.',
            style: TextStyle(fontSize: 11.5, color: OT.muted, height: 1.4),
          ),
        ]);
      },
    );
  }

  Widget _panel(String title, Widget child) => OpsPanel(title: title, child: child);

  Widget _row(String label, SampleStats s) {
    final v = s.median == null ? 'No data' : '${_duration(s.median!)} · p90 ${_duration(s.p90!)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 190, child: Text(label, style: const TextStyle(fontSize: 12.5, color: OT.soft))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: OT.text))),
        Text('n = ${s.sample}', style: const TextStyle(fontSize: 11.5, color: OT.muted, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _responseTimes(List<IncidentRecord> list) {
    final a = sampleStats([for (final i in list) i.metrics?.secondsToFirstOffer]);
    final b = sampleStats([for (final i in list) i.metrics?.secondsToFirstAccept]);
    final c = sampleStats([for (final i in list) i.metrics?.secondsToFirstArrival]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _row('First offer', a),
      _row('First accept', b),
      _row('First arrival', c),
      const SizedBox(height: 4),
      const Text('Median and 90th percentile of the seconds from the alert being created.', style: TextStyle(fontSize: 11, color: OT.muted)),
    ]);
  }

  Widget _outcomes(List<IncidentRecord> list) {
    final total = list.length;
    final cancelled = list.where((i) => i.status == 'Cancelled').length;
    final unfilled = list.where((i) => i.dispatchState != 'support_only' && !i.units.any((u) => kHeldStatuses.contains(u.status))).length;
    final closed = total - cancelled;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _pct('Cancellation rate', cancelled, total),
      _pct('No unit ever accepted', unfilled, total),
      _pct('Resolved', closed, total),
      const SizedBox(height: 4),
      const Text('“No unit ever accepted” counts closed incidents where no unit reached accepted, on the way, arrived or done. Support-only alerts are excluded from that count and still appear in the total.', style: TextStyle(fontSize: 11, color: OT.muted, height: 1.4)),
    ]);
  }

  Widget _pct(String label, int part, int total) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 190, child: Text(label, style: const TextStyle(fontSize: 12.5, color: OT.soft))),
      Expanded(child: Text(total == 0 ? '-' : '${(part * 100 / total).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: OT.text))),
      Text('$part of $total', style: const TextStyle(fontSize: 11.5, color: OT.muted, fontFeatures: [FontFeature.tabularFigures()])),
    ]),
  );

  Widget _declines() {
    final declined = [for (final o in widget.offers) if (o.status == 'declined') o];
    if (declined.isEmpty) return const Text('No declined offer in the latest 500 offers on this device.', style: TextStyle(fontSize: 12.5, color: OT.muted));
    final by = <String, int>{};
    for (final o in declined) {
      final r = o.withdrawReason?.trim() ?? '';
      final key = r.isEmpty ? 'Not given' : r;
      by[key] = (by[key] ?? 0) + 1;
    }
    final max = by.values.fold<int>(0, (a, b) => a > b ? a : b);
    final entries = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final e in entries) OpsBarRow(label: e.key, value: e.value, max: max, color: OT.priority('Medium')),
      const SizedBox(height: 4),
      Text('${declined.length} declined offer${declined.length == 1 ? '' : 's'}. Declines carry a reason only when one was written; otherwise they show as “Not given”.', style: const TextStyle(fontSize: 11, color: OT.muted, height: 1.4)),
    ]);
  }

  Widget _categories(List<IncidentRecord> list) {
    final by = <String, int>{};
    for (final i in list) {
      by[i.category] = (by[i.category] ?? 0) + 1;
    }
    final max = by.values.fold<int>(0, (a, b) => a > b ? a : b);
    final entries = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final e in entries) OpsBarRow(label: e.key, value: e.value, max: max),
      const SizedBox(height: 4),
      Text('Sample: ${list.length} closed incidents.', style: const TextStyle(fontSize: 11, color: OT.muted)),
    ]);
  }

  Widget _days(List<IncidentRecord> list) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 13));
    final counts = List<int>.filled(14, 0);
    for (final i in list) {
      final t = i.createdAt;
      if (t == null) continue;
      final d = DateTime(t.year, t.month, t.day);
      final k = d.difference(start).inDays;
      if (k >= 0 && k < 14) counts[k]++;
    }
    final total = counts.fold<int>(0, (a, b) => a + b);
    final max = counts.fold<int>(0, (a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (total == 0)
        const Text('No closed incident in the last 14 days.', style: TextStyle(fontSize: 12.5, color: OT.muted))
      else
        for (var k = 0; k < 14; k++)
          OpsBarRow(
            label: _dayLabel(start.add(Duration(days: k)), now),
            value: counts[k],
            max: max,
            color: OT.accent,
          ),
      const SizedBox(height: 4),
      Text('Sample: $total closed incidents created in these 14 days (of ${list.length} loaded).', style: const TextStyle(fontSize: 11, color: OT.muted)),
    ]);
  }
}

String _duration(int seconds) {
  if (seconds < 60) return '$seconds s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m min' : '$m min $s s';
}

String _dayLabel(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}
