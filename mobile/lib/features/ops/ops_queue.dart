// The pending queue: incidents that are not fully staffed. Rows that breached their SLA are pinned
// to the top with the reason in words. The elapsed timer updates every second while the console is open.
import 'dart:async';

import 'package:flutter/material.dart';

import 'ops_logic.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsQueue extends StatefulWidget {
  const OpsQueue({
    super.key,
    required this.repo,
    required this.rows,
    required this.selectedId,
    required this.onSelect,
    this.filterLabel,
    this.onClearFilter,
    this.emptyTitle = 'Nothing is waiting',
    this.emptyMessage = 'Every open alert has a unit holding each role it needs.',
  });

  final OpsRepository repo;
  final List<QueueRow> rows;
  final String? selectedId;
  final void Function(QueueRow) onSelect;
  final String? filterLabel;
  final VoidCallback? onClearFilter;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<OpsQueue> createState() => _OpsQueueState();
}

class _OpsQueueState extends State<OpsQueue> {
  final Map<String, String> _streets = {};
  final Set<String> _loading = {};
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStreets());
  }

  @override
  void didUpdateWidget(covariant OpsQueue old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStreets());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// One reverse geocode per incident, in order, and only once. Failures show the landmark instead.
  Future<void> _loadStreets() async {
    for (final row in widget.rows) {
      final i = row.incident;
      if (i.latitude == null || i.longitude == null) continue;
      if (_streets.containsKey(i.id) || _loading.contains(i.id)) continue;
      _loading.add(i.id);
      final s = await widget.repo.streetLabel(i.latitude!, i.longitude!);
      _loading.remove(i.id);
      if (!mounted) return;
      if (s.isNotEmpty) setState(() => _streets[i.id] = s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(OT.pad, 10, OT.pad, 6),
        child: Row(children: [
          Expanded(
            child: Text(
              rows.isEmpty ? 'QUEUE' : 'QUEUE · ${rows.length} WAITING',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: OT.muted),
            ),
          ),
          if (widget.filterLabel != null)
            TextButton.icon(
              onPressed: widget.onClearFilter,
              icon: const Icon(Icons.close, size: 14),
              label: Text(widget.filterLabel!, style: const TextStyle(fontSize: 11.5)),
            ),
        ]),
      ),
      Expanded(
        child: rows.isEmpty
            ? EmptyState(icon: Icons.done_all_outlined, title: widget.emptyTitle, message: widget.emptyMessage)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                itemCount: rows.length,
                itemBuilder: (_, k) {
                  final row = rows[k];
                  final i = row.incident;
                  return _QueueTile(
                    row: row,
                    street: _streets[i.id],
                    elapsed: i.createdAt == null ? null : Duration(seconds: _now.difference(i.createdAt!).inSeconds),
                    selected: widget.selectedId == i.id,
                    onTap: () => widget.onSelect(row),
                  );
                },
              ),
      ),
    ]);
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.row, required this.street, required this.elapsed, required this.selected, required this.onTap});

  final QueueRow row;
  final String? street;
  final Duration? elapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = row.incident;
    final pinned = row.pinned;
    final accent = OT.priority(i.priority);
    final sub = i.subtype == null ? '' : i.subtype!.replaceAll('_', ' ');
    final place = street ?? (i.landmark.isNotEmpty ? i.landmark : (i.latitude == null ? 'No location' : 'Finding the street…'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? OT.raised : OT.panel,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: selected ? OT.accent : (pinned ? const Color(0xFF7A3A3A) : OT.line)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, color: pinned ? OT.alert : accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      PriorityTag(i.priority),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sub.isEmpty ? i.category : '${i.category} · $sub',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OT.text),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        elapsed == null ? '--:--' : mmss(elapsed!),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: OT.soft, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.place_outlined, size: 13, color: OT.muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: OT.muted)),
                      ),
                      const SizedBox(width: 6),
                      Text('${row.rolesLabel} roles', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: OT.soft)),
                    ]),
                    if (pinned) ...[
                      const SizedBox(height: 5),
                      Row(children: [
                        const Icon(Icons.error_outline, size: 13, color: OT.alert),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(row.attentionText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: OT.alert)),
                        ),
                      ]),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
