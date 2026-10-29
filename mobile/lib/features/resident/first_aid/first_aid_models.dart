// Typed view of assets/first_aid/guides.json. The file is reviewed content: this layer only
// reads it. A malformed pack throws FormatException, which the screen turns into an ErrorState.
import 'dart:convert';

import 'first_aid_constants.dart';

class FirstAidText {
  const FirstAidText(this.en, this.sw);

  final String en;
  final String sw;

  String of(FirstAidLanguage language) => language == FirstAidLanguage.sw ? sw : en;

  bool get isComplete => en.trim().isNotEmpty && sw.trim().isNotEmpty;

  factory FirstAidText.fromJson(Object? value, String field) {
    final map = _asObject(value, field);
    final en = _asString(map['en'], '$field.en');
    final sw = _asString(map['sw'], '$field.sw');
    if (en.trim().isEmpty || sw.trim().isEmpty) {
      throw FormatException('$field must have English and Kiswahili text');
    }
    return FirstAidText(en, sw);
  }
}

class FirstAidPulse {
  const FirstAidPulse(this.bpm);

  final int bpm;

  factory FirstAidPulse.fromJson(Object? value) {
    final map = _asObject(value, 'pulse');
    final bpm = _asInt(map['bpm'], 'pulse.bpm');
    if (bpm < 100 || bpm > 120) {
      throw FormatException('pulse.bpm must be between 100 and 120');
    }
    return FirstAidPulse(bpm);
  }
}

class FirstAidStep {
  const FirstAidStep({required this.title, required this.body, this.pulse});

  final FirstAidText title;
  final FirstAidText body;
  final FirstAidPulse? pulse;

  factory FirstAidStep.fromJson(Object? value, int index) {
    final map = _asObject(value, 'steps[$index]');
    return FirstAidStep(
      title: FirstAidText.fromJson(map['t'], 'steps[$index].t'),
      body: FirstAidText.fromJson(map['b'], 'steps[$index].b'),
      pulse: map['pulse'] == null ? null : FirstAidPulse.fromJson(map['pulse']),
    );
  }
}

class FirstAidFlowNode {
  const FirstAidFlowNode({
    required this.id,
    required this.text,
    required this.yes,
    required this.no,
  });

  final String id;
  final FirstAidText text;
  final String yes;
  final String no;

  factory FirstAidFlowNode.fromJson(Object? value, int index) {
    final map = _asObject(value, 'flow[$index]');
    return FirstAidFlowNode(
      id: _asString(map['id'], 'flow[$index].id'),
      text: FirstAidText.fromJson(map['text'], 'flow[$index].text'),
      yes: _asString(map['yes'], 'flow[$index].yes'),
      no: _asString(map['no'], 'flow[$index].no'),
    );
  }
}

class FirstAidFlow {
  const FirstAidFlow({required this.id, required this.nodes});

  final String id;
  final List<FirstAidFlowNode> nodes;

  FirstAidFlowNode? node(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  factory FirstAidFlow.fromJson(String id, Object? value) {
    final list = _asList(value, 'flows.$id');
    final nodes = <FirstAidFlowNode>[
      for (var i = 0; i < list.length; i++) FirstAidFlowNode.fromJson(list[i], i),
    ];
    final ids = <String>{};
    for (final n in nodes) {
      if (!ids.add(n.id)) throw FormatException('flows.$id has a duplicate question id');
    }
    if (nodes.isEmpty) throw FormatException('flows.$id has no questions');
    return FirstAidFlow(id: id, nodes: nodes);
  }
}

class FirstAidEmergencyNumbers {
  const FirstAidEmergencyNumbers({
    required this.emergency,
    this.nationalDispatch,
    this.redCross,
    this.gbvHelpline,
  });

  final List<String> emergency;
  final String? nationalDispatch;
  final String? redCross;
  final String? gbvHelpline;

