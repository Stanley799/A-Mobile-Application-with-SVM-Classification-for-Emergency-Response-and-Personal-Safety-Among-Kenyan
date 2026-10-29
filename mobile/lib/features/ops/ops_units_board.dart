// Units board: Available, On a job, Stale GPS (heartbeat older than 120 s) and Offline.
// The last-100-offer statistics are computed only when a unit is expanded.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'ops_logic.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsUnitsBoard extends StatefulWidget {
  const OpsUnitsBoard({super.key, required this.responders, required this.offers, this.groupFilter, this.compact = false, this.onShowAll});

  final List<ResponderRecord> responders;
  final List<Offer> offers;
  final String? groupFilter;
  final bool compact;
  final VoidCallback? onShowAll;

  @override
  State<OpsUnitsBoard> createState() => _OpsUnitsBoardState();
}

class _OpsUnitsBoardState extends State<OpsUnitsBoard> {
  final Set<String> _expanded = {};
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ResponderRecord>>{for (final g in kUnitGroups) g: []};
    for (final r in widget.responders) {
      groups[unitGroup(r.availabilityStatus, r.lastSeenAt, now: _now)]!.add(r);
    }
    for (final list in groups.values) {
      list.sort((a, b) => a.organizationName.toLowerCase().compareTo(b.organizationName.toLowerCase()));
    }
    final show = widget.groupFilter == null ? kUnitGroups : [widget.groupFilter!];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.compact)
        const Padding(
          padding: EdgeInsets.fromLTRB(OT.pad, 10, OT.pad, 4),
          child: Text(
            'A heartbeat older than 120 seconds counts as stale. Statistics are computed from the latest offers on this device.',
            style: TextStyle(fontSize: 11.5, color: OT.muted),
          ),
        ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(OT.pad, 6, OT.pad, 16), children: [
          for (final g in show)
            if (groups[g]!.isNotEmpty || widget.groupFilter != null) ...[
              OpsUnitsGroupHeader(group: g, count: groups[g]!.length),
              if (groups[g]!.isEmpty)
                const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('No units in this state.', style: TextStyle(fontSize: 12.5, color: OT.muted)))
              else
                for (final r in (widget.compact ? groups[g]!.take(4) : groups[g]!))
                  _UnitTile(
                    responder: r,
                    offers: widget.offers,
                    group: g,
                    now: _now,
                    compact: widget.compact,
                    expanded: _expanded.contains(r.id),
                    onToggle: () => setState(() => _expanded.contains(r.id) ? _expanded.remove(r.id) : _expanded.add(r.id)),
                  ),
              const SizedBox(height: 10),
            ],
          if (widget.compact)
            Center(
              child: TextButton(onPressed: widget.onShowAll, child: const Text('Open the units board')),
            ),
        ]),
      ),
    ]);
  }
}

class OpsUnitsGroupHeader extends StatelessWidget {
  const OpsUnitsGroupHeader({super.key, required this.group, required this.count});
  final String group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = switch (group) { 'Available' => OT.accent, 'On a job' => OT.priority('Medium'), 'Stale GPS' => const Color(0xFF8A939B), _ => OT.muted };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(group.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: c)),
        const SizedBox(width: 6),
        Text('$count', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OT.muted)),
      ]),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.responder,
    required this.offers,
    required this.group,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.compact,
  });

  final ResponderRecord responder;
  final List<Offer> offers;
  final String group;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final r = responder;
    final caps = r.effectiveCapabilities;
    final seen = r.lastSeenAt == null ? 'never seen' : 'seen ${_ago(now.difference(r.lastSeenAt!))}';
    final stats = expanded ? unitStats(offers, r.id, now: now) : UnitStats.empty;
    final jobsToday = expanded ? _jobsToday(offers, r.id, now) : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: OT.panel,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: OT.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(r.organizationName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OT.text)),
                ),
                if (r.verificationStatus != 'Verified') const OpsTag('Not verified', bg: Color(0xFF33280F), fg: Color(0xFFFFCF7A)),
                const SizedBox(width: 6),
                Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 17, color: OT.muted),
              ]),
              const SizedBox(height: 2),
              Text('${r.organizationType} · $seen · ${r.serviceArea.isEmpty ? 'No service area' : r.serviceArea}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: OT.muted)),
              if (!compact) ...[
                const SizedBox(height: 5),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final c in (caps.isEmpty ? const ['any_responder'] : caps)) OpsTag(roleLabel(c)),
                ]),
              ],
              if (expanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1, color: OT.line),
                const SizedBox(height: 8),
                Wrap(spacing: 18, runSpacing: 6, children: [
                  _stat('Jobs today', '$jobsToday'),
                  _stat('Offers, 30 days', '${stats.offers}'),
                  _stat('Acceptance', stats.acceptanceRate == null ? '-' : '${(stats.acceptanceRate! * 100).round()}%'),
                  _stat('Median accept', stats.medianSecondsToAccept == null ? '-' : _dur(stats.medianSecondsToAccept!)),
                  _stat('Avg accept', stats.averageSecondsToAccept == null ? '-' : _dur(stats.averageSecondsToAccept!)),
                ]),
                if (stats.offers == 0)
                  const Padding(padding: EdgeInsets.only(top: 4), child: Text('No offers in the last 30 days on this device.', style: TextStyle(fontSize: 11, color: OT.muted))),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Text(k.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: OT.muted)),
    Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OT.text, fontFeatures: [FontFeature.tabularFigures()])),
  ]);
}

int _jobsToday(List<Offer> offers, String responderId, DateTime now) {
  var n = 0;
  for (final o in offers) {
    if (o.responderId != responderId) continue;
    final at = o.respondedAt;
    if (at == null || !kHeldStatuses.contains(o.status)) continue;
    if (at.year == now.year && at.month == now.month && at.day == now.day) n++;
  }
  return n;
}

String _ago(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}

String _dur(int s) => s < 60 ? '$s s' : '${s ~/ 60} m ${s % 60} s';
