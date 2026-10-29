import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/ops/ops_logic.dart';

void main() {
  test('median and 90th percentile skip nulls and report the sample', () {
    final s = sampleStats([null, 30, null, 10, 20]);
    expect(s.sample, 3);
    expect(s.median, 20);
    expect(s.p90, 30);

    final even = sampleStats([10, 21]);
    expect(even.sample, 2);
    expect(even.median, 16); // (10 + 21) / 2 rounded
    expect(even.p90, 21);
  });

  test('a single number is its own median and percentile', () {
    final s = sampleStats([45]);
    expect(s.sample, 1);
    expect(s.median, 45);
    expect(s.p90, 45);
  });

  test('ten numbers: median averages the middle pair, p90 takes the 9th', () {
    final s = sampleStats([for (var i = 1; i <= 10; i++) i]);
    expect(s.median, 6);
    expect(s.p90, 9);
    expect(s.sample, 10);
  });

  test('no data is empty, never zero', () {
    for (final values in [<int?>[], <int?>[null, null]]) {
      final s = sampleStats(values);
      expect(s.sample, 0);
      expect(s.median, isNull);
      expect(s.p90, isNull);
    }
  });

  test('elapsed time reads as mm:ss', () {
    expect(mmss(Duration.zero), '00:00');
    expect(mmss(const Duration(seconds: 41)), '00:41');
    expect(mmss(const Duration(minutes: 12, seconds: 5)), '12:05');
    expect(mmss(const Duration(seconds: -5)), '00:00');
  });
}
