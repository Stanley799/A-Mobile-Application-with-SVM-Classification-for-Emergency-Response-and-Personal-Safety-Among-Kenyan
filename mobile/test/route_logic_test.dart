import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tracking/maneuver_icons.dart';
import 'package:mobile/features/tracking/route_logic.dart';

const a = LatLngPoint(-1.2900, 36.8200);
const b = LatLngPoint(-1.2800, 36.8200);
const route = <LatLngPoint>[a, b];
const vector = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

RouteStep step(double dist, {String? poly}) =>
    RouteStep(instruction: 'x', maneuver: null, distanceM: dist, durationSec: 10, polyline: poly);

void main() {
  group('polyline', () {
    test('decodes the reference vector', () {
      final p = decodePolyline(vector);
      expect(p.length, 3);
      expect(p[0].lat, closeTo(38.5, 1e-9));
      expect(p[0].lng, closeTo(-120.2, 1e-9));
      expect(p[1].lat, closeTo(40.7, 1e-9));
      expect(p[1].lng, closeTo(-120.95, 1e-9));
      expect(p[2].lat, closeTo(43.252, 1e-9));
      expect(p[2].lng, closeTo(-126.453, 1e-9));
    });

    test('empty and malformed never throw', () {
      expect(decodePolyline(''), isEmpty);
      expect(() => decodePolyline('@@@'), returnsNormally);
      expect(decodePolyline('\u0001\u0002'), isEmpty);
    });

    test('encode gives the reference string exactly', () {
      expect(encodePolyline(const [LatLngPoint(38.5, -120.2), LatLngPoint(40.7, -120.95), LatLngPoint(43.252, -126.453)]), vector);
    });

    test('encode then decode returns 50 random points', () {
      final rnd = math.Random(7);
      final pts = <LatLngPoint>[
        for (var i = 0; i < 50; i++)
          LatLngPoint(
            double.parse((rnd.nextDouble() * 160 - 80).toStringAsFixed(5)),
            double.parse((rnd.nextDouble() * 358 - 179).toStringAsFixed(5)),
          ),
      ];
      final back = decodePolyline(encodePolyline(pts));
      expect(back.length, pts.length);
      for (var i = 0; i < pts.length; i++) {
        expect(back[i].lat, closeTo(pts[i].lat, 1e-9));
        expect(back[i].lng, closeTo(pts[i].lng, 1e-9));
      }
    });
  });

  group('snapping', () {
    test('route length', () => expect(routeLengthM(route), closeTo(1111.9, 1)));

    test('a point beside the route', () {
      final s = snapToRoute(route, -1.2850, 36.8203)!;
      expect(s.crossTrackM, closeTo(33.35, 0.5));
      expect(s.alongM, closeTo(556, 1.5));
      expect(remainingMeters(route, s), closeTo(556, 1.5));
    });

    test('a point on the route has no cross-track', () {
      expect(snapToRoute(route, -1.2850, 36.8200)!.crossTrackM, lessThan(0.5));
    });

    test('beyond the ends snaps to the ends', () {
      expect(snapToRoute(route, -1.2700, 36.8200)!.alongM, closeTo(routeLengthM(route), 1e-6));
      expect(snapToRoute(route, -1.3000, 36.8200)!.alongM, closeTo(0, 1e-6));
    });

    test('empty route gives null', () => expect(snapToRoute(const [], 0, 0), isNull));

    test('trimRoute drops the travelled part', () {
      final r = <LatLngPoint>[a, const LatLngPoint(-1.2850, 36.8200), b];
      final s = snapToRoute(r, -1.2830, 36.8200)!;
      final t = trimRoute(r, s);
      expect(t.first.lat, closeTo(-1.2830, 1e-6));
      expect(t.length, 2);
      expect(t.last, b);
    });
  });

  group('off route', () {
    final t0 = DateTime(2026, 1, 1, 10);

    test('three bad fixes fire, not before', () {
      final m = OffRouteMonitor();
      expect(m.onFix(now: t0, crossTrackM: 40, accuracyM: 10), isFalse);
      expect(m.onFix(now: t0, crossTrackM: 40, accuracyM: 10), isFalse);
      expect(m.onFix(now: t0, crossTrackM: 40, accuracyM: 10), isTrue);
    });

    test('a good fix resets the count', () {
      final m = OffRouteMonitor();
      m.onFix(now: t0, crossTrackM: 40, accuracyM: 10);
      m.onFix(now: t0, crossTrackM: 40, accuracyM: 10);
      m.onFix(now: t0, crossTrackM: 10, accuracyM: 10);
      expect(m.onFix(now: t0, crossTrackM: 40, accuracyM: 10), isFalse);
      expect(m.onFix(now: t0, crossTrackM: 40, accuracyM: 10), isFalse);
    });

    test('after a reroute it stays quiet for 20 seconds', () {
      final m = OffRouteMonitor()..markRerouted(t0);
      for (var i = 0; i < 5; i++) {
        expect(m.onFix(now: t0.add(const Duration(seconds: 5)), crossTrackM: 60, accuracyM: 10), isFalse);
      }
      expect(m.onFix(now: t0.add(const Duration(seconds: 21)), crossTrackM: 60, accuracyM: 10), isTrue);
    });

    test('poor accuracy widens the limit', () {
      final m = OffRouteMonitor();
      for (var i = 0; i < 4; i++) {
        expect(m.onFix(now: t0, crossTrackM: 60, accuracyM: 80), isFalse);
      }
    });
  });

  group('eta and arrival', () {
    test('eta from what remains', () {
      expect(etaFromRemaining(remainingM: 1250, routeDistM: 2500, routeDurSec: 300), 150);
      expect(etaFromRemaining(remainingM: 0, routeDistM: 2500, routeDurSec: 300), 0);
      expect(etaFromRemaining(remainingM: 100, routeDistM: 0, routeDurSec: 0), isNull);
    });

    test('arrival is only suggested when close and slow', () {
      expect(arrivalSuggested(distToTargetM: 30, speedMps: 1), isTrue);
      expect(arrivalSuggested(distToTargetM: 30, speedMps: 5), isFalse);
      expect(arrivalSuggested(distToTargetM: 60, speedMps: 1), isFalse);
      expect(arrivalSuggested(distToTargetM: 70, speedMps: 1, accuracyM: 60), isTrue);
      expect(arrivalSuggested(distToTargetM: 90, speedMps: 1, accuracyM: 500), isFalse);
    });
  });

  group('steps', () {
    test('next step uses cumulative ends', () {
      final steps = withCumulativeEnds([step(100), step(200), step(50)]);
      expect(nextStep(steps, 0)!.distToStepEndM, closeTo(100, 1e-9));
      expect(nextStep(steps, 150)!.step.endAlongM, closeTo(300, 1e-9));
      expect(nextStep(steps, 150)!.distToStepEndM, closeTo(150, 1e-9));
      expect(nextStep(steps, 999), isNull);
    });

    test('route from steps joins and drops the repeated joint', () {
      final p1 = encodePolyline(const [LatLngPoint(-1.0, 36.0), LatLngPoint(-1.001, 36.0), LatLngPoint(-1.002, 36.0)]);
      final p2 = encodePolyline(const [LatLngPoint(-1.002, 36.0), LatLngPoint(-1.003, 36.0), LatLngPoint(-1.004, 36.0), LatLngPoint(-1.005, 36.0)]);
      expect(routeFromSteps([step(1, poly: p1), step(1, poly: p2)]).length, 6);
    });

    test('a step without a line is skipped, none at all gives empty', () {
      final p1 = encodePolyline(const [LatLngPoint(-1.0, 36.0), LatLngPoint(-1.001, 36.0)]);
      expect(routeFromSteps([step(1), step(1, poly: p1)]).length, 2);
      expect(routeFromSteps([step(1), step(1)]), isEmpty);
    });
  });

  group('sharing the route', () {
    final long7999 = 'a' * 7999;
    final long8001 = 'a' * 8001;
    final short = 'b' * 500;

    test('picks the full route when it fits', () => expect(chooseRouteForSharing(fullEncoded: long7999, overviewEncoded: short), long7999));
    test('falls back to the overview', () => expect(chooseRouteForSharing(fullEncoded: long8001, overviewEncoded: short), short));
    test('nothing fits', () => expect(chooseRouteForSharing(fullEncoded: long8001, overviewEncoded: long8001), isNull));
    test('no full route', () => expect(chooseRouteForSharing(overviewEncoded: short), short));
  });

  group('slices', () {
    test('first half', () {
      final s = routeSlice(route, 0, 556);
      expect(s.length, 2);
      final mid = pointAtAlong(route, 556);
      expect(distanceMeters(s.last, mid), lessThan(1.5));
    });

    test('reversed gives one point', () => expect(routeSlice(route, 556, 0).length, 1));
    test('out of range gives the whole route', () => expect(routeSlice(route, -50, 99999), route));
  });

  group('zoom', () {
    test('by speed', () {
      expect(zoomForSpeed(speedMps: 0), 17.5);
      expect(zoomForSpeed(speedMps: 3.0), 17.0);
      expect(zoomForSpeed(speedMps: 5), 17.0);
      expect(zoomForSpeed(speedMps: 8.0), 16.3);
      expect(zoomForSpeed(speedMps: 10), 16.3);
      expect(zoomForSpeed(speedMps: 15.0), 15.6);
      expect(zoomForSpeed(speedMps: 20), 15.6);
    });

    test('near the target or a turn', () {
      expect(zoomForSpeed(speedMps: 20, distToTargetM: 150), 17.5);
      expect(zoomForSpeed(speedMps: 12, distToStepEndM: 100), 17.0);
      expect(zoomForSpeed(speedMps: 12, distToStepEndM: 400), 16.3);
    });
  });

  group('maneuver icons', () {
    test('known and unknown', () {
      expect(maneuverIcon('turn-left'), Icons.turn_left);
      expect(maneuverIcon('keep-right'), Icons.fork_right);
      expect(maneuverIcon('roundabout-left'), Icons.roundabout_left);
      expect(maneuverIcon('something-new'), Icons.navigation);
      expect(maneuverIcon(null), Icons.navigation);
    });
  });
}
