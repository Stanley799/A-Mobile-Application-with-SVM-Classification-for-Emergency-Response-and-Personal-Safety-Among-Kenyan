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
  group('summary and timeline', () {
    test('summary reads naturally', () {
      expect(checkinSummary(lengthMin: 30, remindMin: 5, contacts: 2, responders: true), '30 min · reminder 5 min before · 2 contacts · responders on');
      expect(checkinSummary(lengthMin: 60, remindMin: 0, contacts: 0, responders: false), '1 h · no reminder · no contacts · responders off');
      expect(checkinSummary(lengthMin: 15, remindMin: 10, contacts: 1, responders: true), contains('1 contact '));
    });
    test('timeline has deadline, contacts, then responders 15 min later', () {
      final steps = checkinTimeline(expiry: expiry, graceSec: 300, level2AfterSec: 900, contactNames: ['Mum', 'Brian'], responders: true);
      expect(steps.length, 3);
      expect(checkinHhmm(steps[0].at), '14:30');
      expect(checkinHhmm(steps[1].at), '14:35');
      expect(steps[1].text, 'Contacts are told: Mum, Brian.');
      expect(checkinHhmm(steps[2].at), '14:50');
    });
    test('timeline drops responders when off and says when nobody is told', () {
      final steps = checkinTimeline(expiry: expiry, graceSec: 300, level2AfterSec: 900, contactNames: [], responders: false);
      expect(steps.length, 2);
      expect(steps[1].text, 'No contacts to tell.');
    });
  });
}
