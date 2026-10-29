// Audit (administrators only): the latest 300 system decisions. The per-incident Timeline tab is the
// detailed view, so a row links to the incident it belongs to.
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'ops_incident_panel.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsAudit extends StatefulWidget {
  const OpsAudit({super.key, required this.repo, required this.incidents, required this.onOpen});
  final OpsRepository repo;
  final List<IncidentRecord> incidents;
  final void Function(String incidentId) onOpen;

  @override
  State<OpsAudit> createState() => _OpsAuditState();
}

class _OpsAuditState extends State<OpsAudit> {
  late Stream<List<OpsAuditEntry>> _stream = widget.repo.watchAuditLogs();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OpsSectionHeader(
        'Audit',
        subtitle: 'The latest 300 decisions. Open an incident for its full timeline.',
        trailing: IconButton(tooltip: 'Refresh', onPressed: () => setState(() => _stream = widget.repo.watchAuditLogs()), icon: const Icon(Icons.refresh, size: 19)),
      ),
      Expanded(
        child: StreamBuilder<List<OpsAuditEntry>>(
          stream: _stream,
          builder: (context, s) {
            if (s.hasError) return ErrorState(message: 'Could not load the audit log: ${s.error}', onRetry: () => setState(() => _stream = widget.repo.watchAuditLogs()));
            if (!s.hasData) return const OpsSkeleton(rows: 8);
            final list = s.data ?? const <OpsAuditEntry>[];
            if (list.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No audit entries yet', message: 'Dispatch decisions are recorded here as incidents are handled.');
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(OT.pad, 0, OT.pad, 20),
              itemCount: list.length,
              itemBuilder: (_, k) => _row(list[k]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _row(OpsAuditEntry e) {
    final known = widget.incidents.any((i) => i.id == e.incidentId);
    final details = [for (final x in e.detail.entries) '${x.key}: ${x.value}'].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: OT.panel,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: known || e.incidentId.isNotEmpty ? () => widget.onOpen(e.incidentId) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: OT.line)),
            child: Row(children: [
              SizedBox(width: 128, child: Text(_stamp(e.at), style: const TextStyle(fontSize: 11, color: OT.muted))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(eventWords(e.action), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: OT.text)),
                  if (details.isNotEmpty) Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: OT.muted)),
                ]),
              ),
              if (e.incidentId.isNotEmpty) ...[
                const SizedBox(width: 8),
                OpsTag(e.incidentId),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

String _stamp(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