  factory FirstAidEmergencyNumbers.fromJson(Map<String, dynamic> json) {
    final emergency = _asStringList(json['emergency'], 'emergencyNumbers.emergency');
    if (emergency.isEmpty) {
      throw const FormatException('emergencyNumbers.emergency must not be empty');
    }
    return FirstAidEmergencyNumbers(
      emergency: emergency,
      nationalDispatch: _asStringOrNull(json['nationalDispatch']),
      redCross: _asStringOrNull(json['redCross']),
      gbvHelpline: _asStringOrNull(json['gbvHelpline']),
    );
  }
}

class FirstAidKeywords {
  const FirstAidKeywords({required this.en, required this.sw});

  final List<String> en;
  final List<String> sw;

  List<String> of(FirstAidLanguage language) =>
      language == FirstAidLanguage.sw ? sw : en;

  List<String> get all => [...en, ...sw];

  factory FirstAidKeywords.fromJson(Object? value) {
    final map = _asObject(value, 'keywords');
    return FirstAidKeywords(
      en: _asStringList(map['en'], 'keywords.en'),
      sw: _asStringList(map['sw'], 'keywords.sw'),
    );
  }
}

class FirstAidGuide {
  const FirstAidGuide({
    required this.id,
    required this.status,
    required this.title,
    required this.appliesTo,
    required this.subtypes,
    required this.keywords,
    required this.banner,
    required this.steps,
    required this.donts,
    required this.warning,
    required this.sources,
    required this.reviewNote,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.sourceVersion,
  });

  static const statusDraft = 'draft';
  static const statusApproved = 'approved';
  static const statusNeedsContent = 'needs_content';
  static const statuses = {statusDraft, statusApproved, statusNeedsContent};

  final String id;
  final String status;
  final FirstAidText title;
  final List<String> appliesTo;
  final List<String> subtypes;
  final FirstAidKeywords keywords;
  final FirstAidText? banner;
  final List<FirstAidStep> steps;

  /// One line per card. The pack may use a single {en, sw} object or a list.
  final List<FirstAidText> donts;
  final FirstAidText? warning;
  final List<String> sources;
  final String? reviewNote;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? sourceVersion;

  bool get isDraft => status == statusDraft;
  bool get isApproved => status == statusApproved;
  bool get hasContent => steps.isNotEmpty;

  /// needs_content never shows. A draft shows only when the compile-time gate is open.
  bool isVisibleWith({required bool allowDraft}) =>
      hasContent && (isApproved || (allowDraft && isDraft));

  bool get isVisible => isVisibleWith(allowDraft: kAllowDraftFirstAid);

  String titleFor(FirstAidLanguage language) => title.of(language);

  factory FirstAidGuide.fromJson(Object? value) {
    final map = _asObject(value, 'guide');
    final id = _asString(map['id'], 'guide.id');
    final status = _asString(map['status'], '$id.status');
    if (!statuses.contains(status)) {
      throw FormatException('$id.status is not a known status');
    }
    final stepsRaw = _asList(map['steps'], '$id.steps');
    final steps = <FirstAidStep>[
      for (var i = 0; i < stepsRaw.length; i++) FirstAidStep.fromJson(stepsRaw[i], i),
    ];
    return FirstAidGuide(
      id: id,
      status: status,
      title: FirstAidText.fromJson(map['title'], '$id.title'),
      appliesTo: _asStringList(map['appliesTo'], '$id.appliesTo'),
      subtypes: _asStringList(map['subtypes'], '$id.subtypes'),
      keywords: FirstAidKeywords.fromJson(map['keywords']),
      banner: map['banner'] == null ? null : FirstAidText.fromJson(map['banner'], '$id.banner'),
      steps: steps,
      donts: _readDonts(map['donts'], id),
      warning: map['warning'] == null ? null : FirstAidText.fromJson(map['warning'], '$id.warning'),
      sources: _asStringList(map['sources'], '$id.sources'),
      reviewNote: _asStringOrNull(map['reviewNote']),
      reviewedBy: _asStringOrNull(map['reviewedBy']),
      reviewedAt: _asStringOrNull(map['reviewedAt']),
      sourceVersion: _asStringOrNull(map['sourceVersion']),
    );
  }
}

class FirstAidCatalog {
  const FirstAidCatalog({
    required this.schemaVersion,
    required this.contentVersion,
    required this.languages,
    required this.emergencyNumbers,
    required this.draftNotice,
    required this.flows,
    required this.guides,
  });

