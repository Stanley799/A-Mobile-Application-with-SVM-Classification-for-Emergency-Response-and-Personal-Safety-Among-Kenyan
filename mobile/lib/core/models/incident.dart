import 'package:cloud_firestore/cloud_firestore.dart';

import 'emergency_enums.dart';

/// Strongly typed representation of an emergency incident.
/// The model intentionally supports both new naming and existing legacy fields
/// for compatibility while the emergency flow rolls out.
class Incident {
  const Incident({
    required this.incidentId,
    required this.reporterId,
    required this.activationPath,
    required this.category,
    required this.priority,
    required this.classifierConfidence,
    this.classifierReason,
    this.latitude,
    this.longitude,
    this.triageAnswers = const <String, dynamic>{},
    this.freeTextDescription,
    this.nlpExtractedKeywords = const <String>[],
    required this.status,
    this.channel = 'internet',
    required this.createdAt,
    required this.updatedAt,
    this.dispatchedAt,
    this.responderId,
  });

  final String incidentId;
  final String reporterId;
  final String activationPath;
  final EmergencyCategory category;
  final PriorityLevel priority;
  final double classifierConfidence;
  final String? classifierReason;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic> triageAnswers;
  final String? freeTextDescription;
  final List<String> nlpExtractedKeywords;
  final IncidentStatus status;
  final String channel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dispatchedAt;
  final String? responderId;

  factory Incident.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtValue = data['createdAt'];
    final updatedAtValue = data['updatedAt'];

    return Incident(
      incidentId: (data['incidentId'] ?? doc.id).toString(),
      reporterId: (data['reporterId'] ?? data['userId'] ?? '').toString(),
      activationPath: (data['activationPath'] ?? '').toString(),
      category: EmergencyCategory.fromFirestoreValue(data['category']),
      priority: PriorityLevel.fromFirestoreValue(data['priority']),
      classifierConfidence: ((data['classifierConfidence'] as num?) ?? 0)
          .toDouble(),
      classifierReason: data['classifierReason'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      triageAnswers: Map<String, dynamic>.from(
        data['triageAnswers'] ?? const <String, dynamic>{},
      ),
      freeTextDescription: data['freeTextDescription'] as String?,
      nlpExtractedKeywords: List<String>.from(
        ((data['nlpExtractedKeywords'] ?? const <dynamic>[])
                as Iterable<dynamic>)
            .map((entry) => entry.toString()),
      ),
      status: IncidentStatus.fromFirestoreValue(data['status']),
      channel: (data['channel'] ?? 'internet').toString(),
      createdAt: createdAtValue is Timestamp
          ? createdAtValue.toDate()
          : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp
          ? updatedAtValue.toDate()
          : DateTime.now(),
      dispatchedAt: (data['dispatchedAt'] as Timestamp?)?.toDate(),
      responderId: data['responderId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    final payload = <String, dynamic>{
      'incidentId': incidentId,
      'reporterId': reporterId,
      'userId': reporterId,
      'activationPath': activationPath,
      'category': category.firestoreValue,
      'priority': priority.firestoreValue,
      'classifierConfidence': classifierConfidence,
      'triageAnswers': triageAnswers.map(
        (key, value) => MapEntry(key, switch (value) {
          ConsciousnessStatus status => status.label,
          BreathingStatus status => status.label,
          MobilityStatus status => status.label,
          _ => value,
        }),
      ),
      'status': status.firestoreValue,
      'channel': channel,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };

    if (classifierReason != null && classifierReason!.isNotEmpty) {
      payload['classifierReason'] = classifierReason;
    }
    if (latitude != null) {
      payload['latitude'] = latitude;
    }
    if (longitude != null) {
      payload['longitude'] = longitude;
    }
    if (freeTextDescription != null) {
      payload['freeTextDescription'] = freeTextDescription;
    }
    if (nlpExtractedKeywords.isNotEmpty) {
      payload['nlpExtractedKeywords'] = nlpExtractedKeywords;
    }
    if (dispatchedAt != null) {
      payload['dispatchedAt'] = Timestamp.fromDate(dispatchedAt!);
    }
    if (responderId != null) {
      payload['responderId'] = responderId;
    }

    return payload;
  }
}
