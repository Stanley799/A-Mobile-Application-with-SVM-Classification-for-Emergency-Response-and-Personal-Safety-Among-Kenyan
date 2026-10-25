import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/map/help_models.dart';

void main() {
  test('decodePolyline matches the Google documentation example', () {
    final p = decodePolyline(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(p.length, 3);
    expect(p[0].lat, closeTo(38.5, 1e-6));
    expect(p[0].lng, closeTo(-120.2, 1e-6));
    expect(p[2].lat, closeTo(43.252, 1e-6));
    expect(p[2].lng, closeTo(-126.453, 1e-6));
  });

  test('decodePolyline never throws on bad input', () {
    expect(decodePolyline(''), isEmpty);
    expect(decodePolyline('~'), isA<List>());
  });

  test('HelpOption parses a live unit and a call-only service', () {
    final a = HelpOption.fromMap('r1', {'rank': 1, 'kind': 'live', 'refId': 'u1', 'name': 'Unit', 'orgType': 'Ambulance', 'status': 'available', 'lat': -1.3, 'lng': 36.8, 'etaMin': 6.4, 'etaSource': 'road', 'caps': ['medical_transport']});
    expect(a.canRequest, isTrue);
    expect(a.etaText, '6 min');
    final b = HelpOption.fromMap('r3', {'kind': 'hotline', 'refId': 'h', 'name': 'Ambulance Co', 'status': 'call', 'phones': ['0722000111'], 'etaMin': null});
    expect(b.hasPosition, isFalse);
    expect(b.canRequest, isFalse);
    expect(b.rank, 3);
    expect(b.etaText, isNull);
  });

  test('estimated times are labelled as estimates', () {
    final o = HelpOption.fromMap('r2', {'kind': 'place', 'refId': 'p', 'name': 'Hosp', 'status': 'directions', 'etaMin': 12.2, 'etaSource': 'estimate'});
    expect(o.etaText, 'about 12 min');
  });

  test('HelpMeta defaults are safe when the document is missing', () {
    final m = HelpMeta.fromMap(null);
    expect(m.mode, 'map');
    expect(m.showNumbers, isFalse);
    final x = HelpMeta.fromMap({'mode': 'helplines', 'failedCount': 2, 'suggestCall': true, 'sensitive': true});
    expect(x.mode, 'helplines');
    expect(x.failedCount, 2);
    expect(x.sensitive, isTrue);
  });

  test('TrackPoint.tryParse rejects incomplete data', () {
    expect(TrackPoint.tryParse({'lat': 1.0}), isNull);
    expect(TrackPoint.tryParse({'lat': -1.2, 'lng': 36.8})?.latitude, -1.2);
  });
}
