import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/status/location_confidence.dart';

void main() {
  group('accuracyWords', () {
    test('under 30 m reads as accurate', () {
      expect(accuracyWords(15), 'Accurate to about 15 m');
      expect(accuracyWords(0), 'Accurate to about 0 m');
    });

    test('30 to 150 m reads as approximate', () {
      expect(accuracyWords(30), 'Approximate, about 30 m');
      expect(accuracyWords(120), 'Approximate, about 120 m');
      expect(accuracyWords(150), 'Approximate, about 150 m');
    });

    test('over 150 m asks for a landmark', () {
      expect(accuracyWords(400), 'Low accuracy, about 400 m. Add a landmark.');
    });

    test('no fix means no sentence', () {
      expect(accuracyWords(null), isNull);
      expect(accuracyWords(double.nan), isNull);
      expect(accuracyWords(double.infinity), isNull);
    });
  });

  group('accuracyShort', () {
    test('the responder job card wording', () {
      expect(accuracyShort(12), 'Location accurate to about 12 m');
      expect(accuracyShort(400), 'Location approximate, 400 m');
      expect(accuracyShort(null), isNull);
    });
  });
}
