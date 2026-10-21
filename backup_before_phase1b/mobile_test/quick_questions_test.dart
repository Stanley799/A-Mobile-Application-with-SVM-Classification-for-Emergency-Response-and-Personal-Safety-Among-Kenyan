import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/triage/triage_schema.dart';

void main() {
  group('kQuickQuestions', () {
    test('has exactly the six categories of kCategoryQuestions', () {
      expect(
        kQuickQuestions.keys.toSet(),
        equals(kCategoryQuestions.keys.toSet()),
      );
    });

    test('each list has 1 to 3 unique question IDs belonging to that category', () {
      for (final entry in kQuickQuestions.entries) {
        final cat = entry.key;
        final qq = entry.value;
        expect(qq.length, greaterThanOrEqualTo(1));
        expect(qq.length, lessThanOrEqualTo(3));
        expect(qq.toSet().length, equals(qq.length));

        final categoryQuestions = kCategoryQuestions[cat]!;
        for (final qId in qq) {
          expect(categoryQuestions.contains(qId), isTrue);
          final question = kQuestions[qId];
          expect(question, isNotNull);
          expect(question!.askIf, isEmpty);
        }
      }
    });

    test('has exact lists from Step 2.4', () {
      expect(
        kQuickQuestions['Medical Emergency'],
        equals(['conscious', 'breathing', 'severe_bleeding']),
      );
      expect(
        kQuickQuestions['Road Accident'],
        equals(['trapped', 'hazard', 'conscious']),
      );
      expect(
        kQuickQuestions['Fire & Rescue'],
        equals(['conscious', 'trapped', 'breathing']),
      );
      expect(
        kQuickQuestions['Security Threat'],
        equals(['conscious', 'breathing', 'severe_bleeding']),
      );
      expect(
        kQuickQuestions['Abduction'],
        equals(['immediate_danger', 'weapon_involved', 'age_group']),
      );
      expect(
        kQuickQuestions['Other / General'],
        equals(['conscious', 'breathing', 'severe_bleeding']),
      );
    });
  });
}
