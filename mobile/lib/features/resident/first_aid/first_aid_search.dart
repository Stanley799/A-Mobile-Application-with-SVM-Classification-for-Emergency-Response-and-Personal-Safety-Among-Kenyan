// Local finder for "Describe what is happening". It never calls a network service and
// never writes or logs the typed text. Kiswahili/Sheng reuse the existing on-device
// text-triage rules (assets/text_triage_rules.json) READ-ONLY.
import '../../../../core/services/text_triage_engine.dart';
import 'first_aid_category_map.dart';
import 'first_aid_models.dart';

class FirstAidSearchResult {
  const FirstAidSearchResult({required this.immediateThreat, required this.suggestions});

  final bool immediateThreat;
  final List<FirstAidGuide> suggestions;

  static const empty = FirstAidSearchResult(immediateThreat: false, suggestions: []);
}

typedef FirstAidEngineLoader = Future<TextTriageEngine> Function();

class FirstAidSearch {
  FirstAidSearch({FirstAidEngineLoader? engineLoader})
    : _engineLoader = engineLoader ?? TextTriageEngine.loadFromAsset;

  /// Keyword matching only, with no triage asset read. Used by tests and as a fallback
  /// when the rules asset is unavailable; the guide pack keywords still work.
  FirstAidSearch.keywordsOnly() : _engineLoader = null;

  final FirstAidEngineLoader? _engineLoader;

  static const _threatPhrases = [
    'not breathing',
    'stopped breathing',
    'no breathing',
    'cannot breathe',
    'can not breathe',
    "can't breathe",
    'bleeding heavily',
    'heavy bleeding',
    'bleeding a lot',
    'severe bleeding',
    'suicide',
    'suicidal',
    'kill myself',
    'want to die',
    'end my life',
    'hapumui',
    'hawezi kupumua',
    'damu nyingi',
    'anavuja damu',
    'kujiua',
    'nataka kufa',
  ];

  /// True for words that should put the Call 999 / 112 panel before any suggestion.
  static bool isImmediateThreat(String text) {
    final normalized = normalizeFirstAidText(text);
    if (normalized.isEmpty) return false;
    return _threatPhrases.any((p) => _containsPhrase(normalized, normalizeFirstAidText(p)));
  }

  Future<FirstAidSearchResult> find(String text, List<FirstAidGuide> guides) async {
    final immediateThreat = isImmediateThreat(text);
    final normalized = normalizeFirstAidText(text);
    if (normalized.isEmpty) {
      return FirstAidSearchResult(immediateThreat: immediateThreat, suggestions: const []);
    }

    final scored = <({FirstAidGuide guide, int score, int order})>[];
    var order = 0;
    for (final guide in guides) {
      if (!guide.isVisible) continue;
      var score = 0;
      for (final keyword in guide.keywords.all) {
        final phrase = normalizeFirstAidText(keyword);
        if (phrase.isEmpty) continue;
        if (_containsPhrase(normalized, phrase)) {
          score += 10 + phrase.split(' ').length;
        }
      }
      if (score > 0) scored.add((guide: guide, score: score, order: order));
      order++;
    }

    // Kiswahili and Sheng: reuse the local triage lookups. A category/subtype hit is a
    // weaker signal than guide keywords, so it only fills gaps below the top matches.
    if (scored.length < 3 && _engineLoader != null) {
      try {
        final engine = await _engineLoader();
        final result = engine.triage(text);
        final category = result.category;
        if (category != null) {
          final byTriage = firstAidGuidesForIncident(
            guides,
            category: category,
            subtype: result.subtype,
          );
          final known = {for (final s in scored) s.guide.id};
          var extraOrder = order;
          for (final guide in byTriage) {
            if (known.add(guide.id)) {
              scored.add((guide: guide, score: 1, order: extraOrder++));
            }
          }
        }
      } catch (_) {
        // The rules asset is optional here: keyword matches still stand.
      }
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });

    return FirstAidSearchResult(
      immediateThreat: immediateThreat,
      suggestions: [for (final s in scored.take(3)) s.guide],
    );
  }
}

/// Lowercase, strip punctuation, collapse spaces. No stemming and no rewriting of content.
String normalizeFirstAidText(String text) => text
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _containsPhrase(String haystack, String phrase) {
  if (phrase.isEmpty) return false;
  return ' $haystack '.contains(' $phrase ');
}
