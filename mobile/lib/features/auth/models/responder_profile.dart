import 'auth_models.dart';

class ResponderProfile {
  const ResponderProfile({
    required this.responderId,
    required this.verificationStatus,
    required this.verificationNotes,
  });

  final String responderId;
  final ResponderVerificationStatus verificationStatus;
  final String? verificationNotes;

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
