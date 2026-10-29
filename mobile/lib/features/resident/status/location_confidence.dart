// How precise the caller's location is, in words. Three bands; no raw metres-only figure and no jargon.
import 'dart:math' as math;

/// The accuracy sentence shown under the street name. null when there is no location yet.
String? accuracyWords(double? metres) {
  if (metres == null || metres.isNaN || metres.isInfinite) return null;
  final m = math.max(0, metres).round();
  if (m < 30) return 'Accurate to about $m m';
  if (m <= 150) return 'Approximate, about $m m';
  return 'Low accuracy, about $m m. Add a landmark.';
}

/// Short form used on a responder's job card. null when unknown.
String? accuracyShort(double? metres) {
  if (metres == null || metres.isNaN || metres.isInfinite) return null;
  if (metres < 30) return 'Location accurate to about ${math.max(0, metres).round()} m';
  return 'Location approximate, ${math.max(0, metres).round()} m';
}
