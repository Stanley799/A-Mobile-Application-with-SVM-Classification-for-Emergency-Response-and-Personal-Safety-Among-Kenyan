import 'package:cloud_functions/cloud_functions.dart';

/// What the server thinks a typed description is about. The resident always confirms it.
class TextSuggestion {
  const TextSuggestion({
    required this.category,
    required this.subtype,
    required this.alternatives,
    required this.flags,
    required this.possibleFlags,
    required this.needsClarification,
  });

  final String? category;
  final String? subtype;
  final List<String> alternatives;
  final List<String> flags;
  final List<String> possibleFlags;
  final bool needsClarification;

  bool get mentionsSelfHarm =>
      flags.contains('self_harm') || possibleFlags.contains('self_harm');

  static List<String> _strings(Object? value) =>
      (value as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory TextSuggestion.fromMap(Map<String, dynamic> map) => TextSuggestion(
    category: map['category'] as String?,
    subtype: map['subtype'] as String?,
    alternatives: _strings(map['alternatives']),
    flags: _strings(map['flags']),
    possibleFlags: _strings(map['possible_flags']),
    needsClarification: map['needs_clarification'] as bool? ?? true,
  );
}

/// Talks to the Cloud Functions in functions/main.py. Every call can fail silently:
/// a failed suggestion or save must never block a request for help.
class TriageTextService {
  TriageTextService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instanceFor(region: region);

  /// Must be the same region as OPTS in functions/main.py.
  static const region = 'europe-west1';
  final FirebaseFunctions _functions;

  /// Returns null when offline, slow or broken; the resident then picks the category by hand.
  Future<TextSuggestion?> suggest(String text) async {
    try {
      final callable = _functions.httpsCallable(
        'triage_text_fn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call<dynamic>({'text': text});
      return TextSuggestion.fromMap(Map<String, dynamic>.from(result.data as Map));
    } catch (_) {
      return null;
    }
  }

  /// Keeps the confirmed label for training. Only call after the resident ticked consent.
  /// The server refuses anything sensitive, so ignoring the answer is correct.
  Future<void> saveFeedback({
    required String text,
    required String confirmedCategory,
    String? confirmedSubtype,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'save_text_feedback_fn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      await callable.call<dynamic>({
        'text': text,
        'confirmed_category': confirmedCategory,
        'confirmed_subtype': confirmedSubtype,
        'consent': true,
      });
    } catch (_) {
      // Training data is optional. Never bother the resident.
    }
  }
}
