// "Are you safe now?" asked once after an alert closes. Never required: every step can be skipped.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// Shows the closure sheet. [onSave] must write residentFeedback exactly once; the sheet guards repeats itself.
Future<void> showClosureSheet(
  BuildContext context, {
  required Future<bool> Function(bool safe, int? rating) onSave,
  VoidCallback? onRaiseAlert,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
  builder: (_) => _ClosureSheet(onSave: onSave, onRaiseAlert: onRaiseAlert),
);

class _ClosureSheet extends StatefulWidget {
  const _ClosureSheet({required this.onSave, this.onRaiseAlert});
  final Future<bool> Function(bool safe, int? rating) onSave;
  final VoidCallback? onRaiseAlert;

  @override
  State<_ClosureSheet> createState() => _ClosureSheetState();
}

class _ClosureSheetState extends State<_ClosureSheet> {
  bool? _safe;
  int? _rating;
  bool _saving = false;
  bool _saved = false;
  bool _failed = false;

  Future<void> _finish() async {
    final safe = _safe;
    if (safe == null || _saving || _saved) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    final ok = await widget.onSave(safe, _rating);
    if (!mounted) return;
    if (ok) {
      _saved = true;
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  Future<void> _call(String number) => launchUrl(Uri(scheme: 'tel', path: number));

  @override
  Widget build(BuildContext context) {
    final safe = _safe;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Are you safe now?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (safe == null) ...[
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                onPressed: () => setState(() => _safe = true),
                child: const Text("Yes, I'm safe", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.sosDeep, side: const BorderSide(color: AppColors.sos)),
                onPressed: () => setState(() => _safe = false),
                child: const Text('No, I still need help', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            if (safe == false) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.sosLight, borderRadius: BorderRadius.circular(16)),
                child: const Text(
                  'Call now if you are in danger. Help can also be sent again.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.sosDeep),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _callBtn('Call 999', AppColors.sos, () => _call('999'))),
                const SizedBox(width: 10),
                Expanded(child: _callBtn('Call 922', const Color(0xFF1F3A5F), () => _call('922'))),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onRaiseAlert?.call();
                },
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Raise a new alert'),
              ),
            ],
            const SizedBox(height: 18),
            const Text('How was the help? (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i of 5',
                    onPressed: _saving ? null : () => setState(() => _rating = i),
                    iconSize: 34,
                    icon: Icon(i <= (_rating ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.warning),
                  ),
              ],
            ),
            if (_failed) const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Your answer was not saved. You can close this.', style: TextStyle(fontSize: 12, color: AppColors.sosDeep)),
            ),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: _saving ? null : () {
                    _rating = null;
                    _finish();
                  },
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size(0, 50)),
                  onPressed: _saving ? null : _finish,
                  child: Text(_saving ? 'Saving…' : 'Send'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _callBtn(String label, Color c, VoidCallback f) => SizedBox(
    height: 52,
    child: FilledButton(style: FilledButton.styleFrom(backgroundColor: c), onPressed: f, child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
  );
}
