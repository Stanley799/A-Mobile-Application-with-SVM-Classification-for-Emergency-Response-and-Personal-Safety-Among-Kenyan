import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/priority_classifier.dart';

void main() {
  test('PriorityClassifier instance initializes and returns failSafe when not loaded', () {
    final result = PriorityClassifier.instance.classify(
      category: 'Medical Emergency',
      answers: {},
    );
    expect(result.priority, equals('High'));
    expect(result.needsHumanReview, isTrue);
  });
}
