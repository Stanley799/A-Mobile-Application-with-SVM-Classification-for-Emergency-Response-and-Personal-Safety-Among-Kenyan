import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tracking/nav_repository.dart';
import 'package:mobile/features/tracking/route_logic.dart';

void main() {
  group('NavTrack.tryParse', () {
    test('reads every field', () {
      final at = DateTime(2026, 11, 4, 9, 30);
      final t = NavTrack.tryParse({
        'lat': -1.2833,
        'lng': 36.8167,
        'heading': 90,
        'speed': 6.5,
        'accuracy': 12,
        'at': Timestamp.fromDate(at),
        'sharing': 'live',
      })!;
      expect(t.lat, -1.2833);
      expect(t.lng, 36.8167);
      expect(t.heading, 90);
      expect(t.speed, 6.5);
      expect(t.accuracy, 12);
      expect(t.at, at);
      expect(t.sharing, 'live');
      expect(t.position, const LatLngPoint(-1.2833, 36.8167));
    });
    test('an older document with only the basics still parses', () {
      final t = NavTrack.tryParse({'lat': -1.28, 'lng': 36.82})!;
      expect(t.accuracy, isNull);
      expect(t.at, isNull);
      expect(t.sharing, isNull);
    });
    test('missing or odd coordinates are skipped, never thrown', () {
      expect(NavTrack.tryParse(null), isNull);
      expect(NavTrack.tryParse({'lat': 'x', 'lng': 36.8}), isNull);
      expect(NavTrack.tryParse({'lat': -1.2}), isNull);
      expect(NavTrack.tryParse({'lat': 0, 'lng': 0}), isNull);
      expect(NavTrack.tryParse({'lat': 95, 'lng': 36}), isNull);
    });
  });

  group('parseNavRoute', () {
    const a = LatLngPoint(-1.29, 36.82);
    const mid = LatLngPoint(-1.285, 36.82);
    const b = LatLngPoint(-1.28, 36.82);

    Map<String, dynamic> answer({bool truncated = false}) => {
          'ok': true,
          'polyline': encodePolyline(const [a, b]),
          'overviewPolyline': encodePolyline(const [a, b]),
          'etaS': 200.0,
          'durationSec': 200,
          'distanceM': 1112,
          'estimate': false,
          if (truncated) 'stepsTruncated': true,
          'steps': [
            {'instruction': 'Head north', 'maneuver': null, 'distanceM': 556, 'durationSec': 100, 'polyline': truncated ? null : encodePolyline(const [a, mid])},
            {'instruction': 'Turn left onto Waiyaki Way', 'maneuver': 'turn-left', 'distanceM': 556, 'durationSec': 100, 'polyline': truncated ? null : encodePolyline(const [mid, b])},
          ],
        };

    test('joins the step lines into one full-precision route', () {
      final r = parseNavRoute(answer())!;
      expect(r.points.length, 3);
      expect(r.points[1].lat, closeTo(-1.285, 1e-6));
      expect(r.steps.length, 2);
      expect(r.steps[1].maneuver, 'turn-left');
      expect(r.steps[1].instruction, 'Turn left onto Waiyaki Way');
      expect(r.steps.last.endAlongM, closeTo(1112, 0.01));
      expect(r.distanceM, 1112);
      expect(r.durationSec, 200);
      expect(r.estimate, isFalse);
    });
    test('a truncated answer falls back to the overview line', () {
      final r = parseNavRoute(answer(truncated: true))!;
      expect(r.points.length, 2);
      expect(r.steps.length, 2);
    });
    test('the server said no, or sent nothing', () {
      expect(parseNavRoute(null), isNull);
      expect(parseNavRoute('x'), isNull);
      expect(parseNavRoute({'ok': false}), isNull);
    });
    test('a straight-line estimate has no points and is flagged', () {
      final r = parseNavRoute({'ok': true, 'polyline': '', 'etaS': 420, 'distanceM': 2100, 'estimate': true})!;
      expect(r.points, isEmpty);
      expect(r.steps, isEmpty);
      expect(r.estimate, isTrue);
      expect(r.durationSec, 420);
    });
    test('an old-style answer without steps still gives the route line', () {
      final r = parseNavRoute({'ok': true, 'polyline': encodePolyline(const [a, mid, b]), 'etaS': 180, 'distanceM': 1112, 'estimate': false})!;
      expect(r.points.length, 3);
      expect(r.steps, isEmpty);
    });
  });
}
