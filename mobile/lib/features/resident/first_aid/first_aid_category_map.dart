// The only place that translates the guide pack's intent keys into the real triage schema.
// Guide appliesTo: medical, fire, violence_crime, sexual_violence, emotional_distress, accident_road.
// Real category keys come from triage_schema.dart (kCategories / kCategorySubtypes).
import '../../../../core/triage/triage_schema.dart';
import 'first_aid_constants.dart';
import 'first_aid_models.dart';

/// guide pack intent -> real triage category key.
const Map<String, String> kFirstAidIntentToCategory = {
  'medical': 'Medical Emergency',
  'fire': 'Fire & Rescue',
  'violence_crime': 'Security Threat',
  'sexual_violence': 'Security Threat',
  'emotional_distress': 'Other / General',
  'accident_road': 'Road Accident',
};

/// guide pack subtype -> the real triage subtype keys it can answer.
/// An empty list means the guide matches its category as a whole (no subtype claim).
const Map<String, List<String>> kFirstAidSubtypeToRealSubtypes = {
  'cardiac_arrest': ['cardiac'],
  'unresponsive': ['seizure_or_collapse'],
  'choking': ['breathing_problem'],
  'bleeding': ['other_medical', 'fall_or_injury'],
  'stab': ['other_medical'],
  'gunshot': ['other_medical'],
  'injury': ['fall_or_injury', 'other_medical'],
  'burn': ['burns'],
  'snakebite': ['snakebite_or_poison'],
  'seizure': ['seizure_or_collapse'],
  'unconscious': ['seizure_or_collapse'],
  'stroke': ['other_medical'],
  'crash': [],
  'fire': ['building_fire', 'bush_or_vegetation_fire'],
  'assault': ['assault'],
  'mob': ['mob_violence'],
  'robbery': ['armed_robbery'],
  'looting': ['looting_or_riot'],
  'rape': ['sexual_violence'],
  'sexual_assault': ['sexual_violence'],
  'crisis': ['mental_health_crisis'],
  'suicide_risk': ['mental_health_crisis', 'emotional_distress'],
};

/// The intent that names the category itself. A guide whose FIRST appliesTo is this intent
/// ranks above a guide that only covers the category as a side-effect (road_crash above
/// bleeding for a crash). The guide pack lists a guide's own intent first.
const Map<String, String> kFirstAidPrimaryIntent = {
  'Medical Emergency': 'medical',
  'Road Accident': 'accident_road',
  'Fire & Rescue': 'fire',
  'Security Threat': 'violence_crime',
  'Other / General': 'emotional_distress',
};

/// Guides that are only suggested when the incident's subtype (or the person's own words)
/// point at them. They stay reachable from the category list and the finder.
const Set<String> kFirstAidSensitiveGuideIds = {
  'sexual_violence_support',
  'emotional_support',
};

const Map<String, String> kFirstAidCategorySwahili = {
  'Medical Emergency': 'Dharura ya afya',
  'Road Accident': 'Ajali ya barabara',
  'Fire & Rescue': 'Moto na uokoaji',
  'Security Threat': 'Tishio la usalama',
  'Abduction': 'Utekaji',
  'Other / General': 'Nyingine / jumla',
};

String firstAidCategoryLabel(String category, FirstAidLanguage language) =>
    language == FirstAidLanguage.sw
        ? kFirstAidCategorySwahili[category] ?? category
        : category;

List<String> firstAidIntentsForCategory(String category) => [
  for (final e in kFirstAidIntentToCategory.entries)
    if (e.value == category) e.key,
];

Set<String> firstAidRealSubtypesFor(FirstAidGuide guide) => {
  for (final subtype in guide.subtypes)
    ...?kFirstAidSubtypeToRealSubtypes[subtype],
};

bool _isUsable(FirstAidGuide guide, bool includeDrafts) =>
    guide.status != FirstAidGuide.statusNeedsContent &&
    guide.hasContent &&
    (includeDrafts || guide.isVisible);

bool _byIntent(FirstAidGuide guide, List<String> intents) =>
    guide.appliesTo.any(intents.contains);

bool _bySubtype(FirstAidGuide guide, Set<String> realSubtypes) =>
    firstAidRealSubtypesFor(guide).any(realSubtypes.contains);

/// Deliberate navigation: every guide whose intent or subtype belongs to [category].
List<FirstAidGuide> firstAidGuidesForCategory(
  Iterable<FirstAidGuide> guides,
  String category, {
  bool includeDrafts = false,
}) {
  final intents = firstAidIntentsForCategory(category);
  final realSubtypes = (kCategorySubtypes[category] ?? const <String>[]).toSet();
  return [
    for (final g in guides)
      if (_isUsable(g, includeDrafts) &&
          (_byIntent(g, intents) || _bySubtype(g, realSubtypes)))
        g,
  ];
}

/// Alert status entry: best match first. 5 = primary intent + subtype, 4 = secondary intent
/// + subtype, 3 = primary intent only, 2 = secondary intent only, 1 = subtype only.
/// Sensitive guides are never category-only suggestions.
List<FirstAidGuide> firstAidGuidesForIncident(
  Iterable<FirstAidGuide> guides, {
  required String? category,
  String? subtype,
  bool includeDrafts = false,
}) {
  if (category == null || category.isEmpty) return const [];
  final intents = firstAidIntentsForCategory(category);
  final primary = kFirstAidPrimaryIntent[category];
  final realSubtypes = {
    if (subtype != null && subtype.isNotEmpty) subtype,
  };
  final scored = <({FirstAidGuide guide, int score, int order})>[];
  var order = 0;
  for (final guide in guides) {
    final usable = _isUsable(guide, includeDrafts);
    if (!usable) continue;
    final categoryMatch = _byIntent(guide, intents);
    final subtypeMatch = realSubtypes.isNotEmpty && _bySubtype(guide, realSubtypes);
    final primaryMatch = primary != null && guide.appliesTo.isNotEmpty && guide.appliesTo.first == primary;
    var score = 0;
    if (categoryMatch && subtypeMatch) {
      score = primaryMatch ? 5 : 4;
    } else if (categoryMatch) {
      score = kFirstAidSensitiveGuideIds.contains(guide.id) ? 0 : (primaryMatch ? 3 : 2);
    } else if (subtypeMatch) {
      score = 1;
    }
    if (score > 0) scored.add((guide: guide, score: score, order: order));
    order++;
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.order.compareTo(b.order);
  });
  return [for (final s in scored) s.guide];
}

/// Content gaps for the report/test. Uses every written guide, ignoring the draft gate.
List<String> firstAidCategoriesWithoutGuide(Iterable<FirstAidGuide> guides) => [
  for (final category in kCategories)
    if (firstAidGuidesForCategory(guides, category, includeDrafts: true).isEmpty)
      category,
];

/// Real subtypes that no guide claims directly (reported, never invented).
List<String> firstAidUnmappedRealSubtypes() {
  final covered = {
    for (final list in kFirstAidSubtypeToRealSubtypes.values) ...list,
  };
  return [
    for (final category in kCategories)
      for (final subtype in kCategorySubtypes[category] ?? const <String>[])
        if (!covered.contains(subtype)) '$category / $subtype',
  ];
}
