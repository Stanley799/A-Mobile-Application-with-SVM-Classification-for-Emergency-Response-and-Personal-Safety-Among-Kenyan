// Responder SOS: a 2-second press-and-hold (with a progress ring) so it cannot be sent by accident.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'responder_repository.dart';
import 'responder_theme.dart';

class SosHoldButton extends StatefulWidget {
  const SosHoldButton({
    super.key,
    required this.onSend,
    this.hold = const Duration(seconds: 2),
    this.label = 'Hold 2 seconds to send',
  });

  final Future<void> Function() onSend;
  final Duration hold;
  final String label;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.hold,
  )..addStatusListener((status) {
    // animateTo() always reports "completed", even when it runs back to 0, so the value decides.
    if (status == AnimationStatus.completed && _progress.value >= 1) _fire();
  });
  bool _holding = false;
  bool _sent = false;
  bool _sending = false;

  Future<void> _fire() async {
    if (_sent || _sending || !mounted) return;
    setState(() {
      _sent = true;
      _sending = true;
    });
    try {
      await widget.onSend();
    } catch (_) {
      if (mounted) setState(() => _sent = false);
      rethrow;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _cancel() {
    if (!_holding) return;
    _holding = false;
    if (!_sent) _progress.animateTo(0, duration: const Duration(milliseconds: 160));
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        'I need help. Press and hold for ${widget.hold.inSeconds} seconds to alert dispatch.',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (_sent) return;
        _holding = true;
        _progress.forward(from: 0);
      },
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      child: SizedBox(
        width: 164,
        height: 164,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: AnimatedBuilder(
                animation: _progress,
                builder: (_, _) => CircularProgressIndicator(
                  value: _progress.value,
                  strokeWidth: 8,
                  backgroundColor: RC.line,
                  color: RC.alert,
                ),
              ),
            ),
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _sent ? RC.alert : RC.danger,
              ),
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sos_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              _sent ? 'Sent' : widget.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The SOS sheet: hold to send, then the expected confirmation, with 999 and 112 always one tap away.
Future<void> showSosSheet(
  BuildContext context,
  ResponderRepository repo, {
  String? incidentId,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => _SosSheet(repo: repo, incidentId: incidentId),
);

class _SosSheet extends StatefulWidget {
  const _SosSheet({required this.repo, this.incidentId});
  final ResponderRepository repo;
  final String? incidentId;

  @override
  State<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<_SosSheet> {
  bool _sent = false;
  bool _failed = false;

  Future<void> _send() async {
    try {
      await widget.repo.sendSos(incidentId: widget.incidentId);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('I need help', style: ResponderTextStyles.title),
          const SizedBox(height: ResponderSpacing.sm),
          Text(
            'This alerts dispatch and administrators immediately and shows them your last known location.',
            style: ResponderTextStyles.body,
          ),
          const SizedBox(height: ResponderSpacing.xl),
          Center(
            child: SosHoldButton(
              onSend: _send,
              label: _sent ? 'Sent' : 'Hold 2 seconds\nto send',
            ),
          ),
          const SizedBox(height: ResponderSpacing.lg),
          if (_sent)
            const Text(
              'Dispatch has been alerted and can see your last location. Call your supervisor if you can.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RC.accept,
                height: 1.4,
              ),
            )
          else if (_failed)
            const Text(
              'Your SOS was not sent. Call 999 now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RC.alert,
                height: 1.4,
              ),
            )
          else
            const Text(
              'Use this if you are in danger or need another unit now.',
              textAlign: TextAlign.center,
              style: ResponderTextStyles.caption,
            ),
          const SizedBox(height: ResponderSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: RC.danger,
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: '999')),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call 999'),
                ),
              ),
              const SizedBox(width: ResponderSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RC.text,
                    side: const BorderSide(color: RC.outline),
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call 112'),
                ),
              ),
            ],
          ),
          const SizedBox(height: ResponderSpacing.xs),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
  );
}
