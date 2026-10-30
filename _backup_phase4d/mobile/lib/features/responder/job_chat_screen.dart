// Job chat with dispatch. Only dispatch and the units holding this incident can read it; the caller never appears here.
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'responder_repository.dart';
import 'responder_theme.dart';

const List<String> kQuickReplies = [
  'Running late',
  'Scene is safe',
  'Need directions',
  'Patient refused care',
  'Need police at scene',
];

class JobChatScreen extends StatefulWidget {
  const JobChatScreen({
    super.key,
    required this.incidentId,
    required this.repo,
    this.systemLine,
  });
  final String incidentId;
  final ResponderRepository repo;

  /// A one-line note shown above the thread (for example a request for more units).
  final String? systemLine;

  @override
  State<JobChatScreen> createState() => _JobChatScreenState();
}

class _JobChatScreenState extends State<JobChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<({String text, bool failed})> _pending = [];
  bool _sending = false;
  int _retry = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? quick]) async {
    final text = (quick ?? _text.text).trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 500) return;
    setState(() {
      _sending = true;
      _pending.add((text: text, failed: false));
      if (quick == null) _text.clear();
    });
    _scrollToEnd();
    try {
      await widget.repo.sendMessage(widget.incidentId, text);
      if (mounted) setState(() => _pending.removeWhere((p) => p.text == text && !p.failed));
    } catch (_) {
      if (mounted) {
        setState(() {
          final i = _pending.indexWhere((p) => p.text == text && !p.failed);
          if (i >= 0) _pending[i] = (text: text, failed: true);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.repo.uid;
    return Scaffold(
      backgroundColor: RC.bg,
      appBar: AppBar(
        backgroundColor: RC.bg,
        foregroundColor: RC.text,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Dispatch chat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
              'Only dispatchers and your unit can read this',
              style: TextStyle(fontSize: 12, color: RC.muted),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.systemLine != null) _SystemLine(widget.systemLine!),
            Expanded(
              child: StreamBuilder<List<JobMessage>>(
                key: ValueKey(_retry),
                stream: widget.repo.watchMessages(widget.incidentId),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _ChatError(
                      onRetry: () => setState(() => _retry++),
                    );
                  }
                  final messages = snap.data ?? const <JobMessage>[];
                  if (snap.connectionState == ConnectionState.waiting &&
                      messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (messages.isEmpty && _pending.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No messages yet. Use a quick reply below or write to dispatch.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: RC.muted, height: 1.5),
                        ),
                      ),
                    );
                  }
                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      for (final m in messages)
                        _Bubble(
                          text: m.text,
                          mine: m.senderUid == uid,
                          time: m.at,
                        ),
                      for (final p in _pending)
                        _Bubble(
                          text: p.text,
                          mine: true,
                          pending: !p.failed,
                          failed: p.failed,
                          onRetry: p.failed ? () => _retrySend(p.text) : null,
                        ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              height: 44,
              child: _QuickReplyRow(enabled: !_sending, onTap: _send),
            ),
            _Composer(
              controller: _text,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retrySend(String text) async {
    setState(() => _pending.removeWhere((p) => p.text == text && p.failed));
    await _send(text);
  }
}

class _QuickReplyRow extends StatelessWidget {
  const _QuickReplyRow({required this.enabled, required this.onTap});
  final bool enabled;
  final void Function(String text)? onTap;

  @override
  Widget build(BuildContext context) => ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    children: [
      for (final reply in kQuickReplies)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            label: Text(reply),
            onPressed: enabled ? () => onTap?.call(reply) : null,
            backgroundColor: RC.surface2,
            side: const BorderSide(color: RC.line),
            labelStyle: const TextStyle(color: RC.soft, fontSize: 12.5),
          ),
        ),
    ],
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: const BoxDecoration(
      color: RC.card,
      border: Border(top: BorderSide(color: RC.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: RC.text, fontSize: 15),
            onSubmitted: (_) => onSend(),
            decoration: const InputDecoration(
              hintText: 'Message dispatch',
              hintStyle: TextStyle(color: RC.muted),
              counterText: '',
              filled: true,
              fillColor: RC.surface2,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderSide: BorderSide(color: RC.line)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send',
          onPressed: sending ? null : onSend,
          style: IconButton.styleFrom(
            backgroundColor: RC.accept,
            foregroundColor: const Color(0xFF04130C),
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    this.time,
    this.pending = false,
    this.failed = false,
    this.onRetry,
  });
  final String text;
  final bool mine;
  final DateTime? time;
  final bool pending;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 300),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mine ? RC.needBg : RC.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: mine ? RC.needFg : RC.text,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
          if (pending)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Sending…', style: TextStyle(fontSize: 11, color: RC.muted)),
            )
          else if (failed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Not sent.',
                  style: TextStyle(fontSize: 11, color: RC.alert),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text('Retry', style: TextStyle(fontSize: 11)),
                ),
              ],
            )
          else if (time != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10.5, color: RC.muted),
              ),
            ),
        ],
      ),
    ),
  );
}

class _SystemLine extends StatelessWidget {
  const _SystemLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: RC.surface2,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12.5, color: RC.soft, height: 1.3),
    ),
  );
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Chat could not be loaded. Check your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RC.soft),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
