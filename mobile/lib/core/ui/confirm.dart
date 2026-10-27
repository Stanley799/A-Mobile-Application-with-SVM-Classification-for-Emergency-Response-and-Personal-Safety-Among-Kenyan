// Confirmation for actions that matter (sign out, cancel an alert). Calm wording, one clear safe choice, one clear risky choice.
import 'package:flutter/material.dart';

import 'app_button.dart';
import 'tokens.dart';

Future<bool> confirmAction(BuildContext context, {required String title, required String message, required String confirmLabel, String cancelLabel = 'Stay', bool danger = false}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Tk.rSheet))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tk.line, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Tk.ink)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 15, height: 1.45, color: Tk.mute)),
          const SizedBox(height: 20),
          AppButton(label: confirmLabel, kind: danger ? AppButtonKind.danger : AppButtonKind.primary, onPressed: () => Navigator.of(c).pop(true)),
          const SizedBox(height: 10),
          AppButton(label: cancelLabel, kind: AppButtonKind.secondary, onPressed: () => Navigator.of(c).pop(false)),
        ]),
      ),
    ),
  );
  return r ?? false;
}