  final int schemaVersion;
  final String contentVersion;
  final List<String> languages;
  final FirstAidEmergencyNumbers emergencyNumbers;
  final Map<String, String> draftNotice;
  final Map<String, FirstAidFlow> flows;
  final List<FirstAidGuide> guides;

  List<FirstAidGuide> get visibleGuides => [
    for (final g in guides)
      if (g.isVisible) g,
  ];

  FirstAidGuide? guideById(String id, {bool visibleOnly = true}) {
    for (final g in guides) {
      if (g.id == id && (!visibleOnly || g.isVisible)) return g;
    }
    return null;
  }

  String draftNoticeFor(FirstAidLanguage language) =>
      draftNotice[language.code] ?? draftNotice['en'] ?? '';

  factory FirstAidCatalog.fromJsonString(String source) =>
      FirstAidCatalog.fromJson(_asObject(jsonDecode(source), 'root'));

  factory FirstAidCatalog.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _asInt(json['schemaVersion'], 'schemaVersion');
    if (schemaVersion != 1) {
      throw FormatException('Unsupported first-aid schema version $schemaVersion');
    }
    final languages = _asStringList(json['languages'], 'languages');
    if (!languages.contains('en') || !languages.contains('sw')) {
      throw const FormatException('languages must include en and sw');
    }
    final rawFlows = _asObject(json['flows'], 'flows');
    final flows = <String, FirstAidFlow>{
      for (final e in rawFlows.entries) e.key: FirstAidFlow.fromJson(e.key, e.value),
    };
    final rawGuides = _asList(json['guides'], 'guides');
    final guides = <FirstAidGuide>[
      for (final g in rawGuides) FirstAidGuide.fromJson(g),
    ];
    final ids = <String>{};
    for (final g in guides) {
      if (!ids.add(g.id)) throw FormatException('Duplicate guide id ${g.id}');
    }
    return FirstAidCatalog(
      schemaVersion: schemaVersion,
      contentVersion: _asString(json['contentVersion'], 'contentVersion'),
      languages: languages,
      emergencyNumbers: FirstAidEmergencyNumbers.fromJson(
        _asObject(json['emergencyNumbers'], 'emergencyNumbers'),
      ),
      draftNotice: _asStringMap(json['draftNotice'], 'draftNotice'),
      flows: flows,
      guides: guides,
    );
  }
}

List<FirstAidText> _readDonts(Object? value, String id) {
  if (value == null) return const [];
  if (value is Map) {
    return [FirstAidText.fromJson(value, '$id.donts')];
  }
  if (value is List) {
    return [
      for (final item in value)
        if (item is String)
          FirstAidText(item, item)
        else
          FirstAidText.fromJson(item, '$id.donts'),
    ];
  }
  throw FormatException('$id.donts must be an object or a list');
}

Map<String, dynamic> _asObject(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('$field must be an object');
}

List<dynamic> _asList(Object? value, String field) {
  if (value is List) return value;
  throw FormatException('$field must be a list');
}

String _asString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field must be text');
}

String? _asStringOrNull(Object? value) => value is String ? value : null;

int _asInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field must be a number');
}

List<String> _asStringList(Object? value, String field) {
  final list = _asList(value, field);
  return [
    for (final item in list)
      if (item is String) item else throw FormatException('$field must contain text'),
  ];
}

Map<String, String> _asStringMap(Object? value, String field) {
  final map = _asObject(value, field);
  final out = <String, String>{};
  for (final e in map.entries) {
    final text = e.value;
    if (text is! String) {
      throw FormatException('$field.${e.key} must be text');
    }
    out[e.key] = text;
  }
  return out;
}
