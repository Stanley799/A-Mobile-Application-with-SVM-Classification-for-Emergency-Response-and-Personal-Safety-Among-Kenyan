import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'admin_repository.dart';
import 'admin_widgets.dart';

class AdminResponders extends StatefulWidget {
  const AdminResponders({super.key, required this.repo, required this.responders});
  final AdminRepository repo;
  final List<ResponderRecord> responders;

  @override
  State<AdminResponders> createState() => _AdminRespondersState();
}

class _AdminRespondersState extends State<AdminResponders> {
  String _filter = 'Pending';

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _review(ResponderRecord r, String status) async {
    var caps = {...r.effectiveCapabilities};
    final notes = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('$status: ${r.organizationName}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.organizationType} · registration ${r.registrationNumber} · ${r.serviceArea}'),
              const SizedBox(height: 12),
              if (status == 'Verified') ...[
                const Text('What can this responder do?', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final k in kRoleLabels.keys.where((k) => k != 'any_responder'))
                  CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: caps.contains(k), title: Text(kRoleLabels[k]!), onChanged: (v) => set(() => v == true ? caps.add(k) : caps.remove(k))),
              ],
              TextField(controller: notes, maxLength: 200, decoration: const InputDecoration(labelText: 'Note (optional)')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(status))],
        ),
      ),
    );
    if (go != true) return;
    try {
      await widget.repo.review(r.id, status, notes: notes.text.trim().isEmpty ? null : notes.text.trim(), capabilities: status == 'Verified' ? caps.toList() : null);
      _toast('${r.organizationName}: $status');
    } catch (e) {
      _toast('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = [for (final r in widget.responders) if (_filter == 'All' || r.verificationStatus == _filter) r];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Wrap(spacing: 8, children: [for (final f in const ['Pending', 'Verified', 'Suspended', 'Rejected', 'All']) ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f))]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text(_filter == 'Pending' ? 'No responder is waiting for verification.' : 'No responders here.', style: const TextStyle(color: AC.mute)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: list.length,
                itemBuilder: (_, k) {
                  final r = list[k];
                  return Panel(
                    title: r.organizationName,
                    trailing: Pill(r.verificationStatus, r.verificationStatus == 'Verified' ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0), r.verificationStatus == 'Verified' ? const Color(0xFF1B5E20) : const Color(0xFF9C3700)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.organizationType} · registration ${r.registrationNumber}${r.serviceArea.isEmpty ? '' : ' · ${r.serviceArea}'}${r.isDemo ? ' · DEMO' : ''}', style: const TextStyle(color: AC.mute, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final c in r.effectiveCapabilities) Pill(roleLabel(c), const Color(0xFFE0F2F1), AC.brand), if (r.effectiveCapabilities.isEmpty) const Text('No abilities set', style: TextStyle(color: AC.high, fontSize: 13))]),
                      const SizedBox(height: 8),
                      Text('${r.availabilityStatus}${r.lastSeenAt == null ? '' : ' · last seen ${ago(r.lastSeenAt)}'}', style: const TextStyle(fontSize: 13, color: AC.ink)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 8, children: [
                        if (r.verificationStatus != 'Verified') FilledButton(onPressed: () => _review(r, 'Verified'), child: const Text('Verify')),
                        if (r.verificationStatus == 'Verified') OutlinedButton(onPressed: () => _review(r, 'Verified'), child: const Text('Edit abilities')),
                        if (r.verificationStatus == 'Pending') OutlinedButton(onPressed: () => _review(r, 'Rejected'), child: const Text('Reject')),
                        if (r.verificationStatus == 'Verified') OutlinedButton(onPressed: () => _review(r, 'Suspended'), child: const Text('Suspend')),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
