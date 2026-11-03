import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tracking/route_logic.dart';
import 'package:mobile/features/tracking/track_logic.dart';

void main() {
  final t0 = DateTime(2026, 10, 30, 9, 40);

  group('distance and bearing', () {
    test('one degree of latitude', () => expect(haversineMeters(0, 0, 1, 0), closeTo(111194.9, 1)));
    test('Nairobi CBD to Westlands', () {
      expect(haversineMeters(-1.2833, 36.8167, -1.2676, 36.8108), closeTo(1864.9, 1));
      expect(bearingDegrees(-1.2833, 36.8167, -1.2676, 36.8108), closeTo(339.4, 0.5));
    });
    test('north and east', () {
      expect(bearingDegrees(0, 0, 1, 0), closeTo(0, 1e-6));
      expect(bearingDegrees(0, 0, 0, 1), closeTo(90, 1e-6));
    });
  });

  group('shouldWriteTrack', () {
    test('first fix is written', () => expect(shouldWriteTrack(now: t0, movedMeters: 0, accuracyM: 20), isTrue));
    test('never within 3 seconds', () {
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 2)), lastWriteAt: t0, movedMeters: 500, accuracyM: 5), isFalse);
    });
    test('poor accuracy is dropped, until 30 seconds have passed', () {
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 10)), lastWriteAt: t0, movedMeters: 100, accuracyM: 400), isFalse);
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 31)), lastWriteAt: t0, movedMeters: 100, accuracyM: 400), isTrue);
    });
    test('moved 10 m is written', () {
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 5)), lastWriteAt: t0, movedMeters: 10, accuracyM: 10), isTrue);
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 5)), lastWriteAt: t0, movedMeters: 9, accuracyM: 10), isFalse);
    });
    test('heartbeat after 20 seconds', () {
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 19)), lastWriteAt: t0, movedMeters: 0, accuracyM: 10), isFalse);
      expect(shouldWriteTrack(now: t0.add(const Duration(seconds: 20)), lastWriteAt: t0, movedMeters: 0, accuracyM: 10), isTrue);
    });
  });

  group('freshness', () {
    TrackFreshness at(int s, [String? sharing = 'live']) => freshnessOf(t0.add(Duration(seconds: s)), t0, sharing);
    test('by age', () {
      expect(at(15), TrackFreshness.live);
      expect(at(16), TrackFreshness.delayed);
      expect(at(45), TrackFreshness.delayed);
      expect(at(46), TrackFreshness.stale);
    });
    test('paused, stopped and never written', () {
      expect(at(1, 'paused'), TrackFreshness.none);
      expect(at(1, 'stopped'), TrackFreshness.none);
      expect(freshnessOf(t0, null, 'live'), TrackFreshness.none);
    });
    test('older documents with no sharing field count as live', () => expect(at(5, null), TrackFreshness.live));
    test('paused is told apart from stopped', () {
      expect(sharingOf('paused'), TrackSharing.paused);
      expect(sharingOf('stopped'), TrackSharing.stopped);
      expect(sharingOf(null), TrackSharing.live);
    });
  });

  group('follow target', () {
    test('caller only when fresh and accurate', () {
      expect(chooseDefaultTarget(callerFreshness: TrackFreshness.live, callerAccuracyM: 50), FollowTarget.caller);
      expect(chooseDefaultTarget(callerFreshness: TrackFreshness.delayed, callerAccuracyM: 100), FollowTarget.caller);
      expect(chooseDefaultTarget(callerFreshness: TrackFreshness.live, callerAccuracyM: 101), FollowTarget.reported);
      expect(chooseDefaultTarget(callerFreshness: TrackFreshness.stale, callerAccuracyM: 10), FollowTarget.reported);
      expect(chooseDefaultTarget(callerFreshness: TrackFreshness.none, callerAccuracyM: 10), FollowTarget.reported);
      expect(chooseDefaultTarget(callerFreshness: TrackFreshness.live), FollowTarget.reported);
    });
  });

  group('heading and smoothing', () {
    test('slow keeps the last heading', () {
      expect(effectiveHeading(lastHeading: 120, newHeading: 300, speedMps: 0.5), 120);
      expect(effectiveHeading(newHeading: 300, speedMps: 0.5), 0);
    });
    test('fast uses the new heading', () => expect(effectiveHeading(lastHeading: 120, newHeading: 300, speedMps: 5), 300));
    test('a missing or negative heading is ignored', () {
      expect(effectiveHeading(lastHeading: 120, newHeading: null, speedMps: 5), 120);
      expect(effectiveHeading(lastHeading: 120, newHeading: -1, speedMps: 5), 120);
    });
    test('shortest arc', () {
      expect(smoothBearing(350, 10), closeTo(356, 0.01));
      expect(smoothBearing(10, 350), closeTo(4, 0.01));
    });
    test('lerp across longitude 180', () {
      const a = LatLngPoint(0, 179.9);
      const b = LatLngPoint(0, -179.9);
      expect(lerpLatLng(a, b, 0).lng, closeTo(179.9, 1e-6));
      expect(lerpLatLng(a, b, 1).lng, closeTo(-179.9, 1e-6));
      expect(lerpLatLng(a, b, 0.5).lng.abs(), closeTo(180, 1e-6));
      expect(lerpLatLng(const LatLngPoint(0, 0), const LatLngPoint(10, 20), 0.5).lat, closeTo(5, 1e-9));
    });
  });

  group('words', () {
    test('eta in English', () {
      expect(etaText(null), 'ETA not available');
      expect(etaText(30), 'Less than a minute');
      expect(etaText(59), 'Less than a minute');
      expect(etaText(60), 'About 1 min');
      expect(etaText(90), 'About 2 min');
      expect(etaText(3600), 'About 60 min');
      expect(etaText(5400), 'About 1 h 30 min');
      expect(etaText(7500), 'About 2 h 5 min');
    });
    test('eta in Kiswahili', () {
      expect(etaText(null, lang: 'sw'), 'Muda haujapatikana');
      expect(etaText(30, lang: 'sw'), 'Chini ya dakika moja');
      expect(etaText(300, lang: 'sw'), 'Takriban dakika 5');
      expect(etaText(7500, lang: 'sw'), 'Takriban saa 2 dakika 5');
    });
    test('big eta', () {
      expect(bigEtaText(null), '–');
      expect(bigEtaText(20), '<1 min');
      expect(bigEtaText(300), '5 min');
      expect(bigEtaText(3900), '1 h 05 min');
    });
    test('distance', () {
      expect(distanceText(0), '0 m');
      expect(distanceText(850), '850 m');
      expect(distanceText(999), '999 m');
      expect(distanceText(1000), '1.0 km');
      expect(distanceText(2450), '2.5 km');
    });
    test('arrival clock', () {
      expect(arrivalClock(DateTime(2026, 10, 30, 9, 40), 300), '09:45');
      expect(arrivalClock(DateTime(2026, 10, 30, 23, 58), 300), '00:03');
      expect(arrivalClock(t0, null), '–');
    });
  });

  group('validCoordinate', () {
    test('rejects bad values', () {
      expect(validCoordinate(double.nan, 36), isFalse);
      expect(validCoordinate(double.infinity, 36), isFalse);
      expect(validCoordinate(0, 0), isFalse);
      expect(validCoordinate(91, 36), isFalse);
      expect(validCoordinate(-1.28, -181), isFalse);
    });
    test('accepts a real Nairobi point', () => expect(validCoordinate(-1.2833, 36.8167), isTrue));
  });
}
