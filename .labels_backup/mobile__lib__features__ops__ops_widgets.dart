// Shared pieces for the staff console. Solid surfaces only (no glass), graphite tokens.
import 'package:flutter/material.dart';

import 'ops_tokens.dart';

class OpsPanel extends StatelessWidget {
  const OpsPanel({super.key, required this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(OT.pad)});
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: OT.panelDecoration(),
    padding: padding,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OT.text, letterSpacing: 0.2))),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

class OpsTag extends StatelessWidget {
  const OpsTag(this.text, {super.key, this.bg, this.fg, this.border});
  final String text;
  final Color? bg;
  final Color? fg;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg ?? OT.raised,
      borderRadius: BorderRadius.circular(7),
      border: border == null ? null : Border.all(color: border!),
    ),
    child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg ?? OT.soft)),
  );
}

class PriorityTag extends StatelessWidget {
  const PriorityTag(this.priority, {super.key});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final c = OT.priority(priority);
    return OpsTag(priority.toUpperCase(), bg: c.withValues(alpha: 0.16), fg: c, border: c.withValues(alpha: 0.55));
  }
}

class OpsKpi extends StatelessWidget {
  const OpsKpi({super.key, required this.label, required this.value, this.hint, this.alert = false, this.selected = false, this.onTap});
  final String label;
  final String value;
  final String? hint;
  final bool alert;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = alert ? OT.alert : OT.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OT.radius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? OT.raised : OT.panel,
          borderRadius: BorderRadius.circular(OT.radius),
          border: Border.all(color: selected ? accent : OT.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: OT.muted)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.05, color: alert ? OT.alert : OT.text)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint!, style: const TextStyle(fontSize: 11, color: OT.muted))),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 34, color: OT.muted),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: OT.soft)),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: OT.muted, height: 1.4)),
        ],
      ]),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 34, color: OT.alert),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: OT.soft, height: 1.4)),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ]),
    ),
  );
}

/// A calm placeholder while the first snapshot arrives. No spinner on the whole page.
class OpsSkeleton extends StatelessWidget {
  const OpsSkeleton({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(OT.pad),
    itemCount: rows,
    itemBuilder: (_, i) => Container(
      height: i == 0 ? 42 : 66,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: OT.raised, borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class OpsSectionHeader extends StatelessWidget {
  const OpsSectionHeader(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(OT.pad, 14, OT.pad, 8),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: OT.text)),
          if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: OT.muted)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]),
  );
}

/// Thin bar for the analytics pages (no chart package).
class OpsBarRow extends StatelessWidget {
  const OpsBarRow({super.key, required this.label, required this.value, required this.max, this.color = OT.accent, this.suffix = ''});
  final String label;
  final num value;
  final num max;
  final Color color;
  final String suffix;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 150, child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: OT.soft))),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final w = max <= 0 ? 0.0 : c.maxWidth * (value / max);
          return Stack(children: [
            Container(height: 10, decoration: BoxDecoration(color: OT.raised, borderRadius: BorderRadius.circular(5))),
            Container(height: 10, width: w.clamp(0.0, c.maxWidth), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
          ]);
        }),
      ),
      SizedBox(width: 74, child: Text('$value$suffix', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: OT.text))),
    ]),
  );
}

class OpsDialogField extends StatelessWidget {
  const OpsDialogField({super.key, required this.controller, required this.label, this.maxLength, this.maxLines = 1, this.error});
  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int maxLines;
  final String? error;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: maxLength,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label, errorText: error, border: const OutlineInputBorder()),
  );
}
