import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/widgets/alert_status_sheet.dart';

void main() {
  group('alertPhase truth table', () {
    test('failed beats everything', () {
      final res = alertPhase(
        createDone: true,
        createFailed: true,
        hasPendingWrites: false,
        docSeen: true,
        secondsSinceStart: 10,
      );
      expect(res, equals(AlertPhase.failed));
    });

    test('recorded when createDone is true', () {
      final res = alertPhase(
        createDone: true,
        createFailed: false,
        hasPendingWrites: true,
        docSeen: false,
        secondsSinceStart: 2,
      );
      expect(res, equals(AlertPhase.recorded));
    });

    test('recorded when docSeen is true and hasPendingWrites is false', () {
      final res = alertPhase(
        createDone: false,
        createFailed: false,
        hasPendingWrites: false,
        docSeen: true,
        secondsSinceStart: 3,
      );
      expect(res, equals(AlertPhase.recorded));
    });

    test('savedOffline when secondsSinceStart >= 8 and not recorded', () {
      final res = alertPhase(
        createDone: false,
        createFailed: false,
        hasPendingWrites: true,
        docSeen: false,
        secondsSinceStart: 8,
      );
      expect(res, equals(AlertPhase.savedOffline));
    });

    test('sending otherwise', () {
      final res = alertPhase(
        createDone: false,
        createFailed: false,
        hasPendingWrites: true,
        docSeen: false,
        secondsSinceStart: 5,
      );
      expect(res, equals(AlertPhase.sending));
    });
  });
}
