import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/resident/map/resident_track_publisher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => ResidentTrackPublisher.instance.stop());

  test('releasing a holder while a write is in flight does not throw', () async {
    final p = ResidentTrackPublisher.instance;
    p.acquire('a');
    p.acquire('b');
    p.acquire('c');

    final seen = <String>[];
    await p.forEachHolderForTest((id) async {
      seen.add(id);
      await Future<void>.delayed(Duration.zero);
      p.release('b'); // the alert closes while 'a' is still being written
    });

    expect(seen, ['a', 'c'], reason: 'b was released, so it is skipped');
    expect(p.holds('b'), isFalse);
    expect(p.holds('a'), isTrue);
  });

  test('a failing write for one alert does not stop the others', () async {
    final p = ResidentTrackPublisher.instance;
    p.acquire('a');
    p.acquire('b');

    final seen = <String>[];
    await p.forEachHolderForTest((id) async {
      seen.add(id);
      if (id == 'a') throw StateError('permission-denied');
    });

    expect(seen, ['a', 'b']);
  });

  test('why the copy matters: removing from a live Set mid-loop throws', () async {
    final live = <String>{'a', 'b'};
    Future<void> bad() async {
      for (final x in live) {
        await Future<void>.delayed(Duration.zero);
        live.remove(x == 'a' ? 'b' : 'a');
      }
    }

    await expectLater(bad(), throwsA(isA<ConcurrentModificationError>()));
  });
}
