import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/map/emergency_layers.dart';
import 'package:mobile/features/resident/map/nearby_places.dart';

void main() {
  test('each emergency shows the right kinds of places first', () {
    expect(layersFor('Fire & Rescue', null).primary.first, PlaceType.fire);
    expect(layersFor('Security Threat', null).primary, [PlaceType.police]);
    expect(layersFor('Medical Emergency', null).primary, contains(PlaceType.hospital));
    expect(layersFor('Road Accident', null).primary, containsAll([PlaceType.ambulance, PlaceType.police]));
  });

  test('subtype overrides category; sexual violence never lists police first', () {
    final l = layersFor('Medical Emergency', 'sexual_violence');
    expect(l.primary, [PlaceType.hospital, PlaceType.helpline]);
    expect(l.secondary, contains(PlaceType.police));
  });

  test('unknown or missing category never gives an empty list', () {
    expect(layersFor(null, null).primary, isNotEmpty);
    expect(layersFor('Something new', 'nope').all, isNotEmpty);
  });

  test('directory type names map to place types', () {
    expect(placeTypeOf('ambulance_operator'), PlaceType.ambulance);
    expect(placeTypeOf('hospital'), PlaceType.hospital);
    expect(placeTypeOf('bar'), isNull);
  });

  NearbyPlace p(String id, PlaceType t, double? la, double? lo) => NearbyPlace(id: id, name: id, type: t, latitude: la, longitude: lo);

  test('rankNearby: nearest first, far dropped, capped per type', () {
    final all = [
      p('far', PlaceType.hospital, -1.2921 + 0.5, 36.8219),
      p('near', PlaceType.hospital, -1.2921 + 0.01, 36.8219),
      p('mid', PlaceType.hospital, -1.2921 + 0.05, 36.8219),
      p('third', PlaceType.hospital, -1.2921 + 0.06, 36.8219),
    ];
    final r = rankNearby(all, -1.2921, 36.8219, radiusKm: 12, perType: 2);
    expect(r.map((e) => e.id).toList(), ['near', 'mid']);
    expect(r.first.distanceKm, closeTo(1.1, 0.2));
  });

  test('fromMap rejects hidden, unnamed and unknown-type places', () {
    expect(NearbyPlace.fromMap('a', {'type': 'hospital', 'name': 'X', 'status': 'hidden'}), isNull);
    expect(NearbyPlace.fromMap('b', {'type': 'hospital', 'name': ' '}), isNull);
    expect(NearbyPlace.fromMap('c', {'type': 'shop', 'name': 'X'}), isNull);
    expect(NearbyPlace.fromMap('d', {'type': 'police', 'name': 'Central', 'lat': -1.3, 'lng': 36.8, 'phones': ['0700']})!.phone, '0700');
  });
}
