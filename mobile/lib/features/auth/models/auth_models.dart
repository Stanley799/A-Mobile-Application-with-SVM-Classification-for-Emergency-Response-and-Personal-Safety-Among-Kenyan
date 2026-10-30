/// Application roles and their corresponding Firestore values.
enum UserRole { resident, responder, systemAdmin }

/// Supported profile language codes.
enum PreferredLanguage { en, sw }

/// Organization types accepted for responder registration.
enum OrganizationType {
  ambulance,
  fire,
  police,
  hospital,
  community,
  maritime,
  other,
}

/// Account-level access states stored in user documents.
enum AccountStatus { active, pendingVerification, suspended }

/// Verification outcomes that gate responder access.
enum ResponderVerificationStatus { pending, verified, rejected, suspended }

/// Availability values published by verified responders.
enum AvailabilityStatus { available, busy, offline }

/// Maps user roles to and from the case-sensitive Firestore representation.
extension UserRoleX on UserRole {
  String get firestoreValue {
    switch (this) {
      case UserRole.resident:
        return 'Resident';
      case UserRole.responder:
        return 'Responder';
      case UserRole.systemAdmin:
        return 'SystemAdmin';
    }
  }

  static UserRole fromFirestore(String value) {
    switch (value) {
      case 'Resident':
        return UserRole.resident;
      case 'Responder':
        return UserRole.responder;
      case 'SystemAdmin':
        return UserRole.systemAdmin;
      default:
        throw ArgumentError('Unsupported role value: $value');
    }
  }
}

/// Maps application language values to persisted language codes.
extension PreferredLanguageX on PreferredLanguage {
  String get firestoreValue {
    switch (this) {
      case PreferredLanguage.en:
        return 'en';
      case PreferredLanguage.sw:
        return 'sw';
    }
  }
}

/// Maps organization types to the names expected by Firestore.
extension OrganizationTypeX on OrganizationType {
  String get firestoreValue {
    switch (this) {
      case OrganizationType.ambulance:
        return 'Ambulance';
      case OrganizationType.fire:
        return 'Fire';
      case OrganizationType.police:
        return 'Police';
      case OrganizationType.hospital:
        return 'Hospital';
      case OrganizationType.community:
        return 'Community';
      case OrganizationType.maritime:
        return 'Maritime';
      case OrganizationType.other:
        return 'Other';
    }
  }
}

/// Maps account status values to their persisted names.
extension AccountStatusX on AccountStatus {
  String get firestoreValue {
    switch (this) {
      case AccountStatus.active:
        return 'Active';
      case AccountStatus.pendingVerification:
        return 'PendingVerification';
      case AccountStatus.suspended:
        return 'Suspended';
    }
  }
}

/// Maps responder verification values to and from persisted names.
extension ResponderVerificationStatusX on ResponderVerificationStatus {
  String get firestoreValue {
    switch (this) {
      case ResponderVerificationStatus.pending:
        return 'Pending';
      case ResponderVerificationStatus.verified:
        return 'Verified';
      case ResponderVerificationStatus.rejected:
        return 'Rejected';
      case ResponderVerificationStatus.suspended:
        return 'Suspended';
    }
  }

  static ResponderVerificationStatus fromFirestore(String value) {
    switch (value) {
      case 'Pending':
        return ResponderVerificationStatus.pending;
      case 'Verified':
        return ResponderVerificationStatus.verified;
      case 'Rejected':
        return ResponderVerificationStatus.rejected;
      case 'Suspended':
        return ResponderVerificationStatus.suspended;
      default:
        throw ArgumentError('Unsupported responder verification status: $value');
    }
  }
}

/// Maps responder availability values to persisted names.
extension AvailabilityStatusX on AvailabilityStatus {
  String get firestoreValue {
    switch (this) {
      case AvailabilityStatus.available:
        return 'Available';
      case AvailabilityStatus.busy:
        return 'Busy';
      case AvailabilityStatus.offline:
        return 'Offline';
    }
  }
}
