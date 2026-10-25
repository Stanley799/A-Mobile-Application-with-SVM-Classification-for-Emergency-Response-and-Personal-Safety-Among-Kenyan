// Administrators tab: list, add (by e-mail) and remove administrators. All changes go through server functions that re-check
// that the caller is an administrator, refuse to remove yourself or the last administrator, and write an audit entry.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_repository.dart';
import 'admin_widgets.dart';

class AdminAdmins extends StatefulWidget {
  const AdminAdmins({super.key, required this.repo});
  final AdminRepository repo;

  @override
  State<AdminAdmins> createState() => _AdminAdminsState();
}

class _AdminAdminsState extends State<AdminAdmins> {
  AdminList? _list;
  String? _error;
  bool _busy = false;
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String _msg(Object e) => e is FirebaseFunctionsException ? (e.message ?? e.code) : 'Something went wrong. Check your connection and try again.';

  Future<void> _load() async {
    try {
      final l = await widget.repo.listAdmins();
      if (mounted) setState(() { _list = l; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  Future<void> _add() async {
    final email = _email.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final link = await widget.repo.grantAdmin(email);
      _email.clear();
      await _load();
      if (!mounted) return;
      if (link != null) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Administrator created'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Send this one-time link to the new administrator privately. They use it to choose their own password, then sign in. Do not post it anywhere.'),
              const SizedBox(height: 12),
              SelectableText(link, style: const TextStyle(fontSize: 12)),
            ]),
            actions: [
              TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: link)), child: const Text('Copy link')),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Done. They must sign out and sign in again to see the administrator screens.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AdminAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove administrator?'),
        content: Text('${a.email} will lose administrator access and be signed out. Their account stays.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove'))],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.revokeAdmin(a.uid);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Panel(
        title: 'Add an administrator',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Give an existing account, or a new e-mail address, full administrator access. Use a personal work address, never a shared one.', style: TextStyle(color: AC.mute, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail address', border: OutlineInputBorder()), onSubmitted: (_) => _add())),
            const SizedBox(width: 12),
            FilledButton(onPressed: _busy ? null : _add, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add')),
          ]),
        ]),
      ),
      Panel(
        title: 'Administrators',
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Color(0xFF9B1C1C)))
            : l == null
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                : Column(children: [
                    for (final a in l.admins)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.admin_panel_settings_outlined),
                        title: Text(a.email.isEmpty ? a.uid : a.email, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(a.uid == l.me ? 'You' : (a.lastSignInAt == null ? 'Has not signed in yet' : 'Last sign-in ${a.lastSignInAt!.toLocal().toString().substring(0, 16)}')),
                        trailing: a.uid == l.me ? null : IconButton(tooltip: 'Remove administrator', icon: const Icon(Icons.person_remove_outlined), onPressed: () => _remove(a)),
                      ),
                  ]),
      ),
    ]);
  }
}
