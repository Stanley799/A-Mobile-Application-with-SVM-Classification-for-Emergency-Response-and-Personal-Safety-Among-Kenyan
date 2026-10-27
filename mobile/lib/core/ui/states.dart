// What a screen shows while it waits, when it is empty, and when it fails. Every list or stream in the app uses AppStream so no screen is ever blank.
import 'package:flutter/material.dart';

import 'app_button.dart';
import 'feedback.dart';
import 'tokens.dart';

/// Grey shimmer block. Calm: one soft sweep every 1.4 s.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(begin: Alignment(-1 + 2 * _c.value, 0), end: Alignment(1 + 2 * _c.value, 0), colors: const [Color(0xFFE9E6E0), Color(0xFFF6F4F0), Color(0xFFE9E6E0)]),
      ),
    ),
  );
}

/// A few card-shaped skeleton rows, for lists.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 4});
  final int rows;

  @override
  Widget build(BuildContext context) => Column(children: [
    for (var i = 0; i < rows; i++)
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Tk.rCard)),
        child: const Row(children: [
          Skeleton(width: 44, height: 44, radius: 22),
          SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 160, height: 14), SizedBox(height: 10), Skeleton(height: 12)])),
        ]),
      ),
  ]);
}

/// Centered spinner with words. Words matter: "Signing you in…" is better than a bare wheel.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: Tk.brand)),
        if (label != null) ...[const SizedBox(height: 14), Text(label!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Tk.mute))],
      ]),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76, decoration: const BoxDecoration(color: Tk.brandTint, shape: BoxShape.circle), child: Icon(icon, size: 34, color: Tk.brandDeep)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Tk.ink)),
        if (body != null) ...[const SizedBox(height: 8), Text(body!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.mute))],
        if (actionLabel != null && onAction != null) ...[const SizedBox(height: 18), AppButton(label: actionLabel!, onPressed: onAction, expand: false, kind: AppButtonKind.secondary)],
      ]),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.message, this.onRetry});
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'We could not load this',
    body: message ?? 'Check your connection and try again.',
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// StreamBuilder with the three states done properly: loading skeleton, friendly error with retry, empty message.
class AppStream<T> extends StatelessWidget {
  const AppStream({super.key, required this.stream, required this.builder, this.isEmpty, this.empty, this.loading, this.onRetry});
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: stream,
    builder: (context, snap) {
      if (snap.hasError) return ErrorState(message: friendlyError(snap.error!), onRetry: onRetry);
      if (!snap.hasData) return loading ?? const Padding(padding: EdgeInsets.all(16), child: SkeletonList());
      final d = snap.data as T;
      if (isEmpty != null && isEmpty!(d) && empty != null) return empty!;
      return builder(context, d);
    },
  );
}
