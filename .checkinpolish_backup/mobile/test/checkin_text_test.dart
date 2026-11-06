import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/screens/checkin_text.dart';

void main() {
  final expiry = DateTime(2026, 11, 6, 14, 30);
  group('checkinStatusText', () {
    test('Active before the deadline names the time', () {
      expect(checkinStatusText('Active', expiry: expiry, graceSec: 300, now: DateTime(2026, 11, 6, 14, 0)), 'Check in before 14:30.');
    });
    test('Active just after the deadline says time is up', () {
      expect(checkinStatusText('Active', expiry: expiry, graceSec: 300, now: DateTime(2026, 11, 6, 14, 30, 5)), 'Time is up. Check in now.');
    });
    test('Grace says when contacts will be alerted (deadline + grace)', () {
      expect(checkinStatusText('Grace', expiry: expiry, graceSec: 300, now: expiry), contains('14:35'));
    });
    test('Level1 and Level2 say who has been alerted', () {
      expect(checkinStatusText('Level1', expiry: expiry, graceSec: 300, now: expiry), contains('contacts have been alerted'));
      expect(checkinStatusText('Level2', expiry: expiry, graceSec: 300, now: expiry), contains('responders have been alerted'));
    });
    test('unknown status is still readable', () {
      expect(checkinStatusText('Closed', expiry: expiry, graceSec: 300, now: expiry), 'Check-in Closed.');
    });
  });
  group('labels', () {
    test('length labels', () {
      expect(checkinLengthLabel(900), '15 min');
      expect(checkinLengthLabel(3600), '1 h');
      expect(checkinLengthLabel(5400), '1 h 30 min');
    });
    test('clock', () {
      expect(checkinClock(-5), '00:00');
      expect(checkinClock(65), '01:05');
      expect(checkinClock(3725), '1:02:05');
    });
  });
}
