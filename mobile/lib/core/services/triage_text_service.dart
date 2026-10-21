import 'package:cloud_functions/cloud_functions.dart';

import 'text_triage_engine.dart';

/// What the app understood from a typed description. The resident ALWAYS confirms it.
class TextSuggestion {
  const TextSuggestion({
    required this.category,
    required this.subtype,
    required this.alternatives,
    required this.flags,
    required this.possibleFlags,
    required this.needsClarification,
    this.safetyCheck = false,
    this.method = 'unclear',
    this.themes = const [],
  });

  final String? category;
  final String? subtype;

  /// Other likely categories, best evidence first (at most 3). Show them as chips.
  final List<String> alternatives;
  final List<String> flags;
  final List<String> possibleFlags;
  final bool needsClarification;

  /// True when the text suggests the person may be in distress: show the support card.
  final bool safetyCheck;

  /// lexicon | ambiguous | unclear | safety_flag | empty | error
  final String method;
  final List<String> themes;

  bool get mentionsSelfHarm => flags.contains('self_harm') || possibleFlags.contains('self_harm');

  /// Nothing useful found: show the "we could not understand" message and the manual choices.
  bool get isUnclear => category == null && alternatives.isEmpty;

  factory TextSuggestion.fromResult(TextTriageResult r) => TextSuggestion(
    category: r.category,
    subtype: r.subtype,
    alternatives: r.alternatives,
    flags: r.flags,
    possibleFlags: r.possibleFlags,
    needsClarification: r.needsClarification,
    safetyCheck: r.safetyCheck,
    method: r.method,
    themes: r.themes,
  );
}

/// Understands typed descriptions ON THE PHONE (Swahili, Sheng, English). No internet, no Cloud Function.
/// Only [saveFeedback] uses the cloud, and it fails silently.
class TriageTextService {
  TriageTextService({FirebaseFunctions? functions}) : _functions = functions;

  static const region = 'europe-west1';
  FirebaseFunctions? _functions;
  static Future<TextTriageEngine>? _engine;

  static Future<TextTriageEngine> _load() => _engine ??= TextTriageEngine.loadFromAsset();

  /// Call once at startup (not awaited) so the first description is instant.
  static void warmUp() {
    _load().then<void>((_) {}, onError: (Object _) {
      _engine = null;
    });
  }

  /// Never returns null and never throws. A broken engine gives an "unclear" suggestion.
  Future<TextSuggestion> suggest(String text) async {
    try {
      final engine = await _load();
      return TextSuggestion.fromResult(engine.triage(text));
    } catch (_) {
      _engine = null;
      return TextSuggestion.fromResult(const TextTriageResult(method: 'error'));
    }
  }

  /// Keeps the confirmed label for training. Only call after the resident ticked consent.
  Future<void> saveFeedback({
    required String text,
    required String confirmedCategory,
    String? confirmedSubtype,
  }) async {
    try {
      final fns = _functions ??= FirebaseFunctions.instanceFor(region: region);
      final callable = fns.httpsCallable(
        'save_text_feedback_fn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      await callable.call<dynamic>({
        'text': text,
        'confirmed_category': confirmedCategory,
        'confirmed_subtype': confirmedSubtype,
        'consent': true,
      });
    } catch (_) {}
  }
}
