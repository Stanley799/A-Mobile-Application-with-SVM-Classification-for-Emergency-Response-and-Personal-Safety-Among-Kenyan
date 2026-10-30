// Pass-on notes: the shift hand-over board. Everyone on duty reads them; only an administrator writes.
// A pinned note also appears as a banner above the queue.
import 'package:flutter/material.dart';

import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsNotesPage extends StatelessWidget {
  const OpsNotesPage({super.key, required this.repo, required this.notes, required this.isAdmin});

  final OpsRepository repo;
  final List<OpsNote> notes;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final pinned = [for (final n in notes) if (n.pinned) n];
    final rest = [for (final n in notes) if (!n.pinned) n];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OpsSectionHeader(
        'Pass-on notes',
        subtitle: isAdmin ? 'Pinned notes show above the queue. 500 characters each.' : 'Read-only. An administrator writes these notes.',
        trailing: isAdmin
            ? FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add, size: 18), label: const Text('Add note'))
            : null,
      ),
      Expanded(
        child: notes.isEmpty
            ? const EmptyState(icon: Icons.sticky_note_2_outlined, title: 'No pass-on notes', message: 'Notes written here stay for the next shift.')
            : ListView(padding: const EdgeInsets.fromLTRB(OT.pad, 0, OT.pad, 20), children: [
                if (pinned.isNotEmpty) ...[
                  const _GroupLabel('Pinned'),
                  for (final n in pinned) _NoteCard(note: n),
                  const SizedBox(height: 10),
                ],
                if (rest.isNotEmpty) ...[
                  const _GroupLabel('Earlier notes'),
                  for (final n in rest) _NoteCard(note: n),
                ],
              ]),
      ),
    ]);
  }

  Future<void> _add(BuildContext context) async {
    final text = TextEditingController();
    var pinned = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          backgroundColor: OT.panel,
          title: const Text('New pass-on note', style: TextStyle(color: OT.text)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: text,
                maxLength: 500,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'What the next shift must know', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: pinned,
                onChanged: (v) => set(() => pinned = v),
                title: const Text('Pin above the queue'),
              ),
              const Text('Do not write names, phone numbers or addresses in a note.', style: TextStyle(fontSize: 11.5, color: OT.muted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final t = text.text.trim();
                if (t.isEmpty) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('Write the note first.')));
                  return;
                }
                if (t.length > 500) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('Keep the note to 500 characters.')));
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('Save note'),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    try {
      await repo.addNote(text.text.trim(), pinned: pinned);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save the note: $e')));
    }
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final OpsNote note;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: note.pinned ? const Color(0xFF1E2620) : OT.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: note.pinned ? const Color(0xFF3C4A3E) : OT.line),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (note.pinned) ...[
          const Icon(Icons.push_pin_outlined, size: 13, color: Color(0xFFB8D8BD)),
          const SizedBox(width: 5),
        ],
        Text(_when(note.at), style: const TextStyle(fontSize: 11, color: OT.muted)),
        const Spacer(),
        Text('Dispatch', style: const TextStyle(fontSize: 11, color: OT.muted)),
      ]),
      const SizedBox(height: 5),
      Text(note.text, style: const TextStyle(fontSize: 13.5, color: OT.soft, height: 1.4)),
    ]),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: OT.muted)),
  );
}

String _when(DateTime? t) {
  if (t == null) return 'Just now';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
