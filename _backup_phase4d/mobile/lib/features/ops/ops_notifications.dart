// The bell tray: SOS, attention flags, extra-unit requests, new High incidents and imprecise locations.
// A new High incident or SOS rings the system sound ONCE (never on load, never while muted).
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

enum NoticeKind { sos, attention, extraResources, high, lowAccuracy }

class OpsNotice {
  const OpsNotice({required this.id, required this.kind, required this.title, required this.body, required this.at, this.incidentId, this.sos});

  final String id;
  final NoticeKind kind;
  final String title;
  final String body;
  final DateTime? at;
  final String? incidentId;
  final SosAlert? sos;

  bool get isUrgent => kind == NoticeKind.sos || kind == NoticeKind.high;
}

/// Newest first. An incident can raise more than one notice (e.g. High priority and low accuracy).
List<OpsNotice> buildNotices({required List<IncidentRecord> incidents, required List<SosAlert> sos, DateTime? now}) {
  final out = <OpsNotice>[];
  for (final s in sos) {
    if (s.status != 'open') continue;
    out.add(OpsNotice(
      id: 'sos_${s.id}',
      kind: NoticeKind.sos,
      title: 'SOS from ${s.orgName}',
      body: s.incidentId == null ? 'A responder asked for immediate help.' : 'A responder on an incident asked for immediate help.',
      at: s.at,
      incidentId: s.incidentId,
      sos: s,
    ));
  }
  for (final i in incidents) {
    if (!i.isOpen) continue;
    final where = i.landmark.isEmpty ? i.category : '${i.category} · ${i.landmark}';
    if (i.needsAttention) {
      final kind = i.attentionReason == 'extra_resources'
          ? NoticeKind.extraResources
          : i.attentionReason == 'low_accuracy'
          ? NoticeKind.lowAccuracy
          : NoticeKind.attention;
      final body = switch (i.attentionReason) {
        'no_accept_in_time' => 'No unit has accepted within the target time.',
        'extra_resources' => 'Someone asked for more units.',
        'responder_sos' => 'A responder raised an SOS.',
        'low_accuracy' => 'The caller location is imprecise.',
        _ => 'This incident was flagged for a human.',
      };
      out.add(OpsNotice(id: '${kind.name}_${i.id}', kind: kind, title: where, body: body, at: i.createdAt, incidentId: i.id));
    }
    if (i.priority == 'High') {
      out.add(OpsNotice(id: 'high_${i.id}', kind: NoticeKind.high, title: 'High priority: $where', body: 'A new High priority incident is open.', at: i.createdAt, incidentId: i.id));
    }
  }
  out.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
  return out;
}

IconData noticeIcon(NoticeKind k) => switch (k) {
  NoticeKind.sos => Icons.sos_outlined,
  NoticeKind.attention => Icons.priority_high,
  NoticeKind.extraResources => Icons.group_add_outlined,
  NoticeKind.high => Icons.campaign_outlined,
  NoticeKind.lowAccuracy => Icons.my_location_outlined,
};

class NoticeTray extends StatelessWidget {
  const NoticeTray({super.key, required this.notices, required this.muted, required this.onToggleMute, required this.onOpenIncident, required this.onResolveSos, required this.onClose});

  final List<OpsNotice> notices;
  final bool muted;
  final VoidCallback onToggleMute;
  final void Function(String incidentId) onOpenIncident;
  final void Function(SosAlert sos) onResolveSos;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    width: 380,
    constraints: const BoxConstraints(maxHeight: 520),
    decoration: BoxDecoration(color: OT.panel, borderRadius: BorderRadius.circular(OT.radius), border: Border.all(color: OT.line)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Row(children: [
          const Expanded(child: Text('Notifications', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: OT.text))),
          TextButton.icon(
            onPressed: onToggleMute,
            icon: Icon(muted ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 18),
            label: Text(muted ? 'Muted' : 'Sound on'),
          ),
          IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close, size: 18)),
        ]),
      ),
      const Divider(height: 1, color: OT.line),
      Flexible(
        child: notices.isEmpty
            ? const EmptyState(icon: Icons.notifications_none, title: 'Nothing needs you right now', message: 'SOS alerts, attention flags and new High priority incidents appear here.')
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: notices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, k) {
                  final n = notices[k];
                  final urgent = n.kind == NoticeKind.sos;
                  return Material(
                    color: urgent ? const Color(0xFF2C1A1A) : OT.raised,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        if (n.sos != null) {
                          onResolveSos(n.sos!);
                        } else if (n.incidentId != null) {
                          onOpenIncident(n.incidentId!);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: urgent ? OT.alert : OT.panel, shape: BoxShape.circle, border: Border.all(color: urgent ? OT.alert : OT.line)),
                            child: Icon(noticeIcon(n.kind), size: 14, color: urgent ? Colors.white : OT.soft),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(n.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OT.text)),
                              const SizedBox(height: 2),
                              Text(n.body, style: const TextStyle(fontSize: 12, color: OT.muted)),
                            ]),
                          ),
                          if (n.sos != null)
                            TextButton(onPressed: () => onResolveSos(n.sos!), child: const Text('Resolve')),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]),
  );
}
