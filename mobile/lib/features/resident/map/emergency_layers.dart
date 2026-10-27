// Which kinds of places matter for which emergency. PURE (no Flutter, no Firebase) so it is unit-tested.
enum PlaceType { hospital, clinic, ambulance, police, fire, helpline }

PlaceType? placeTypeOf(String? directoryType) => switch (directoryType) {
  'hospital' => PlaceType.hospital,
  'clinic' => PlaceType.clinic,
  'ambulance_operator' => PlaceType.ambulance,
  'police' => PlaceType.police,
  'fire' => PlaceType.fire,
  'helpline' => PlaceType.helpline,
  _ => null,
};

String placeTypeLabel(PlaceType t) => switch (t) {
  PlaceType.hospital => 'Hospitals',
  PlaceType.clinic => 'Clinics',
  PlaceType.ambulance => 'Ambulance',
  PlaceType.police => 'Police',
  PlaceType.fire => 'Fire & rescue',
  PlaceType.helpline => 'Helplines',
};

class EmergencyLayers {
  const EmergencyLayers({required this.title, required this.primary, required this.secondary});
  final String title;
  final List<PlaceType> primary; // shown by default
  final List<PlaceType> secondary; // one tap away
  List<PlaceType> get all => [...primary, ...secondary];
}

/// category and subtype come from the classifier; unknown values fall back to the general set (never empty).
EmergencyLayers layersFor(String? category, String? subtype) {
  switch (subtype) {
    case 'sexual_violence':
      return const EmergencyLayers(title: 'Care and support', primary: [PlaceType.hospital, PlaceType.helpline], secondary: [PlaceType.police, PlaceType.clinic]);
    case 'domestic_violence':
      return const EmergencyLayers(title: 'Safety and support', primary: [PlaceType.helpline, PlaceType.hospital, PlaceType.police], secondary: [PlaceType.clinic]);
    case 'mental_health_crisis':
      return const EmergencyLayers(title: 'Urgent mental health help', primary: [PlaceType.hospital, PlaceType.ambulance, PlaceType.helpline], secondary: [PlaceType.police]);
    case 'snakebite_or_poison':
      return const EmergencyLayers(title: 'Poison or snakebite', primary: [PlaceType.hospital, PlaceType.ambulance], secondary: [PlaceType.clinic]);
  }
  switch (category) {
    case 'Medical Emergency':
      return const EmergencyLayers(title: 'Medical emergency', primary: [PlaceType.ambulance, PlaceType.hospital], secondary: [PlaceType.clinic, PlaceType.police, PlaceType.fire]);
    case 'Road Accident':
      return const EmergencyLayers(title: 'Road accident', primary: [PlaceType.ambulance, PlaceType.hospital, PlaceType.police], secondary: [PlaceType.fire, PlaceType.clinic]);
    case 'Fire & Rescue':
      return const EmergencyLayers(title: 'Fire and rescue', primary: [PlaceType.fire, PlaceType.ambulance, PlaceType.hospital], secondary: [PlaceType.police, PlaceType.clinic]);
    case 'Security Threat':
      return const EmergencyLayers(title: 'Security threat', primary: [PlaceType.police], secondary: [PlaceType.hospital, PlaceType.ambulance]);
    case 'Abduction':
      return const EmergencyLayers(title: 'Abduction', primary: [PlaceType.police], secondary: [PlaceType.hospital]);
    default:
      return const EmergencyLayers(title: 'Emergency', primary: [PlaceType.hospital, PlaceType.police], secondary: [PlaceType.ambulance, PlaceType.fire, PlaceType.clinic]);
  }
}
