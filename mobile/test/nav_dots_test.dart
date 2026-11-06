import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tracking/nav_logic.dart';
import 'package:mobile/features/tracking/route_logic.dart';

void main() {
  group('dotted route', () {
    test('path length matches the known distance of 0.01 degree of latitude', () {
      final m = pathLengthM(const [LatLngPoint(-1.29, 36.82), LatLngPoint(-1.28, 36.82)]);
      expect(m, closeTo(1111.95, 1.0));
    });
    test('empty and single-point paths have no length', () {
      expect(pathLengthM(const []), 0);
      expect(pathLengthM(const [LatLngPoint(-1.29, 36.82)]), 0);
    });
    test('dots only for a short remaining path', () {
      const near = [LatLngPoint(-1.2900, 36.8200), LatLngPoint(-1.2910, 36.8200)];
      const far = [LatLngPoint(-1.2900, 36.8200), LatLngPoint(-1.2800, 36.8200)];
      expect(useDottedRoute(near), isTrue);
      expect(useDottedRoute(far), isFalse);
      expect(useDottedRoute(const []), isFalse);
    });
  });
}
