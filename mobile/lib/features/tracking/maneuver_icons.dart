import 'package:flutter/material.dart';

/// Icon for a Directions `maneuver` string. Unknown or null gives a plain navigation arrow.
IconData maneuverIcon(String? maneuver) => switch (maneuver) {
      'turn-left' => Icons.turn_left,
      'turn-right' => Icons.turn_right,
      'turn-slight-left' => Icons.turn_slight_left,
      'turn-slight-right' => Icons.turn_slight_right,
      'turn-sharp-left' => Icons.turn_sharp_left,
      'turn-sharp-right' => Icons.turn_sharp_right,
      'uturn-left' => Icons.u_turn_left,
      'uturn-right' => Icons.u_turn_right,
      'keep-left' || 'fork-left' => Icons.fork_left,
      'keep-right' || 'fork-right' => Icons.fork_right,
      'roundabout-left' => Icons.roundabout_left,
      'roundabout-right' => Icons.roundabout_right,
      'ramp-left' => Icons.ramp_left,
      'ramp-right' => Icons.ramp_right,
      'merge' => Icons.merge,
      'straight' => Icons.straight,
      _ => Icons.navigation,
    };
