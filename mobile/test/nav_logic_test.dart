import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tracking/nav_logic.dart';
import 'package:mobile/features/tracking/nav_styles.dart';
import 'package:mobile/features/tracking/route_logic.dart';
import 'package:mobile/features/tracking/track_logic.dart';

const a = LatLngPoint(-1.2900, 36.8200);
const b = LatLngPoint(-1.2800, 36.8200);
const route = <LatLngPoint>[a, b];

RouteStep step(double dist) => RouteStep(instruction: 'x', maneuver: null, distanceM: dist, durationSec: 10);

void main() {
  group('style by zoom', () {
    test('detail switches on at 16', () {
      expect(styleForZoom(15.99, NavMapStyle.overview), NavMapStyle.overview);
      expect(styleForZoom(16.0, NavMapStyle.overview), NavMapStyle.detail);
      expect(styleForZoom(18.0, NavMapStyle.overview), NavMapStyle.detail);
    });
    test('and off again a little lower, so it does not flicker', () {
      expect(styleForZoom(15.5, NavMapStyle.detail), NavMapStyle.detail);
      expect(styleForZoom(15.4, NavMapStyle.detail), NavMapStyle.detail);
      expect(styleForZoom(15.39, NavMapStyle.detail), NavMapStyle.overview);
      expect(styleForZoom(15.5, NavMapStyle.overview), NavMapStyle.overview);
    });
    test('both styles are valid JSON and differ the way they should', () {
      List<Map<String, dynamic>> parse(String s) => [for (final e in jsonDecode(s) as List) Map<String, dynamic>.from(e as Map)];
      bool hidesAllPoi(List<Map<String, dynamic>> l) =>
          l.any((e) => e['featureType'] == 'poi' && (e['stylers'] as List).any((s) => (s as Map)['visibility'] == 'off'));
      final overview = parse(kNavStyleOverview);
      final detail = parse(kNavStyleDetail);
      expect(overview, isNotEmpty);
      expect(detail, isNotEmpty);
      expect(hidesAllPoi(overview), isTrue);
      expect(hidesAllPoi(detail), isFalse);
      expect(detail.any((e) => e['featureType'] == 'poi.medical'), isTrue);
    });
  });

  group('accuracy circle', () {
    test('only when it is worth drawing', () {
      expect(accuracyRadiusM(null), isNull);
      expect(accuracyRadiusM(double.nan), isNull);
      expect(accuracyRadiusM(10), isNull);
      expect(accuracyRadiusM(20), isNull);
      expect(accuracyRadiusM(35), 35);
      expect(accuracyRadiusM(5000), 1000);
    });
  });

  group('progress on a route', () {
    final len = routeLengthM(route);
    final steps = withCumulativeEnds([step(600), step(len - 600)]);

    test('halfway: half is left, the ETA is half, and the first step is still current', () {
      final p = progressOnRoute(route: route, steps: steps, lat: -1.2850, lng: 36.8200, routeDistM: len, routeDurSec: 200)!;
      expect(p.crossTrackM, lessThan(0.5));
      expect(p.remainingM, closeTo(len / 2, 0.01));
      expect(p.etaSec, 100);
      expect(p.traveled.last.lat, closeTo(-1.2850, 1e-6));
      expect(p.remaining.first.lat, closeTo(-1.2850, 1e-6));
      expect(p.remaining.last, b);
      expect(p.next!.step, same(steps.first));
      expect(p.next!.distToStepEndM, closeTo(600 - len / 2, 0.01));
    });
    test('past the first step the second one is current', () {
      final p = progressOnRoute(route: route, steps: steps, lat: -1.2810, lng: 36.8200, routeDistM: len, routeDurSec: 200)!;
      expect(p.next!.step, same(steps.last));
    });
    test('beside the road it reports how far off', () {
      final p = progressOnRoute(route: route, steps: steps, lat: -1.2850, lng: 36.8210, routeDistM: len, routeDurSec: 200)!;
      expect(p.crossTrackM, closeTo(111.2, 1.0));
    });
    test('an empty route gives nothing', () {
      expect(progressOnRoute(route: const <LatLngPoint>[], steps: steps, lat: -1.285, lng: 36.82, routeDistM: 0, routeDurSec: 0), isNull);
    });
  });

  group('gliding between two fixes', () {
    const from = LatLngPoint(-1.2890, 36.8200);
    const to = LatLngPoint(-1.2870, 36.8200);
    test('along the road when both fixes are on it', () {
      expect(glidePoint(from: from, to: to, t: 0, route: route).lat, closeTo(-1.2890, 1e-6));
      expect(glidePoint(from: from, to: to, t: 0.5, route: route).lat, closeTo(-1.2880, 1e-6));
      expect(glidePoint(from: from, to: to, t: 1, route: route).lat, closeTo(-1.2870, 1e-6));
    });
    test('a fix 20 m beside the road is pulled onto the road', () {
      final p = glidePoint(from: const LatLngPoint(-1.2890, 36.82018), to: const LatLngPoint(-1.2870, 36.82018), t: 0.5, route: route);
      expect(p.lng, closeTo(36.8200, 1e-9));
    });
    test('55 m off the road it is a straight line, not snapped', () {
      final p = glidePoint(from: const LatLngPoint(-1.2890, 36.8205), to: const LatLngPoint(-1.2870, 36.8205), t: 0.5, route: route);
      expect(p.lng, closeTo(36.8205, 1e-9));
      expect(p.lat, closeTo(-1.2880, 1e-9));
    });
    test('without a route it is a straight line', () {
      final p = glidePoint(from: from, to: to, t: 0.25);
      expect(p.lat, closeTo(-1.2885, 1e-9));
    });
    test('t is kept between 0 and 1', () {
      expect(glidePoint(from: from, to: to, t: 2, route: route).lat, closeTo(-1.2870, 1e-6));
      expect(glidePoint(from: from, to: to, t: -1, route: route).lat, closeTo(-1.2890, 1e-6));
    });
  });

  group('when to ask for a new route', () {
    final t0 = DateTime(2026, 11, 4, 9, 0, 0);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    test('no route yet: ask, but not more than every 15 s', () {
      expect(needReroute(hasRoute: false, offRoute: false, destMovedM: 0, now: t0), isTrue);
      expect(needReroute(hasRoute: false, offRoute: false, destMovedM: 0, now: at(14), lastRouteAt: t0), isFalse);
      expect(needReroute(hasRoute: false, offRoute: false, destMovedM: 0, now: at(15), lastRouteAt: t0), isTrue);
    });
    test('off the route: ask, but not more than every 10 s', () {
      expect(needReroute(hasRoute: true, offRoute: true, destMovedM: 0, now: at(9), lastRouteAt: t0), isFalse);
      expect(needReroute(hasRoute: true, offRoute: true, destMovedM: 0, now: at(10), lastRouteAt: t0), isTrue);
    });
    test('the caller moved 150 m or more: ask, but not more than every 30 s', () {
      expect(needReroute(hasRoute: true, offRoute: false, destMovedM: 149, now: at(60), lastRouteAt: t0), isFalse);
      expect(needReroute(hasRoute: true, offRoute: false, destMovedM: 150, now: at(29), lastRouteAt: t0), isFalse);
      expect(needReroute(hasRoute: true, offRoute: false, destMovedM: 150, now: at(30), lastRouteAt: t0), isTrue);
    });
    test('otherwise only a traffic refresh every 3 minutes', () {
      expect(needReroute(hasRoute: true, offRoute: false, destMovedM: 0, now: at(179), lastRouteAt: t0), isFalse);
      expect(needReroute(hasRoute: true, offRoute: false, destMovedM: 0, now: at(180), lastRouteAt: t0), isTrue);
      expect(needReroute(hasRoute: true, offRoute: false, destMovedM: 0, now: t0), isFalse);
    });
  });

  group('framing the camera', () {
    test('two points 1.1 km apart on a phone-sized box', () {
      final v = fitView(points: route, widthPx: 400, heightPx: 800);
      expect(v.lat, closeTo(-1.285, 1e-9));
      expect(v.lng, closeTo(36.82, 1e-9));
      expect(v.zoom, closeTo(16.327, 0.001));
    });
    test('a 15 km box shows the whole thing', () {
      final v = fitView(points: const [LatLngPoint(-1.30, 36.80), LatLngPoint(-1.20, 36.90)], widthPx: 400, heightPx: 800);
      expect(v.lat, closeTo(-1.25, 1e-9));
      expect(v.lng, closeTo(36.85, 1e-9));
      expect(v.zoom, closeTo(11.836, 0.001));
    });
    test('two points on top of each other stop at the closest allowed zoom', () {
      final v = fitView(points: const [LatLngPoint(-1.2833, 36.8167), LatLngPoint(-1.2833, 36.8167)], widthPx: 400, heightPx: 800);
      expect(v.zoom, 17.5);
      expect(fitView(points: route, widthPx: 400, heightPx: 800, maxZoom: 16).zoom, 16);
    });
    test('one point is a street-level view, none is Nairobi', () {
      expect(fitView(points: const [LatLngPoint(-1.2833, 36.8167)], widthPx: 400, heightPx: 800).zoom, 16.5);
      final none = fitView(points: const <LatLngPoint>[], widthPx: 400, heightPx: 800);
      expect(none.lat, closeTo(-1.2921, 1e-9));
      expect(none.zoom, 12);
    });
  });

  group('words on the screen', () {
    test('distance to the next turn', () {
      expect(turnDistanceText(10), 'Now');
      expect(turnDistanceText(29.9), 'Now');
      expect(turnDistanceText(30), '30 m');
      expect(turnDistanceText(124), '120 m');
      expect(turnDistanceText(126), '130 m');
      expect(turnDistanceText(996), '996 m');
      expect(turnDistanceText(1000), '1.0 km');
      expect(turnDistanceText(1500), '1.5 km');
    });
    test('how fresh the other position is', () {
      final now = DateTime(2026, 11, 4, 9, 0, 0);
      expect(freshnessLabel(TrackFreshness.live, now, now), 'Live');
      expect(freshnessLabel(TrackFreshness.delayed, now, now), 'Live · slow signal');
      expect(freshnessLabel(TrackFreshness.stale, now.subtract(const Duration(seconds: 130)), now), 'Last seen 2 min ago');
      expect(freshnessLabel(TrackFreshness.stale, now.subtract(const Duration(seconds: 10)), now), 'Last seen 1 min ago');
      expect(freshnessLabel(TrackFreshness.stale, null, now), 'Last seen 1 min ago');
      expect(freshnessLabel(TrackFreshness.none, null, now), 'Location not shared');
    });
  });
}
