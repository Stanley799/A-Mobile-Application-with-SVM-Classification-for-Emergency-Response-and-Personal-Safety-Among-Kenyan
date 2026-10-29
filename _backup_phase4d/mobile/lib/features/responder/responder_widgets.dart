import 'package:flutter/material.dart';

import 'responder_theme.dart';

class PriorityTag extends StatelessWidget {
  const PriorityTag({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final (label, icon, fill, ink) = switch (priority) {
      'High' => (
        'HIGH',
        Icons.priority_high,
        RC.alert,
        const Color(0xFF1A0503),
      ),
      'Medium' => (
        'MEDIUM',
        Icons.warning_amber_rounded,
        RC.medium,
        const Color(0xFF1A1000),
      ),
      'Low' => ('LOW', Icons.south_rounded, RC.low, const Color(0xFF021426)),
      _ => ('PRIORITY UNKNOWN', Icons.help_outline, RC.surface2, RC.text),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(ResponderRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: ResponderSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 82),
    padding: const EdgeInsets.all(ResponderSpacing.md),
    decoration: BoxDecoration(
      color: RC.surface2,
      borderRadius: BorderRadius.circular(ResponderRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: RC.accent),
              const SizedBox(width: ResponderSpacing.xs),
            ],
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: RC.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ResponderSpacing.xs),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ResponderTextStyles.caption,
        ),
      ],
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: ResponderSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: RC.muted),
          const SizedBox(width: ResponderSpacing.md),
        ],
        SizedBox(
          width: icon == null ? 112 : 96,
          child: Text(label, style: ResponderTextStyles.caption),
        ),
        Expanded(child: Text(value, style: ResponderTextStyles.body)),
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: ResponderSpacing.md),
    padding: const EdgeInsets.all(ResponderSpacing.lg),
    decoration: BoxDecoration(
      color: RC.card,
      borderRadius: BorderRadius.circular(ResponderRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: ResponderTextStyles.section)),
            ?trailing,
          ],
        ),
        const SizedBox(height: ResponderSpacing.md),
        child,
      ],
    ),
  );
}

class PrimaryActionBar extends StatelessWidget {
  const PrimaryActionBar({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(
        ResponderSpacing.lg,
        ResponderSpacing.md,
        ResponderSpacing.lg,
        ResponderSpacing.md,
      ),
      decoration: BoxDecoration(
        color: RC.bg,
        border: Border(top: BorderSide(color: RC.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 64, child: primary),
          if (secondary != null) ...[
            const SizedBox(height: ResponderSpacing.sm),
            SizedBox(height: 52, child: secondary),
          ],
        ],
      ),
    ),
  );
}

enum ReadinessState {
  offDuty,
  onDuty,
  onJob,
  locationOff,
  gpsStale,
  noConnection,
}

class ReadinessBar extends StatelessWidget {
  const ReadinessBar({
    super.key,
    required this.state,
    this.lastFixAt,
    this.accuracyMeters,
    this.capabilities = const [],
    this.onRetryGps,
  });

  final ReadinessState state;
  final DateTime? lastFixAt;
  final double? accuracyMeters;
  final List<String> capabilities;
  final VoidCallback? onRetryGps;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      ReadinessState.offDuty => (
        'OFF DUTY',
        RC.muted,
        Icons.pause_circle_outline,
      ),
      ReadinessState.onDuty => (
        'ON DUTY · RECEIVING ALERTS',
        RC.accept,
        Icons.check_circle_outline,
      ),
      ReadinessState.onJob => ('ON A JOB', RC.medium, Icons.emergency_outlined),
      ReadinessState.locationOff => (
        'NOT RECEIVING · LOCATION OFF',
        RC.alert,
        Icons.location_off_outlined,
      ),
      ReadinessState.gpsStale => (
        'NOT RECEIVING · GPS SIGNAL OLD',
        RC.alert,
        Icons.gps_off,
      ),
      ReadinessState.noConnection => (
        'NO CONNECTION',
        RC.alert,
        Icons.cloud_off_outlined,
      ),
    };
    final age = lastFixAt == null
        ? null
        : DateTime.now().difference(lastFixAt!).inSeconds.clamp(0, 999999);
    final shownCaps = capabilities.take(3).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ResponderSpacing.md),
      decoration: BoxDecoration(
        color: RC.card,
        border: Border(bottom: BorderSide(color: RC.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: ResponderSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              if (state == ReadinessState.gpsStale && onRetryGps != null)
                TextButton(
                  onPressed: onRetryGps,
                  child: const Text('Retry GPS'),
                ),
            ],
          ),
          if (state == ReadinessState.onDuty ||
              state == ReadinessState.gpsStale ||
              state == ReadinessState.onJob) ...[
            const SizedBox(height: ResponderSpacing.xs),
            Text(
              'Keep the app open to receive alerts. Dispatch only sees you while your GPS is fresh.',
              style: ResponderTextStyles.caption,
            ),
            if (age != null)
              Text(
                'GPS fix ${age}s ago${accuracyMeters == null ? '' : ' · ±${accuracyMeters!.round()} m'}',
                style: ResponderTextStyles.caption,
              ),
          ],
          if (shownCaps.isNotEmpty) ...[
            const SizedBox(height: ResponderSpacing.sm),
            Wrap(
              spacing: ResponderSpacing.xs,
              runSpacing: ResponderSpacing.xs,
              children: [
                for (final capability in shownCaps) _CapabilityChip(capability),
                if (capabilities.length > shownCaps.length)
                  _CapabilityChip('+${capabilities.length - shownCaps.length}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: RC.surface2,
      borderRadius: BorderRadius.circular(ResponderRadius.chip),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        color: RC.text,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
  });

  final int secondsLeft;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final seconds = secondsLeft.clamp(0, totalSeconds);
    final warning = seconds <= 5
        ? RC.alert
        : seconds <= 15
        ? RC.medium
        : RC.accent;
    final announcement = seconds == 30 || seconds == 15 || seconds == 5;
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      liveRegion: announcement,
      label: announcement ? '$seconds seconds remaining' : null,
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: totalSeconds == 0 ? 0 : seconds / totalSeconds,
                strokeWidth: 8,
                backgroundColor: RC.line,
                color: warning,
              ),
            ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: RC.text,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text('remaining', style: ResponderTextStyles.caption),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
