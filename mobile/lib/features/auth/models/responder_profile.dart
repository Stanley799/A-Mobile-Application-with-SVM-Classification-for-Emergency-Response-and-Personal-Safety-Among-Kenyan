import 'auth_models.dart';

/// Contains the verification state that controls responder access.
class ResponderProfile {
  const ResponderProfile({
    required this.responderId,
    required this.verificationStatus,
    required this.verificationNotes,
  });

  final String responderId;
  final ResponderVerificationStatus verificationStatus;
  final String? verificationNotes;

  /// Converts a `responders` document map into typed verification data.
  factory ResponderProfile.fromMap(Map<String, dynamic> data) {
    final verificationStatus = ResponderVerificationStatusX.fromFirestore(
      (data['verificationStatus'] as String?) ?? 'Pending',
    );

    return ResponderProfile(
      responderId: (data['responderId'] as String?) ?? '',
      verificationStatus: verificationStatus,
      verificationNotes: data['verificationNotes'] as String?,
    );
  }
}
