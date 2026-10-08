// Centralized domain enums for the emergency activation flow.
// These enums keep the UI, classifier, and Firestore schema aligned.
enum EmergencyCategory {
  medical,
  roadAccident,
  fire,
  security,
  abduction,
  other,
  unknown;

  String get label {
    switch (this) {
      case EmergencyCategory.medical:
        return 'Medical Emergency';
      case EmergencyCategory.roadAccident:
        return 'Road Accident';
      case EmergencyCategory.fire:
        return 'Fire & Rescue';
      case EmergencyCategory.security:
        return 'Security Threat';
      case EmergencyCategory.abduction:
        return 'Abduction';
      case EmergencyCategory.other:
        return 'Other / General';
      case EmergencyCategory.unknown:
        return 'Unknown';
    }
  }

  String get firestoreValue => label;

  static EmergencyCategory fromFirestoreValue(dynamic value) {
    final normalized = (value ?? '').toString();
    return switch (normalized) {
      'Medical Emergency' => EmergencyCategory.medical,
      'Road Accident' => EmergencyCategory.roadAccident,
      'Fire & Rescue' => EmergencyCategory.fire,
      'Security Threat' => EmergencyCategory.security,
      'Abduction' => EmergencyCategory.abduction,
      'Other / General' => EmergencyCategory.other,
      _ => EmergencyCategory.unknown,
    };
  }

  static EmergencyCategory fromLabel(String? value) {
    return fromFirestoreValue(value);
  }
}

enum PriorityLevel {
  high,
  medium,
  low,
  pendingHumanTriage;

  String get label {
    switch (this) {
      case PriorityLevel.high:
        return 'High';
      case PriorityLevel.medium:
        return 'Medium';
      case PriorityLevel.low:
        return 'Low';
      case PriorityLevel.pendingHumanTriage:
        return 'PendingHumanTriage';
    }
  }

  String get firestoreValue => label;

  static PriorityLevel fromFirestoreValue(dynamic value) {
    final normalized = (value ?? '').toString();
    return switch (normalized) {
      'High' => PriorityLevel.high,
      'Medium' => PriorityLevel.medium,
      'Low' => PriorityLevel.low,
      'PendingHumanTriage' => PriorityLevel.pendingHumanTriage,
      _ => PriorityLevel.pendingHumanTriage,
    };
  }
}

enum IncidentStatus {
  newStatus,
  dispatched,
  enRoute,
  arrived,
  resolved,
  cancelled;

  String get label {
    switch (this) {
      case IncidentStatus.newStatus:
        return 'New';
      case IncidentStatus.dispatched:
        return 'Dispatched';
      case IncidentStatus.enRoute:
        return 'EnRoute';
      case IncidentStatus.arrived:
        return 'Arrived';
      case IncidentStatus.resolved:
        return 'Resolved';
      case IncidentStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get firestoreValue => label;

  static IncidentStatus fromFirestoreValue(dynamic value) {
    final normalized = (value ?? '').toString();
    return switch (normalized) {
      'New' => IncidentStatus.newStatus,
      'Dispatched' => IncidentStatus.dispatched,
      'EnRoute' => IncidentStatus.enRoute,
      'Arrived' => IncidentStatus.arrived,
      'Resolved' => IncidentStatus.resolved,
      'Cancelled' => IncidentStatus.cancelled,
      _ => IncidentStatus.newStatus,
    };
  }
}

enum ConsciousnessStatus {
  yes,
  no,
  unknown;

  String get label {
    switch (this) {
      case ConsciousnessStatus.yes:
        return 'Yes';
      case ConsciousnessStatus.no:
        return 'No';
      case ConsciousnessStatus.unknown:
        return 'Unknown';
    }
  }

  static ConsciousnessStatus fromValue(dynamic value) {
    final normalized = (value ?? '').toString();
    return switch (normalized) {
      'Yes' || 'yes' => ConsciousnessStatus.yes,
      'No' || 'no' => ConsciousnessStatus.no,
      _ => ConsciousnessStatus.unknown,
    };
  }
}

enum BreathingStatus {
  yes,
  no,
  unknown;

  String get label {
    switch (this) {
      case BreathingStatus.yes:
        return 'Yes';
      case BreathingStatus.no:
        return 'No';
      case BreathingStatus.unknown:
        return 'Unknown';
    }
  }

  static BreathingStatus fromValue(dynamic value) {
    final normalized = (value ?? '').toString();
    return switch (normalized) {
      'Yes' || 'yes' => BreathingStatus.yes,
      'No' || 'no' => BreathingStatus.no,
      _ => BreathingStatus.unknown,
    };
  }
}

enum MobilityStatus {
  mobile,
  trapped,
  unknown;

  String get label {
    switch (this) {
      case MobilityStatus.mobile:
        return 'Mobile';
      case MobilityStatus.trapped:
        return 'Trapped';
      case MobilityStatus.unknown:
        return 'Unknown';
    }
  }

  static MobilityStatus fromValue(dynamic value) {
    final normalized = (value ?? '').toString();
    return switch (normalized) {
      'Mobile' || 'mobile' => MobilityStatus.mobile,
      'Trapped' || 'trapped' => MobilityStatus.trapped,
      _ => MobilityStatus.unknown,
    };
  }
}

enum ActivationPath {
  sosButton,
  categorySelection,
  otherFreeText;

  String get label {
    switch (this) {
      case ActivationPath.sosButton:
        return 'sos_button';
      case ActivationPath.categorySelection:
        return 'category_selection';
      case ActivationPath.otherFreeText:
        return 'other_free_text';
    }
  }

  static ActivationPath fromValue(String? value) {
    return switch (value) {
      'sos_button' => ActivationPath.sosButton,
      'category_selection' => ActivationPath.categorySelection,
      'other_free_text' => ActivationPath.otherFreeText,
      _ => ActivationPath.categorySelection,
    };
  }
}
