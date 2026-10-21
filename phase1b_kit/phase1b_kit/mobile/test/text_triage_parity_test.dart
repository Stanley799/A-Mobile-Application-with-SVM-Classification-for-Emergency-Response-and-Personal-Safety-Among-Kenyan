// The phone's text engine must give the SAME answer as the Python engine for every stored message.
// Needs assets/text_triage_rules.json and test/assets/text_triage_vectors.json. Run:  flutter test test/text_triage_parity_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/text_triage_engine.dart';

void main() {
  late TextTriageEngine engine;
  late List vectors;

  setUpAll(() {
    engine = TextTriageEngine.fromJsonString(File('assets/text_triage_rules.json').readAsStringSync());
    vectors = jsonDecode(File('test/assets/text_triage_vectors.json').readAsStringSync()) as List;
  });

  test('Dart text engine equals Python for every stored message', () {
    var bad = 0;
    final shown = <String>[];
    for (final v in vectors) {
      final r = engine.triage(v['text'] as String);
      final got = jsonEncode([
        r.category, r.subtype, r.subtypeConfidence, r.method, r.confidence, r.flags,
        r.possibleFlags, r.priorityFloor, r.needsClarification, r.alternatives, r.safetyCheck, r.themes,
      ]);
      final want = jsonEncode([
        v['category'], v['subtype'], v['subtypeConfidence'], v['method'], v['confidence'], v['flags'],
        v['possibleFlags'], v['priorityFloor'], v['needsClarification'], v['alternatives'], v['safetyCheck'], v['themes'],
      ]);
      if (got != want) {
        bad++;
        if (shown.length < 10) shown.add('${v['text']}\n  dart=$got\n  py  =$want');
      }
    }
    expect(bad, 0, reason: '$bad of ${vectors.length} differ:\n${shown.join('\n')}');
  });

  test('plain examples', () {
    expect(engine.triage('someone fainted').category, 'Medical Emergency');
    expect(engine.triage('moto umeshika nyumba ya jirani').category, 'Fire');
    expect(engine.triage('').method, 'empty');
    expect(engine.triage('asdf qwer zxcv').category, isNull);
  });

  test('never throws on odd input', () {
    for (final t in ['😀😀', ' ', 'a' * 5000, 'ni\u0000ce', '!!!!', 'moooooto']) {
      engine.triage(t);
    }
  });
}
