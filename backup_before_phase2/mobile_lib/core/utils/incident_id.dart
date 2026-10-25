import 'dart:math';

const String _kAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _categoryCode(String category) {
  switch (category) {
    case 'Medical Emergency':
      return 'MED';
    case 'Road Accident':
      return 'ROAD';
    case 'Fire & Rescue':
      return 'FIRE';
    case 'Security Threat':
      return 'SEC';
    case 'Abduction':
      return 'ABD';
    case 'Other / General':
    default:
      return 'SOS';
  }
}

String newIncidentId({
  required String category,
  DateTime? now,
  Random? random,
}) {
  final dt = now ?? DateTime.now();
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');

  final code = _categoryCode(category);
  final rng = random ?? Random.secure();

  final chars = StringBuffer();
  for (var i = 0; i < 4; i++) {
    chars.write(_kAlphabet[rng.nextInt(_kAlphabet.length)]);
  }

  return '$year$month$day-$hour$minute$second-$code-${chars.toString()}';
}

String incidentReference(String id) {
  final parts = id.split('-');
  if (parts.length >= 4) {
    return parts.last.toUpperCase();
  }
  if (id.length >= 4) {
    return id.substring(id.length - 4).toUpperCase();
  }
  return id.toUpperCase();
}
