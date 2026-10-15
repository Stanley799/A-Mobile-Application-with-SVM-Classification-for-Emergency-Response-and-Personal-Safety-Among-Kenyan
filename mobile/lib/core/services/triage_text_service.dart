import 'package:cloud_functions/cloud_functions.dart';

/// What the server or local classifier thinks a typed description is about. The resident always confirms it.
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

  /// Suggests a category based on Cloud Functions, falling back to fast local keyword matching offline.
  Future<TextSuggestion?> suggest(String text) async {
    try {
      final callable = _functions.httpsCallable(
        'triage_text_fn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call<dynamic>({'text': text});
      return TextSuggestion.fromMap(Map<String, dynamic>.from(result.data as Map));
    } catch (_) {
      return _localSuggest(text);
    }
  }

  TextSuggestion? _localSuggest(String text) {
    final lower = text.toLowerCase();
    if (lower.trim().length < 3) return null;

    final flags = <String>[];
    if (lower.contains('suicide') ||
        lower.contains('kill myself') ||
        lower.contains('harm myself') ||
        lower.contains('end my life')) {
      flags.add('self_harm');
    }

    String? category;
    String? subtype;

    if (lower.contains('fire') ||
        lower.contains('smoke') ||
        lower.contains('burn') ||
        lower.contains('flame') ||
        lower.contains('explosion')) {
      category = 'Fire & Rescue';
      if (lower.contains('house') || lower.contains('building')) {
        subtype = 'building_fire';
      } else if (lower.contains('bush') ||
          lower.contains('forest') ||
          lower.contains('grass')) {
        subtype = 'bush_or_vegetation_fire';
      } else if (lower.contains('collapse') || lower.contains('collapsed')) {
        subtype = 'building_collapse';
      } else if (lower.contains('flood') ||
          lower.contains('drowning') ||
          lower.contains('water')) {
        subtype = 'flood_or_water_rescue';
      }
    } else if (lower.contains('accident') ||
        lower.contains('crash') ||
        lower.contains('car') ||
        lower.contains('vehicle') ||
        lower.contains('matatu') ||
        lower.contains('boda') ||
        lower.contains('truck') ||
        lower.contains('bus')) {
      category = 'Road Accident';
      if (lower.contains('boda') ||
          lower.contains('motorcycle') ||
          lower.contains('bike')) {
        subtype = 'boda_boda';
      } else if (lower.contains('matatu') || lower.contains('bus')) {
        subtype = 'matatu_or_bus';
      } else if (lower.contains('truck') || lower.contains('heavy')) {
        subtype = 'truck_or_heavy';
      } else if (lower.contains('pedestrian') || lower.contains('hit')) {
        subtype = 'pedestrian_hit';
      } else {
        subtype = 'private_vehicle';
      }
    } else if (lower.contains('sick') ||
        lower.contains('pain') ||
        lower.contains('bleed') ||
        lower.contains('bleeding') ||
        lower.contains('faint') ||
        lower.contains('unconscious') ||
        lower.contains('breathing') ||
        lower.contains('heart') ||
        lower.contains('chest') ||
        lower.contains('pregnant') ||
        lower.contains('labor') ||
        lower.contains('seizure') ||
        lower.contains('snake') ||
        lower.contains('poison')) {
      category = 'Medical Emergency';
      if (lower.contains('chest') || lower.contains('heart')) {
        subtype = 'cardiac';
      } else if (lower.contains('breath')) {
        subtype = 'breathing_problem';
      } else if (lower.contains('seizure') || lower.contains('faint')) {
        subtype = 'seizure_or_collapse';
      } else if (lower.contains('pregnant') ||
          lower.contains('baby') ||
          lower.contains('labor')) {
        subtype = 'maternal';
      } else if (lower.contains('child') || lower.contains('kid')) {
        subtype = 'sick_child';
      } else if (lower.contains('snake') || lower.contains('poison')) {
        subtype = 'snakebite_or_poison';
      } else {
        subtype = 'other_medical';
      }
    } else if (lower.contains('gun') ||
        lower.contains('rob') ||
        lower.contains('stolen') ||
        lower.contains('thief') ||
        lower.contains('knife') ||
        lower.contains('panga') ||
        lower.contains('weapon') ||
        lower.contains('attack') ||
        lower.contains('assault') ||
        lower.contains('mob') ||
        lower.contains('riot') ||
        lower.contains('violence') ||
        lower.contains('rape')) {
      category = 'Security Threat';
      if (lower.contains('rob') ||
          lower.contains('gun') ||
          lower.contains('weapon')) {
        subtype = 'armed_robbery';
      } else if (lower.contains('home') ||
          lower.contains('domestic') ||
          lower.contains('husband') ||
          lower.contains('wife')) {
        subtype = 'domestic_violence';
      } else if (lower.contains('rape') || lower.contains('sexual')) {
        subtype = 'sexual_violence';
      } else if (lower.contains('mob')) {
        subtype = 'mob_violence';
      } else if (lower.contains('riot') || lower.contains('loot')) {
        subtype = 'looting_or_riot';
      } else {
        subtype = 'assault';
      }
    } else if (lower.contains('kidnap') ||
        lower.contains('abduct') ||
        lower.contains('missing') ||
        lower.contains('snatched')) {
      category = 'Abduction';
      if (lower.contains('child') ||
          lower.contains('kid') ||
          lower.contains('baby')) {
        subtype = 'missing_child';
      } else {
        subtype = 'kidnapping';
      }
    }

    if (category == null) return null;

    return TextSuggestion(
      category: category,
      subtype: subtype,
      alternatives: const [],
      flags: flags,
      possibleFlags: const [],
      needsClarification: false,
    );
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
