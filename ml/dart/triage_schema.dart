// GENERATED FILE - DO NOT EDIT BY HAND. Source: schema/triage_schema.json (version 3.0.0).
// Regenerate with: py scripts\generate_dart.py

const String kTriageSchemaVersion = "3.0.0";
const String kNotAsked = "NotAsked";
const List<String> kPriorities = ["Low", "Medium", "High"];
const List<String> kModelFeatureOrder = ["category", "age_group", "conscious", "breathing", "severe_bleeding", "chest_pain", "pregnant", "trapped", "hazard", "weapon_involved", "immediate_danger", "people_count"];
const List<String> kCategories = ["Medical Emergency", "Road Accident", "Fire & Rescue", "Security Threat", "Abduction", "Other / General"];

class TriageQuestion {
  final String id; final String type; final String prompt; final List<String> values;
  final Map<String, String> labels; final int min; final int max; final Map<String, List<String>> askIf;
  const TriageQuestion(this.id, this.type, this.prompt, this.values, this.labels, this.min, this.max, this.askIf);
}

const Map<String, TriageQuestion> kQuestions = {
  "age_group": TriageQuestion("age_group", "enum", "Who needs help?", ["Adult", "Child", "Unknown"], {"Adult": "Adult (13 or older)", "Child": "Child (12 or younger)", "Unknown": "Not sure"}, 0, 0, {}),
  "conscious": TriageQuestion("conscious", "enum", "Is the person awake and responding?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "breathing": TriageQuestion("breathing", "enum", "Is the person breathing normally?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "severe_bleeding": TriageQuestion("severe_bleeding", "enum", "Is there heavy bleeding that will not stop?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "chest_pain": TriageQuestion("chest_pain", "enum", "Is the person having chest pain or crushing pressure in the chest?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "pregnant": TriageQuestion("pregnant", "enum", "Is the person pregnant?", ["Yes", "No", "Unknown"], {}, 0, 0, {"age_group": ["Adult", "Unknown"]}),
  "trapped": TriageQuestion("trapped", "enum", "Is anyone trapped and unable to get out?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "hazard": TriageQuestion("hazard", "enum", "Is there fire, smoke, fuel leaking or danger of collapse?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "weapon_involved": TriageQuestion("weapon_involved", "enum", "Is there a weapon (gun, knife, panga or similar)?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "immediate_danger": TriageQuestion("immediate_danger", "enum", "Is the attacker or threat still close by?", ["Yes", "No", "Unknown"], {}, 0, 0, {}),
  "people_count": TriageQuestion("people_count", "int", "How many people need help? (5 means 5 or more)", [], {}, 1, 5, {}),
};

/// Questions to show for each category, in order. Check askIf before showing each one.
const Map<String, List<String>> kCategoryQuestions = {
  "Medical Emergency": ["age_group", "conscious", "breathing", "severe_bleeding", "chest_pain", "pregnant", "people_count"],
  "Road Accident": ["age_group", "conscious", "breathing", "severe_bleeding", "trapped", "hazard", "pregnant", "people_count"],
  "Fire & Rescue": ["age_group", "conscious", "breathing", "trapped", "hazard", "people_count"],
  "Security Threat": ["age_group", "conscious", "breathing", "severe_bleeding", "weapon_involved", "immediate_danger", "people_count"],
  "Abduction": ["age_group", "weapon_involved", "immediate_danger", "people_count"],
  "Other / General": ["age_group", "conscious", "breathing", "severe_bleeding", "people_count"],
};

const Map<String, List<String>> kCategorySubtypes = {
  "Medical Emergency": ["cardiac", "breathing_problem", "seizure_or_collapse", "maternal", "sick_child", "snakebite_or_poison", "other_medical"],
  "Road Accident": ["boda_boda", "matatu_or_bus", "private_vehicle", "pedestrian_hit", "truck_or_heavy"],
  "Fire & Rescue": ["building_fire", "bush_or_vegetation_fire", "building_collapse", "flood_or_water_rescue"],
  "Security Threat": ["armed_robbery", "assault", "mob_violence", "looting_or_riot", "domestic_violence", "sexual_violence", "other_security"],
  "Abduction": ["kidnapping", "missing_child"],
  "Other / General": ["mental_health_crisis", "wildlife_attack", "fall_or_injury", "burns", "unclear"],
};

class SubtypeRule { final bool confidential; final bool notifyTrustedContactsByDefault; final bool shareFreeTextWithResponder;
  const SubtypeRule(this.confidential, this.notifyTrustedContactsByDefault, this.shareFreeTextWithResponder); }

const Map<String, SubtypeRule> kSubtypeRules = {
  "sexual_violence": SubtypeRule(true, false, false),
  "domestic_violence": SubtypeRule(true, false, false),
  "mental_health_crisis": SubtypeRule(true, true, false),
  "missing_child": SubtypeRule(false, true, true),
};

class Hotline { final String number; final String name; final String showWhen; final bool verified;
  const Hotline(this.number, this.name, this.showWhen, this.verified); }

/// Only show hotlines where verified is true.
const List<Hotline> kHotlines = [
  Hotline("922", "National Ambulance Dispatch Centre (SHA 922 Lifeline)", "always", true),
  Hotline("1195", "National GBV helpline (run by HAK with the government)", "sexual_violence,domestic_violence", true),
  Hotline("999", "General emergency number", "none_until_verified", false),
  Hotline("112", "General emergency number", "none_until_verified", false),
  Hotline("116", "Child helpline", "none_until_verified", false),
];

const double kOfferTimeoutSeconds = 45;
const int kMaxCardsShown = 3;
