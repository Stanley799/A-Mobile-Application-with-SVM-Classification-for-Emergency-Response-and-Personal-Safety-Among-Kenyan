// Approvals: responder verification (the screen the administrator already used, now with the abilities in
// words and a last-seen value) and dispatcher registration decisions. Administrators only; the server
// re-checks the administrator claim before it changes any account.
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import '../admin/admin_repository.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsApprovals extends StatefulWidget {
  const OpsApprovals({super.key, required this.repo, required this.responders});
  final OpsRepository repo;
  final List<ResponderRecord> responders;

  @override
  State<OpsApprovals> createState() => _OpsApprovalsState();
}

class _OpsApprovalsState extends State<OpsApprovals> {
  final _admin = AdminRepository();
  int _tab = 0;
  String _filter = 'Pending';
  Future<List<StaffApplication>>? _apps;

  @override
  void initState() {
    super.initState();
    _apps = widget.repo.listDispatchers();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(OT.pad, 12, OT.pad, 0),
        child: Row(children: [
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('Responders')), ButtonSegment(value: 1, label: Text('Dispatchers'))],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const Spacer(),
          if (_tab == 1)
            IconButton(tooltip: 'Refresh', onPressed: () => setState(() => _apps = widget.repo.listDispatchers()), icon: const Icon(Icons.refresh, size: 19)),
        ]),
      ),
      Expanded(child: _tab == 0 ? _responders() : _dispatchers()),
    ]);
  }

  // ------------------------------------------------------------------ responders
  Widget _responders() {
    final list = [for (final r in widget.responders) if (_filter == 'All' || r.verificationStatus == _filter) r];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(OT.pad, 10, OT.pad, 6),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in const ['Pending', 'Verified', 'Suspended', 'Rejected', 'All'])
            ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? EmptyState(
                icon: Icons.verified_user_outlined,
                title: _filter == 'Pending' ? 'No responder is waiting' : 'Nothing here',
                message: _filter == 'Pending' ? 'New responder accounts appear here for verification.' : 'No responder has this status.',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(OT.pad, 4, OT.pad, 20),
                itemCount: list.length,
                itemBuilder: (_, k) => _responderCard(list[k]),
              ),
      ),
    ]);
  }

  Widget _responderCard(ResponderRecord r) {
    final caps = r.effectiveCapabilities;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: OT.panelDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r.organizationName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OT.text))),
          OpsTag(
            r.verificationStatus,
            bg: r.verificationStatus == 'Verified' ? const Color(0xFF15352F) : const Color(0xFF33280F),
            fg: r.verificationStatus == 'Verified' ? const Color(0xFF8FE8D8) : const Color(0xFFFFCF7A),
          ),
        ]),
        const SizedBox(height: 3),
        Text(
          '${r.organizationType} · registration ${r.registrationNumber.isEmpty ? 'not given' : r.registrationNumber}'
          '${r.serviceArea.isEmpty ? '' : ' · ${r.serviceArea}'}'
          '${r.isDemo ? ' · demo account' : ''}',
          style: const TextStyle(fontSize: 12, color: OT.muted),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 5, children: [
          for (final c in caps) OpsTag(roleLabel(c)),
          if (caps.isEmpty) const OpsTag('No abilities set', bg: Color(0xFF33280F), fg: Color(0xFFFFCF7A)),
        ]),
        const SizedBox(height: 6),
        Text(
          '${r.availabilityStatus}${r.lastSeenAt == null ? ' · never seen' : ' · last seen ${_ago(r.lastSeenAt!)}'}',
          style: const TextStyle(fontSize: 12, color: OT.soft),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (r.verificationStatus != 'Verified') FilledButton(onPressed: () => _reviewResponder(r, 'Verified'), child: const Text('Verify')),
          if (r.verificationStatus == 'Verified') ...[
            OutlinedButton(onPressed: () => _reviewResponder(r, 'Verified'), child: const Text('Edit abilities')),
            OutlinedButton(onPressed: () => _reviewResponder(r, 'Suspended'), child: const Text('Suspend')),
          ],
          if (r.verificationStatus == 'Pending') OutlinedButton(onPressed: () => _reviewResponder(r, 'Rejected'), child: const Text('Reject')),
          if (r.verificationStatus == 'Suspended' || r.verificationStatus == 'Rejected')
            TextButton(onPressed: () => _reviewResponder(r, 'Verified'), child: const Text('Restore')),
        ]),
      ]),
    );
  }

  Future<void> _reviewResponder(ResponderRecord r, String status) async {
    final caps = {...r.effectiveCapabilities};
    final notes = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          backgroundColor: OT.panel,
          title: Text('$status: ${r.organizationName}', style: const TextStyle(color: OT.text)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (status == 'Verified') ...[
                  const Text('What can this unit do?', style: TextStyle(fontWeight: FontWeight.w700, color: OT.soft)),
                  const SizedBox(height: 4),
                  for (final k in kRoleLabels.keys.where((k) => k != 'any_responder'))
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: caps.contains(k),
                      title: Text(kRoleLabels[k]!, style: const TextStyle(fontSize: 13, color: OT.soft)),
                      onChanged: (v) => set(() => v == true ? caps.add(k) : caps.remove(k)),
                    ),
                ],
                TextField(controller: notes, maxLength: 200, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder())),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(status)),
          ],
        ),
      ),
    );
    if (go != true) return;
    try {
      await _admin.review(r.id, status, notes: notes.text.trim().isEmpty ? null : notes.text.trim(), capabilities: status == 'Verified' ? caps.toList() : null);
      _toast('${r.organizationName}: $status');
    } catch (e) {
      _toast('Could not save: $e');
    }
  }

  // ------------------------------------------------------------------ dispatchers
  Widget _dispatchers() => FutureBuilder<List<StaffApplication>>(
    future: _apps,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) return const OpsSkeleton(rows: 4);
      if (s.hasError) return ErrorState(message: 'Could not load dispatcher applications: ${s.error}', onRetry: () => setState(() => _apps = widget.repo.listDispatchers()));
      final list = s.data ?? const <StaffApplication>[];
      if (list.isEmpty) return const EmptyState(icon: Icons.badge_outlined, title: 'No dispatcher applications', message: 'People who register as a dispatcher appear here for a decision.');
      return ListView(padding: const EdgeInsets.fromLTRB(OT.pad, 10, OT.pad, 20), children: [
        for (final a in list) _dispatcherCard(a),
      ]);
    },
  );

  Widget _dispatcherCard(StaffApplication a) {
    final (bg, fg) = switch (a.status) {
      'approved' => (const Color(0xFF15352F), const Color(0xFF8FE8D8)),
      'pending' => (const Color(0xFF33280F), const Color(0xFFFFCF7A)),
      _ => (const Color(0xFF3A2020), const Color(0xFFFFB8B0)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: OT.panelDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(a.name.isEmpty ? a.email : a.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OT.text))),
          OpsTag(a.status, bg: bg, fg: fg),
        ]),
        const SizedBox(height: 3),
        Text(a.email, style: const TextStyle(fontSize: 12, color: OT.muted)),
        if (a.accountStatus.isNotEmpty) Text('Account: ${a.accountStatus}', style: const TextStyle(fontSize: 12, color: OT.soft)),
        if (a.reason.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Reason: ${a.reason}', style: const TextStyle(fontSize: 12, color: OT.soft)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (a.status != 'approved') FilledButton(onPressed: () => _reviewDispatcher(a, 'approved'), child: Text(a.status == 'pending' ? 'Approve' : 'Approve again')),
          if (a.status == 'pending') OutlinedButton(onPressed: () => _reviewDispatcher(a, 'rejected'), child: const Text('Reject')),
          if (a.status == 'approved') OutlinedButton(onPressed: () => _reviewDispatcher(a, 'suspended'), child: const Text('Suspend')),
        ]),
      ]),
    );
  }

  Future<void> _reviewDispatcher(StaffApplication a, String action) async {
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: OT.panel,
        title: Text('${_verb(action)} ${a.name.isEmpty ? a.email : a.name}?', style: const TextStyle(color: OT.text)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              action == 'approved' ? 'The dispatcher claim is set and their other sessions are signed out.' : 'The dispatcher claim is removed and their sessions are signed out.',
              style: const TextStyle(fontSize: 12.5, color: OT.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(labelText: action == 'approved' ? 'Note (optional)' : 'Reason (the applicant reads this)', border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (action != 'approved' && reason.text.trim().length < 3) {
                ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Give a reason (at least 3 characters).')));
                return;
              }
              Navigator.pop(c, true);
            },
            child: Text(_verb(action)),
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      await widget.repo.reviewDispatcher(a.uid, action, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
      _toast('${a.name.isEmpty ? a.email : a.name}: $action');
      setState(() => _apps = widget.repo.listDispatchers());
    } catch (e) {
      _toast('Could not save: $e');
    }
  }

  static String _verb(String action) => switch (action) { 'approved' => 'Approve', 'rejected' => 'Reject', _ => 'Suspend' };
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}
