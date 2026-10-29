import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import 'admin_repository.dart';
import 'admin_stats.dart';
import 'admin_widgets.dart';

class AdminIncidents extends StatefulWidget {
  const AdminIncidents({super.key, required this.incidents, required this.onOpen});
  final List<IncidentRecord> incidents;
  final void Function(IncidentRecord) onOpen;

  @override
  State<AdminIncidents> createState() => _AdminIncidentsState();
}

class _AdminIncidentsState extends State<AdminIncidents> {
  String _filter = 'open'; // open | attention | all
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final i in widget.incidents)
        if ((_filter == 'all' || (_filter == 'open' && i.isOpen) || (_filter == 'attention' && AdminStats.needsAttention(i))) &&
            (_q.isEmpty || i.id.toLowerCase().contains(_q) || i.category.toLowerCase().contains(_q)))
          i,
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in const [('open', 'Open'), ('attention', 'Needs attention'), ('all', 'All')])
            ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
          SizedBox(
            width: 240,
            child: TextField(decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search id or category', border: OutlineInputBorder()), onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
          ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? const Center(child: Text('No incidents match.', style: TextStyle(color: AC.mute)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: list.length,
                itemBuilder: (_, k) {
                  final i = list[k];
                  return Card(
                    elevation: 0,
                    color: AC.card,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AC.line)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => widget.onOpen(i),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          PriorityPill(i.priority),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${i.category}${i.subtype == null ? '' : ' · ${i.subtype!.replaceAll('_', ' ')}'}', style: const TextStyle(fontWeight: FontWeight.w800, color: AC.ink)),
                            const SizedBox(height: 2),
                            Text(i.id, style: const TextStyle(fontSize: 12, color: AC.mute)),
                          ])),
                          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            StatePill(i.dispatchState),
                            if (!i.isOpen) Pill(i.status, const Color(0xFFEDEDED), const Color(0xFF444444)),
                            Text(ago(i.createdAt), style: const TextStyle(fontSize: 12, color: AC.mute)),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class IncidentDetailPage extends StatefulWidget {
  const IncidentDetailPage({super.key, required this.repo, required this.incidentId, required this.responders});
  final AdminRepository repo;
  final String incidentId;
  final List<ResponderRecord> responders;

  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  Future<List<AuditEntry>>? _audit;
  ({String firstName, String phone})? _contact;
  bool _revealBusy = false;

  @override
  void initState() {
    super.initState();
    _audit = widget.repo.auditFor(widget.incidentId);
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _assign(IncidentRecord inc) async {
    final cands = [for (final r in widget.responders) if (r.verificationStatus == 'Verified' && r.availabilityStatus != 'Offline') r];
    final picked = await showDialog<ResponderRecord>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Ask which responder?'),
        children: cands.isEmpty
            ? [const Padding(padding: EdgeInsets.all(20), child: Text('No verified responder is on duty.'))]
            : [
                for (final r in cands)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, r),
                    child: Text('${r.organizationName} · ${r.organizationType} · ${r.availabilityStatus}\n${r.effectiveCapabilities.map(roleLabel).join(', ')}'),
                  ),
              ],
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ask ${picked.organizationName} directly?'),
        content: TextField(controller: reason, maxLength: 140, decoration: const InputDecoration(labelText: 'Reason for the manual override')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length < 3) {
                ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Give a reason (at least 3 characters).')));
                return;
              }
              Navigator.pop(c, true);
            },
            child: const Text('Confirm and send'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.assign(inc.id, picked.id, reason: reason.text.trim());
      _toast('Offer sent to ${picked.organizationName}. It expires in 90 seconds.');
    } catch (e) {
      _toast('Could not assign: $e');
    }
  }

  Future<void> _close(IncidentRecord inc) async {
    final note = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close this incident?'),
        content: TextField(controller: note, maxLength: 280, decoration: const InputDecoration(labelText: 'Note (what happened)')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close incident'))],
      ),
    );
    if (yes != true) return;
    try {
      await widget.repo.close(inc.id, note.text.trim());
      _toast('Incident closed.');
    } catch (e) {
      _toast('Could not close: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IncidentRecord?>(
      stream: widget.repo.watchIncident(widget.incidentId),
      builder: (context, snap) {
        final inc = snap.data;
        return Scaffold(
          backgroundColor: AC.bg,
          appBar: AppBar(backgroundColor: AC.card, foregroundColor: AC.ink, elevation: 0, title: const Text('Incident', style: TextStyle(fontWeight: FontWeight.w800))),
          body: inc == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(20), children: [
                  _header(inc),
                  _why(inc),
                  _units(inc),
                  _resident_(inc),
                  _timeline(),
                  if (inc.isOpen)
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      FilledButton.icon(onPressed: inc.latitude == null ? null : () => _assign(inc), icon: const Icon(Icons.person_add_alt), label: const Text('Ask a responder')),
                      OutlinedButton.icon(onPressed: () => _close(inc), icon: const Icon(Icons.check_circle_outline), label: const Text('Close incident')),
                    ]),
                ]),
        );
      },
    );
  }

  Widget _header(IncidentRecord i) => Panel(
    title: '${i.category}${i.subtype == null ? '' : ' · ${i.subtype!.replaceAll('_', ' ')}'}',
    trailing: PriorityPill(i.priority),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText(i.id, style: const TextStyle(fontSize: 13, color: AC.mute)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [StatePill(i.dispatchState), Pill(i.status, const Color(0xFFEDEDED), const Color(0xFF444444)), Pill('Triage: ${i.triageStatus}', const Color(0xFFEDEDED), const Color(0xFF444444)), if (i.escalate922) const Pill('922 advised to resident', Color(0xFFFDE8E8), Color(0xFF9B1C1C))]),
      const SizedBox(height: 10),
      Text('Created ${clock(i.createdAt)} (${ago(i.createdAt)})', style: const TextStyle(fontSize: 13, color: AC.mute)),
      if (i.latitude != null) ...[
        const SizedBox(height: 8),
        TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${i.latitude},${i.longitude}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.map_outlined), label: Text('${i.latitude!.toStringAsFixed(5)}, ${i.longitude!.toStringAsFixed(5)}')),
      ] else
        const Text('No location yet.', style: TextStyle(color: AC.high, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _why(IncidentRecord i) => Panel(
    title: 'Why this priority',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${i.priority} · decided by: ${i.prioritySource.isEmpty ? 'pending' : i.prioritySource.replaceAll('_', ' ')}', style: const TextStyle(fontWeight: FontWeight.w700, color: AC.ink)),
      const SizedBox(height: 8),
      if (i.priorityReasons.isNotEmpty) ...[const Text('Safety rules triggered', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AC.mute)), for (final r in i.priorityReasons) Text('• $r')],
      if (i.answers.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('Answers given', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AC.mute)),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final e in i.answers.entries) Pill('${e.key.replaceAll('_', ' ')}: ${e.value}', const Color(0xFFEDEDED), AC.ink)]),
      ] else
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('No answers yet. The alert was sent with the fail-safe priority.', style: TextStyle(color: AC.mute))),
      if (i.needsHumanReview && i.triageStatus == 'complete') const Padding(padding: EdgeInsets.only(top: 10), child: Text('The classifier was not confident. Please review.', style: TextStyle(color: AC.medium, fontWeight: FontWeight.w700))),
    ]),
  );

  Widget _units(IncidentRecord i) => Panel(
    title: 'Responders asked',
    child: StreamBuilder<List<Offer>>(
      stream: widget.repo.watchOffersFor(i.id),
      builder: (context, s) {
        final list = s.data ?? const <Offer>[];
        if (list.isEmpty) return Text(i.dispatchState == 'support_only' ? 'Support only: no responder is sent for this kind of alert.' : 'No offer has been made yet.', style: const TextStyle(color: AC.mute));
        final names = {for (final r in widget.responders) r.id: r.organizationName};
        return Column(children: [
          for (final o in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(names[o.responderId] ?? o.responderId, style: const TextStyle(fontWeight: FontWeight.w700, color: AC.ink)),
                  Text('${roleLabel(o.role)} · wave ${o.wave} · ${o.distanceKm.toStringAsFixed(1)} km · asked ${clock(o.createdAt)}${o.respondedAt == null ? '' : ' · answered ${clock(o.respondedAt)}'}', style: const TextStyle(fontSize: 12, color: AC.mute)),
                ])),
                Pill(o.status, AC.stateColors(o.status == 'offered' ? 'dispatching' : (o.status == 'declined' || o.status == 'expired' || o.status == 'withdrawn') ? 'cancelled' : 'assigned').$1, AC.stateColors(o.status == 'offered' ? 'dispatching' : (o.status == 'declined' || o.status == 'expired' || o.status == 'withdrawn') ? 'cancelled' : 'assigned').$2),
              ]),
            ),
        ]);
      },
    ),
  );

  Future<void> _revealContact(IncidentRecord i) async {
    setState(() => _revealBusy = true);
    try {
      final c = await widget.repo.revealContact(i.id);
      if (mounted) setState(() => _contact = c);
    } catch (e) {
      _toast('Could not reveal: $e');
    } finally {
      if (mounted) setState(() => _revealBusy = false);
    }
  }

  Widget _resident_(IncidentRecord i) => Panel(
    title: 'Caller',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(
            _contact == null ? '••• ••• •••' : '${_contact!.firstName.isEmpty ? 'Caller' : _contact!.firstName} · ${_contact!.phone}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AC.ink),
          ),
        ),
        OutlinedButton(
          onPressed: _revealBusy ? null : () => _revealContact(i),
          child: _revealBusy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_contact == null ? 'Reveal contact' : 'Show again'),
        ),
      ]),
      if (_contact != null && _contact!.phone.isNotEmpty) ...[
        const SizedBox(height: 4),
        SelectableText(_contact!.phone, style: const TextStyle(color: AC.mute)),
        const Text('Revealing is written to the timeline.', style: TextStyle(fontSize: 11, color: AC.mute)),
      ],
      const SizedBox(height: 8),
      Text(i.description.isEmpty ? 'No description saved.' : i.description, style: const TextStyle(color: AC.ink)),
      const SizedBox(height: 6),
      const Text("The caller's number is never read from Firestore directly.", style: TextStyle(fontSize: 11, color: AC.mute)),
    ]),
  );

  Widget _timeline() => Panel(
    title: 'Timeline',
    trailing: IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh, size: 18), onPressed: () => setState(() => _audit = widget.repo.auditFor(widget.incidentId))),
    child: FutureBuilder<List<AuditEntry>>(
      future: _audit,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        if (s.hasError) return Text('Could not load the timeline: ${s.error}', style: const TextStyle(color: AC.high));
        final list = s.data ?? const <AuditEntry>[];
        if (list.isEmpty) return const Text('No events yet.', style: TextStyle(color: AC.mute));
        return Column(children: [
          for (final e in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 70, child: Text(clock(e.at), style: const TextStyle(fontSize: 12, color: AC.mute))),
                Expanded(child: Text('${e.action.replaceAll('_', ' ')}${e.detail.isEmpty ? '' : '  (${e.detail})'}', style: const TextStyle(fontSize: 13, color: AC.ink))),
              ]),
            ),
        ]);
      },
    ),
  );
}
