// Approvals: responder verification (the screen the administrator already used, now with the abilities in
// words and a last-seen value). Administrators only; the server re-checks the administrator claim before
// it changes any account.
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import '../admin/admin_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsApprovals extends StatefulWidget {
  const OpsApprovals({super.key, required this.responders});
  final List<ResponderRecord> responders;

  @override
  State<OpsApprovals> createState() => _OpsApprovalsState();
}

class _OpsApprovalsState extends State<OpsApprovals> {
  final _admin = AdminRepository();
  String _filter = 'Pending';

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return _responders();
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

}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}
