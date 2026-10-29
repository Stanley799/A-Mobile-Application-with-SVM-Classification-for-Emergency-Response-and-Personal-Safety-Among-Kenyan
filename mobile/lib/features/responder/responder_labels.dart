/// Human-facing words for responder data persisted as backend enum keys.
class ResponderLabels {
  static const capabilities = <String, String>{
    'medical_transport': 'Ambulance (medical transport)',
    'fire_suppression': 'Fire suppression',
    'extrication': 'Extrication',
    'law_enforcement': 'Police (law enforcement)',
    'maternal_care': 'Maternal care',
    'gbv_care': 'GBV care',
    'antivenom': 'Antivenom',
    'any_responder': 'Any responder',
  };

  static const categories = <String, String>{
    'Medical Emergency': 'Medical emergency',
    'Road Accident': 'Road accident',
    'Fire & Rescue': 'Fire and rescue',
    'Security Threat': 'Security threat',
    'Abduction': 'Abduction',
    'Other / General': 'Other emergency',
  };

  static String capability(String value) =>
      capabilities[value] ?? 'Other response capability';

  static String category(String value) => categories[value] ?? 'Emergency';

  static String offerStatus(String value, {String? withdrawReason}) =>
      switch (value) {
        'offered' => 'Waiting for you',
        'accepted' => 'You accepted',
        'enroute' => 'En route',
        'arrived' => 'Arrived',
        'completed' => 'Completed',
        'declined' => 'Declined',
        'expired' => 'Expired',
        'withdrawn' when withdrawReason == 'another_unit_accepted' ||
            withdrawReason == 'role_already_filled' => 'Taken by another unit',
        'withdrawn' when withdrawReason == 'incident_cancelled' => 'Cancelled',
        'withdrawn' => 'No longer available',
        _ => 'Status unavailable',
      };
}
