/// Plain-language lines for the check-in screen (pure, tested).
String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Headline shown above the timer for a check-in in [status].
String checkinStatusText(
  String status, {
  required DateTime expiry,
  required int graceSec,
  required DateTime now,
}) {
  switch (status) {
    case 'Active':
      return now.isBefore(expiry)
          ? 'Check in before ${_hhmm(expiry)}.'
          : 'Time is up. Check in now.';
    case 'Grace':
      return 'You are overdue. Check in now. Your contacts are alerted at '
          '${_hhmm(expiry.add(Duration(seconds: graceSec)))}.';
    case 'Level1':
      return 'Your contacts have been alerted. Check in now if you are safe.';
    case 'Level2':
      return 'Nusuru responders have been alerted. Check in now if you are safe.';
    default:
      return 'Check-in $status.';
  }
}

/// "30 min", "1 h", "1 h 30 min" for a length in seconds.
String checkinLengthLabel(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// The countdown "mm:ss" or "h:mm:ss"; "00:00" once passed.
String checkinClock(int seconds) {
  if (seconds <= 0) return '00:00';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
