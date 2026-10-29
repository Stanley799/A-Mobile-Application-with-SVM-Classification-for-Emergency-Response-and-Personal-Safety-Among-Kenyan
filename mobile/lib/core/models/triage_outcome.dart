import '../triage/triage_schema.dart';

/// Everything the triage sheet learned about one emergency, ready to be saved on the incident.
class TriageOutcome {
  const TriageOutcome({
    required this.category,
    required this.subtype,
    required this.answers,
    required this.priority,
    required this.confidence,
    required this.needsHumanReview,
    required this.source,
    this.fallbackReason,
    this.description,
    this.flags = const [],
    this.saveForTraining = false,
    this.supportOnly = false,
    required this.schemaVersion,
  });

  factory TriageOutcome.supportOnly({
    required String category,
    required String? subtype,
  }) => TriageOutcome(
        category: category,
        subtype: subtype,
        answers: const {},
        priority: 'Low',
        confidence: 1,
        needsHumanReview: true,
        source: 'support_only',
        supportOnly: true,
        saveForTraining: false,
        schemaVersion: kTriageSchemaVersion,
      );

  final String category;
  final String? subtype;

  /// Question id -> answer text, only for questions that were actually asked.
  final Map<String, String> answers;
  final String priority;
  final double confidence;
  final bool needsHumanReview;

  /// 'decision_table', 'safe_fallback' (High because something was missing) or 'support_only'.
  final String source;
  final String? fallbackReason;

  /// Free text the resident typed. Null for confidential subtypes: it is never shared with responders.
  final String? description;
  final List<String> flags;

  /// True only when the resident ticked the consent box and the text may be kept for training.
  final bool saveForTraining;

  /// True for emotional distress without self-harm: support lines are shown, no responder is sent.
  final bool supportOnly;
  final String schemaVersion;

  /// Fields to merge into the incident document (the caller adds the server timestamp).
  Map<String, Object?> toIncidentFields() => {
    'category': category,
    'subtype': subtype,
    'priority': priority,
    'prioritySource': source,
    'needsHumanReview': needsHumanReview,
    'triageStatus': 'complete',
    'triage': {
      'answers': answers,
      'confidence': confidence,
      'fallbackReason': fallbackReason,
      'schemaVersion': schemaVersion,
      if (description != null) 'input': 'text_description',
    },
    if (description != null) 'description': description,
    if (flags.isNotEmpty) 'flags': flags,
    if (supportOnly) 'status': 'SupportOnly',
  };
}
