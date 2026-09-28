import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an owner-managed trusted contact stored in Firestore.
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relationship,
    required this.isActive,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final String relationship;
  final bool isActive;

  /// Reads contact fields from a Firestore document, applying legacy defaults.
  factory TrustedContact.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return TrustedContact(
      id: document.id,
      name: data['name'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      relationship: data['relationship'] as String? ?? 'Other',
      isActive: data['isActive'] as bool? ?? false,
    );
  }
}