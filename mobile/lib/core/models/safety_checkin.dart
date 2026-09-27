import 'package:cloud_firestore/cloud_firestore.dart';

class SafetyCheckIn {
  const SafetyCheckIn({
    required this.id,
    required this.status,
    required this.durationMinutes,
    required this.expiryTime,
  });

  final String id;
  final String status;
  final int durationMinutes;
  final DateTime expiryTime;

  factory SafetyCheckIn.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final expiryTime = data['expiryTime'];
    return SafetyCheckIn(
      id: document.id,
      status: data['status'] as String? ?? 'Active',
      durationMinutes: data['durationMinutes'] as int? ?? 0,
      expiryTime: expiryTime is Timestamp ? expiryTime.toDate() : DateTime.now(),
    );
  }
}