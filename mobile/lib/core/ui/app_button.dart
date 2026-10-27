// The one button for the whole app. If onPressed returns a Future, the button disables itself, shows a spinner in place of the label
// (the width never jumps) and ignores extra taps until the work finishes. This is what stops "I tapped and nothing happened".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

enum AppButtonKind { primary, secondary, danger, ghost }

class AppButton extends StatefulWidget {
  const AppButton({super.key, required this.label, required this.onPressed, this.kind = AppButtonKind.primary, this.icon, this.expand = true, this.loading = false, this.height = 52, this.busyLabel});
  final String label;
  final FutureOr<void> Function()? onPressed; // null = disabled
  final AppButtonKind kind;
  final IconData? icon;
  final bool expand;
  final bool loading; // set from outside when the busy state is owned by the parent
  final double height;
  final String? busyLabel; // optional words next to the spinner, e.g. "Signing in…"

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _busy = false;
  bool _down = false;

  bool get _disabled => widget.onPressed == null;
  bool get _working => _busy || widget.loading;

  Future<void> _tap() async {
    if (_disabled || _working) return;
    HapticFeedback.selectionClick();
    final r = widget.onPressed!();
    if (r is Future) {
      setState(() => _busy = true);
      try {
        await r;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  (Color bg, Color fg, Color? border) get _colors => switch (widget.kind) {
    AppButtonKind.primary => (Tk.brand, Colors.white, null),
    AppButtonKind.danger => (Tk.danger, Colors.white, null),
    AppButtonKind.secondary => (Colors.white, Tk.brandDeep, Tk.line),
    AppButtonKind.ghost => (Colors.transparent, Tk.brandDeep, null),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _colors;
    final label = _working && widget.busyLabel != null ? widget.busyLabel! : widget.label;
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      if (_working) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg)) else if (widget.icon != null) Icon(widget.icon, size: 20, color: fg),
      if (_working || widget.icon != null) const SizedBox(width: 10),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg))),
    ]);
    return Semantics(
      button: true,
      enabled: !_disabled && !_working,
      label: widget.label,
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down && !_disabled ? 0.97 : 1,
          duration: Tk.fast,
          curve: Tk.settle,
          child: AnimatedOpacity(
            opacity: _disabled ? 0.45 : 1,
            duration: Tk.fast,
            child: SizedBox(
              height: widget.height,
              width: widget.expand ? double.infinity : null,
              child: Material(
                color: bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: border == null ? BorderSide.none : BorderSide(color: border)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _disabled ? null : _tap,
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Center(child: content)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
