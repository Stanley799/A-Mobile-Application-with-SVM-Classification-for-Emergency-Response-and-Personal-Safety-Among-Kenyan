// Compile-time gate and shared words for the guided first-aid tool.
//
// kAllowDraftFirstAid must stay false in released builds. The clinical content in
// assets/first_aid/guides.json is DRAFT until a clinician sets status to "approved".
// Flipping this to true shows drafts (with the JSON draftNotice banner) for local testing only.
const bool kAllowDraftFirstAid = false;

const String kFirstAidAssetPath = 'assets/first_aid/guides.json';

/// Public emergency numbers. Shown when the guide pack itself cannot be loaded.
const List<String> kFirstAidFallbackNumbers = ['999', '112'];

enum FirstAidLanguage {
  en,
  sw;

  String get code => name;

  /// Each language is named in its own language.
  String get label => this == FirstAidLanguage.sw ? 'Kiswahili' : 'English';

  String get toggleLabel => this == FirstAidLanguage.sw ? 'SW' : 'EN';

  static FirstAidLanguage? fromCode(String? code) => switch (code) {
    'en' => FirstAidLanguage.en,
    'sw' => FirstAidLanguage.sw,
    _ => null,
  };
}

/// UI words only. Clinical text always comes from the reviewed guide pack.
class FirstAidCopy {
  FirstAidCopy._();

  static const Map<String, Map<String, String>> _words = {
    'appTitle': {'en': 'First aid', 'sw': 'Msaada wa kwanza'},
    'languageTitle': {'en': 'English or Kiswahili?', 'sw': 'English au Kiswahili?'},
    'languageBody': {
      'en': 'Choose the language for the steps.',
      'sw': 'Chagua lugha ya hatua.',
    },
    'languageSaved': {'en': 'Saved on your profile', 'sw': 'Imehifadhiwa kwenye wasifu wako'},
    'whatEmergency': {'en': 'What is the emergency?', 'sw': 'Ni dharura gani?'},
    'somethingElse': {'en': 'Something else', 'sw': 'Kitu kingine'},
    'somethingElseHint': {
      'en': 'See every available guide',
      'sw': 'Ona miongozo yote inayopatikana',
    },
    'searchHint': {'en': 'Describe what is happening', 'sw': 'Eleza kinachotokea'},
    'searchLabel': {'en': 'Describe what is happening', 'sw': 'Eleza kinachotokea'},
    'searchNoMatch': {
      'en': 'We could not find a guide for that. Choose what is happening from the list.',
      'sw': 'Hatukupata mwongozo kwa hilo. Chagua kinachotokea kwenye orodha.',
    },
    'isThisWhat': {'en': 'Is this what you mean?', 'sw': 'Je, unamaanisha hii?'},
    'chooseDifferent': {
      'en': 'Choose a different emergency',
      'sw': 'Chagua dharura nyingine',
    },
    'call999': {'en': 'Call 999', 'sw': 'Piga 999'},
    'call112': {'en': 'Call 112', 'sw': 'Piga 112'},
    'callNumber': {'en': 'Call {number}', 'sw': 'Piga {number}'},
    'emergencyTitle': {'en': 'Call for help now', 'sw': 'Piga simu sasa'},
    'immediateThreat': {
      'en': 'This sounds like an emergency. Call 999 or 112 now.',
      'sw': 'Hii inaonekana kama dharura. Piga 999 au 112 sasa.',
    },
    'stepOf': {'en': 'Step {n} of {total}', 'sw': 'Hatua {n} ya {total}'},
    'back': {'en': 'Back', 'sw': 'Rudi'},
    'next': {'en': 'Next', 'sw': 'Endelea'},
    'done': {'en': 'Done', 'sw': 'Maliza'},
    'yes': {'en': 'Yes', 'sw': 'Ndiyo'},
    'no': {'en': 'No', 'sw': 'Hapana'},
    'seeAllMedical': {
      'en': 'See all medical guides',
      'sw': 'Ona miongozo yote ya afya',
    },
    'warning': {'en': 'Warning', 'sw': 'Tahadhari'},
    'donts': {'en': 'Do not', 'sw': 'Usifanye'},
    'gentleVibration': {'en': 'Gentle vibration', 'sw': 'Mtetemo hafifu'},
    'vibrationOffQuiet': {
      'en': 'Off in quiet mode',
      'sw': 'Imezimwa katika hali ya utulivu',
    },
    'perMinute': {'en': '{bpm} per minute', 'sw': '{bpm} kwa dakika'},
    'allGuides': {'en': 'All guides', 'sw': 'Miongozo yote'},
    'firstAidForEmergency': {
      'en': 'First aid for this emergency',
      'sw': 'Msaada wa kwanza kwa dharura hii',
    },
    'noApprovedGuide': {
      'en': 'No first-aid guide has been approved yet. Call 999 or 112 now if someone is in danger.',
      'sw': 'Hakuna mwongozo wa msaada wa kwanza ulioidhinishwa bado. Piga 999 au 112 sasa ikiwa mtu yuko hatarini.',
    },
    'noGuideFor': {
      'en': 'There is no guide for this yet. Call 999 or 112 now if someone is in danger.',
      'sw': 'Hakuna mwongozo kwa hili bado. Piga 999 au 112 sasa ikiwa mtu yuko hatarini.',
    },
    'guideWaiting': {
      'en': 'That guide is waiting for clinician approval. Call 999 or 112 now if someone is in danger.',
      'sw': 'Mwongozo huo unasubiri idhini ya wataalamu wa afya. Piga 999 au 112 sasa ikiwa mtu yuko hatarini.',
    },
    'loadErrorTitle': {
      'en': 'The first-aid guides could not be loaded',
      'sw': 'Miongozo ya msaada wa kwanza haikuweza kupakiwa',
    },
    'loadErrorBody': {
      'en': 'Call 999 or 112 now if someone is in danger.',
      'sw': 'Piga 999 au 112 sasa ikiwa mtu yuko hatarini.',
    },
    'tryAgain': {'en': 'Try again', 'sw': 'Jaribu tena'},
    'loading': {'en': 'Loading first-aid guides…', 'sw': 'Inapakia miongozo…'},
    'webCopied': {
      'en': 'A computer cannot dial. {number} was copied; call it from your phone.',
      'sw': 'Kompyuta haiwezi kupiga. {number} imenakiliwa; ipigie kutoka kwa simu yako.',
    },
    'dialFailed': {
      'en': 'Could not open the dialer. Please dial {number}.',
      'sw': 'Imeshindwa kufungua kipiga simu. Tafadhali piga {number}.',
    },
    'stepsCount': {'en': '{n} steps', 'sw': 'Hatua {n}'},
    'sensitiveSupport': {'en': 'Support guide', 'sw': 'Mwongozo wa msaada'},
  };

  static String of(FirstAidLanguage language, String key) =>
      _words[key]?[language.code] ?? _words[key]?['en'] ?? key;

  static String fill(String text, Map<String, Object> values) {
    var out = text;
    for (final e in values.entries) {
      out = out.replaceAll('{${e.key}}', '${e.value}');
    }
    return out;
  }
}
