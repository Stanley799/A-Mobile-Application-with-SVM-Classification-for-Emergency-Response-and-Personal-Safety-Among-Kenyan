// "Request more units": the first unit on scene is the incident commander (Beacon pattern) and can ask for backups.
import 'package:flutter/material.dart';

import 'responder_theme.dart';

const List<({String code, String label})> kMoreUnitRoles = [
  (code: 'medical_transport', label: 'Ambulance'),
  (code: 'fire_suppression', label: 'Fire'),
  (code: 'law_enforcement', label: 'Police'),
  (code: 'maternal_care', label: 'Medical support'),
];

String moreUnitRoleLabel(String code) => kMoreUnitRoles
    .firstWhere(
      (r) => r.code == code,
      orElse: () => (code: code, label: code.replaceAll('_', ' ')),
    )
    .label;

Future<bool?> showMoreUnitsSheet(
  BuildContext context, {
  required Future<void> Function(String role, int count, String note) onSubmit,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
    child: MoreUnitsRequestSheet(onSubmit: onSubmit),
  ),
);

class MoreUnitsRequestSheet extends StatefulWidget {
  const MoreUnitsRequestSheet({super.key, required this.onSubmit});
  final Future<void> Function(String role, int count, String note) onSubmit;

  @override
  State<MoreUnitsRequestSheet> createState() => _MoreUnitsRequestSheetState();
}

class _MoreUnitsRequestSheetState extends State<MoreUnitsRequestSheet> {
  String _role = kMoreUnitRoles.first.code;
  int _count = 1;
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_role, _count, _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Could not send the request. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Request more units', style: ResponderTextStyles.title),
          const SizedBox(height: ResponderSpacing.xs),
          const Text(
            'Dispatch will be asked for the next nearest unit.',
            style: ResponderTextStyles.caption,
          ),
          const SizedBox(height: ResponderSpacing.lg),
          const Text('What do you need?', style: ResponderTextStyles.section),
          const SizedBox(height: ResponderSpacing.sm),
          Wrap(
            spacing: ResponderSpacing.sm,
            runSpacing: ResponderSpacing.sm,
            children: [
              for (final role in kMoreUnitRoles)
                ChoiceChip(
                  label: Text(role.label),
                  selected: _role == role.code,
                  onSelected: (_) => setState(() => _role = role.code),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _role == role.code ? RC.text : RC.soft,
                  ),
                  selectedColor: RC.needBg,
                  backgroundColor: RC.surface2,
                  side: BorderSide(
                    color: _role == role.code ? RC.outline : RC.line,
                  ),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: ResponderSpacing.lg),
          Row(
            children: [
              const Expanded(
                child: Text('How many?', style: ResponderTextStyles.section),
              ),
              _StepButton(
                icon: Icons.remove,
                label: 'One fewer',
                onPressed: _count > 1 ? () => setState(() => _count--) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '$_count',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: RC.text,
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                label: 'One more',
                onPressed: _count < 3 ? () => setState(() => _count++) : null,
              ),
            ],
          ),
          const SizedBox(height: ResponderSpacing.lg),
          TextField(
            controller: _note,
            maxLength: 140,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(color: RC.text, fontSize: 15),
            decoration: const InputDecoration(
              labelText: 'Note for dispatch (optional)',
              helperText: 'No names or phone numbers',
              helperStyle: TextStyle(color: RC.muted, fontSize: 12),
              counterStyle: TextStyle(color: RC.muted, fontSize: 12),
              filled: true,
              fillColor: RC.surface2,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: RC.line),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: ResponderSpacing.sm),
            Text(_error!, style: const TextStyle(color: RC.alert, fontSize: 13)),
          ],
          const SizedBox(height: ResponderSpacing.lg),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: RC.accept,
                foregroundColor: const Color(0xFF04130C),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF04130C),
                      ),
                    )
                  : const Text(
                      'Request',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: RC.surface2,
      foregroundColor: RC.text,
      disabledBackgroundColor: RC.card,
      disabledForegroundColor: RC.muted,
      minimumSize: const Size(44, 44),
    ),
    icon: Icon(icon),
  );
}
