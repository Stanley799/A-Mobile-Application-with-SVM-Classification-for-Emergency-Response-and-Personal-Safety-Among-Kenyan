// Shared graphite tokens for the staff console. Colours come from the approved responder design
// (features/responder/responder_theme.dart) so both staff-facing surfaces match.
import 'package:flutter/material.dart';

import '../responder/responder_theme.dart';

class OT {
  static const bg = RC.bg;
  static const panel = RC.card;
  static const raised = RC.surface2;
  static const line = RC.line;
  static const text = RC.text;
  static const muted = RC.muted;
  static const soft = RC.soft;
  static const accent = RC.accent;
  static const alert = RC.alert;

  static Color priority(String p) => RC.priority(p);

  static const double gap = 12;
  static const double pad = 16;
  static const double radius = 14;

  static BoxDecoration panelDecoration() => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: line),
  );
}

/// The four staff states of a unit, in words.
String unitGroup(String availability, DateTime? lastSeenAt, {DateTime? now}) {
  final seen = lastSeenAt;
  final stale = seen != null && (now ?? DateTime.now()).difference(seen).inSeconds > 120;
  if (stale) return 'Stale GPS';
  return switch (availability) {
    'Available' => 'Available',
    'Busy' => 'On a job',
    _ => 'Offline',
  };
}

const List<String> kUnitGroups = ['Available', 'On a job', 'Stale GPS', 'Offline'];
