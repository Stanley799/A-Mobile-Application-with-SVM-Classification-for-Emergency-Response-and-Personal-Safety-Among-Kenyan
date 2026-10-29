// Guided first aid: a router over the fixed, reviewed guide pack. It never writes advice.
// Flow: language -> "What is the emergency?" (or the incident's best matches) -> guide player.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/triage/triage_schema.dart';
import '../../../../core/ui/states.dart';
import '../../../../core/ui/tokens.dart';
import 'first_aid_catalog.dart';
import 'first_aid_category_map.dart';
import 'first_aid_constants.dart';
import 'first_aid_models.dart';
import 'first_aid_player.dart';
import 'first_aid_search.dart';
import 'first_aid_widgets.dart';

enum _Stage { language, picker, list, flow, player }

enum _ListKind { alert, category, search, all }

class FirstAidScreen extends StatefulWidget {
  const FirstAidScreen({
    super.key,
    this.category,
    this.subtype,
    this.quiet = false,
    this.catalog,
    this.search,
  });

  /// The incident's real triage category and subtype, when opened from an alert.
  final String? category;
  final String? subtype;

  /// Quiet mode from the alert sheet: no haptics in the guide player.
  final bool quiet;

  /// Tests inject a catalog; production reads assets/first_aid/guides.json once.
  final FirstAidCatalog? catalog;
  final FirstAidSearch? search;

  @override
  State<FirstAidScreen> createState() => _FirstAidScreenState();
}

class _FirstAidScreenState extends State<FirstAidScreen> {
  late Future<FirstAidCatalog> _catalogFuture;
  late final FirstAidSearch _search = widget.search ?? FirstAidSearch();
  final TextEditingController _searchController = TextEditingController();

  FirstAidLanguage? _language;
  String? _rememberedCode;
  _Stage _stage = _Stage.language;
  _ListKind _listKind = _ListKind.category;
  String? _listCategory;
  List<FirstAidGuide> _searchGuides = const [];
  bool _searchThreat = false;
  bool _searchRan = false;
  bool _guideWaiting = false;
  Timer? _debounce;

  FirstAidGuide? _guide;
  _Stage _guideReturn = _Stage.list;
  String? _flowNode;
  final List<String> _flowHistory = [];

  @override
  void initState() {
    super.initState();
    _bindCatalog(force: false);
    _readRememberedLanguage().then((code) {
      if (mounted && code != null) setState(() => _rememberedCode = code);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _bindCatalog({required bool force}) {
    _catalogFuture = widget.catalog != null && !force
        ? Future.value(widget.catalog)
        : FirstAidCatalogLoader.load(force: force);
    _catalogFuture.then<void>((_) {}, onError: (Object _) {});
  }

  Future<String?> _readRememberedLanguage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      return FirstAidLanguage.fromCode(doc.data()?['preferredLanguage'] as String?)?.code;
    } catch (_) {
      return null;
    }
  }

  /// The profile already allows the owner to update preferredLanguage, so the choice is
  /// remembered there. Only the language is written; no guide, search or usage is stored.
  Future<void> _saveLanguage(FirstAidLanguage language) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'preferredLanguage': language.code,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _rememberedCode = language.code;
    } catch (_) {
      // Offline is fine: the choice still applies for this visit.
    }
  }

  void _selectLanguage(FirstAidLanguage language) {
    final firstChoice = _stage == _Stage.language;
    setState(() {
      _language = language;
      if (firstChoice) {
        if (widget.category == 'Medical Emergency' &&
            (widget.subtype == null || widget.subtype!.isEmpty)) {
          _stage = _Stage.flow;
          _listKind = _ListKind.category;
          _listCategory = 'Medical Emergency';
        } else if (widget.category != null) {
          _stage = _Stage.list;
          _listKind = _ListKind.alert;
          _listCategory = widget.category;
        } else {
          _stage = _Stage.picker;
        }
      }
    });
    if (_rememberedCode != language.code) {
      unawaited(_saveLanguage(language));
    }
  }

  void _back() {
    switch (_stage) {
      case _Stage.language:
        Navigator.of(context).maybePop();
      case _Stage.picker:
        setState(() => _stage = _Stage.language);
      case _Stage.list:
        _toPicker();
      case _Stage.flow:
        if (_flowHistory.isNotEmpty) {
          setState(() {
            _flowNode = _flowHistory.removeLast();
          });
        } else {
          _toPicker();
        }
      case _Stage.player:
        setState(() => _stage = _guideReturn);
    }
  }

  void _toPicker() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _stage = _Stage.picker;
      _listKind = _ListKind.category;
      _listCategory = null;
      _searchGuides = const [];
      _searchThreat = false;
      _searchRan = false;
      _guideWaiting = false;
      _guide = null;
      _flowNode = null;
      _flowHistory.clear();
    });
  }

  void _pickCategory(String category) {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchGuides = const [];
      _searchThreat = false;
      _searchRan = false;
      _guideWaiting = false;
      _listKind = _ListKind.category;
      _listCategory = category;
      if (category == 'Medical Emergency') {
        _flowNode = null;
        _flowHistory.clear();
        _stage = _Stage.flow;
      } else {
        _stage = _Stage.list;
      }
    });
  }

  void _medicalTopics() => setState(() {
    _guideWaiting = false;
    _listKind = _ListKind.category;
    _listCategory = 'Medical Emergency';
    _stage = _Stage.list;
  });

  void _openGuide(FirstAidGuide guide) {
    setState(() {
      _guide = guide;
      _guideWaiting = false;
      _guideReturn = _stage;
      _stage = _Stage.player;
    });
  }

  void _finishGuide() {
    if (_guideReturn == _Stage.flow) {
      _medicalTopics();
    } else if (_guideReturn == _Stage.list) {
      setState(() => _stage = _Stage.list);
    } else {
      _toPicker();
    }
  }

  void _onSearchChanged(FirstAidCatalog catalog, String text) {
    _debounce?.cancel();
    setState(() {
      _searchRan = false;
      _searchGuides = const [];
      _searchThreat = false;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(catalog, text));
  }

  Future<void> _runSearch(FirstAidCatalog catalog, String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    final result = await _search.find(query, catalog.visibleGuides);
    if (!mounted) return;
    setState(() {
      _searchGuides = result.suggestions;
      _searchThreat = result.immediateThreat;
      _searchRan = true;
      if (result.suggestions.isNotEmpty || result.immediateThreat) {
        _listKind = _ListKind.search;
        _stage = _Stage.list;
      }
    });
  }

  void _answer(FirstAidCatalog catalog, FirstAidFlow flow, FirstAidFlowNode node, {required bool yes}) {
    final target = yes ? node.yes : node.no;
    if (target.startsWith('guide:')) {
      final guide = catalog.guideById(target.substring(6));
      if (guide != null) {
        _flowHistory.add(node.id);
        _openGuide(guide);
      } else {
        setState(() {
          _guideWaiting = true;
          _listKind = _ListKind.category;
          _listCategory = 'Medical Emergency';
          _stage = _Stage.list;
        });
      }
      return;
    }
    if (target == 'pick_topic') {
      _medicalTopics();
      return;
    }
    if (flow.node(target) != null) {
      setState(() {
        _flowHistory.add(node.id);
        _flowNode = target;
      });
      return;
    }
    _medicalTopics();
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    return PopScope(
      canPop: _stage == _Stage.language,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(FirstAidCopy.of(language ?? FirstAidLanguage.en, 'appTitle')),
          leading: IconButton(
            tooltip: FirstAidCopy.of(language ?? FirstAidLanguage.en, 'back'),
            onPressed: _back,
            icon: Icon(_stage == _Stage.language ? Icons.close : Icons.arrow_back),
          ),
          actions: [
            FirstAidLanguageToggle(language: language, onChanged: _selectLanguage),
            const SizedBox(width: 8),
          ],
        ),
        body: _body(language),
      ),
    );
  }

  Widget _body(FirstAidLanguage? language) {
    if (language == null) return _languagePicker();
    return FutureBuilder<FirstAidCatalog>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _errorView(language);
        final catalog = snapshot.data;
        if (catalog == null) {
          return LoadingView(label: FirstAidCopy.of(language, 'loading'));
        }
        switch (_stage) {
          case _Stage.language:
            return _languagePicker();
          case _Stage.picker:
            return _pickerView(catalog, language);
          case _Stage.flow:
            return _flowView(catalog, language);
          case _Stage.list:
            return _listView(catalog, language);
          case _Stage.player:
            final guide = _guide;
            if (guide == null) return _pickerView(catalog, language);
            return FirstAidPlayer(
              guide: guide,
              catalog: catalog,
              language: language,
              quiet: widget.quiet,
              showDraftBanner: guide.isDraft,
              onChooseDifferent: _toPicker,
              onDone: _finishGuide,
            );
        }
      },
    );
  }

  Widget _languagePicker() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
    children: [
      Text(
        FirstAidCopy.of(_language ?? FirstAidLanguage.en, 'languageTitle'),
        style: const TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800, color: Tk.ink),
      ),
      const SizedBox(height: 8),
      Text(
        FirstAidCopy.of(_language ?? FirstAidLanguage.en, 'languageBody'),
        style: const TextStyle(fontSize: 16, height: 1.4, color: Tk.mute),
      ),
      const SizedBox(height: 24),
      for (final language in FirstAidLanguage.values) ...[
        _languageTile(language),
        if (language != FirstAidLanguage.values.last) const SizedBox(height: 12),
      ],
    ],
  );

  Widget _languageTile(FirstAidLanguage language) {
    final selected = _language == language;
    final saved = _rememberedCode == language.code;
    return Semantics(
      button: true,
      selected: selected,
      label: language.label,
      child: Material(
        color: Tk.card,
        borderRadius: BorderRadius.circular(Tk.rCard),
        child: InkWell(
          key: ValueKey('first_aid_language_${language.code}'),
          borderRadius: BorderRadius.circular(Tk.rCard),
          onTap: () => _selectLanguage(language),
          child: Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tk.rCard),
              border: Border.all(color: selected ? Tk.brand : Tk.line, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Tk.brandTint, shape: BoxShape.circle),
                  child: Text(
                    language.toggleLabel,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Tk.brandDeep),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(language.label, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Tk.ink)),
                      if (saved) ...[
                        const SizedBox(height: 3),
                        Text(
                          FirstAidCopy.of(language, 'languageSaved'),
                          style: const TextStyle(fontSize: 13, color: Tk.mute),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, color: Tk.brand, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerView(FirstAidCatalog catalog, FirstAidLanguage language) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
    children: [
      Text(
        FirstAidCopy.of(language, 'whatEmergency'),
        style: const TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w800, color: Tk.ink),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey('first_aid_search'),
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (text) => _onSearchChanged(catalog, text),
        onSubmitted: (text) {
          _debounce?.cancel();
          _runSearch(catalog, text);
        },
        decoration: InputDecoration(
          hintText: FirstAidCopy.of(language, 'searchHint'),
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Tk.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Tk.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Tk.line)),
        ),
      ),
      if (_searchRan && _searchGuides.isEmpty && !_searchThreat) ...[
        const SizedBox(height: 10),
        Text(
          FirstAidCopy.of(language, 'searchNoMatch'),
          style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: Tk.warnInk),
        ),
      ],
      const SizedBox(height: 16),
      for (final category in kCategories) ...[
        _categoryTile(category, language),
        const SizedBox(height: 10),
      ],
      _somethingElseTile(language),
    ],
  );

  Widget _categoryTile(String category, FirstAidLanguage language) {
    final style = _categoryStyle(category);
    return Semantics(
      button: true,
      label: firstAidCategoryLabel(category, language),
      child: Material(
        color: Tk.card,
        borderRadius: BorderRadius.circular(Tk.rCard),
        child: InkWell(
          key: ValueKey('first_aid_category_$category'),
          borderRadius: BorderRadius.circular(Tk.rCard),
          onTap: () => _pickCategory(category),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
                  child: Icon(style.icon, color: style.foreground, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    firstAidCategoryLabel(category, language),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Tk.ink),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Tk.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _somethingElseTile(FirstAidLanguage language) => Semantics(
    button: true,
    label: FirstAidCopy.of(language, 'somethingElse'),
    child: Material(
      color: Tk.brandTint,
      borderRadius: BorderRadius.circular(Tk.rCard),
      child: InkWell(
        key: const ValueKey('first_aid_something_else'),
        borderRadius: BorderRadius.circular(Tk.rCard),
        onTap: () => setState(() {
          _listKind = _ListKind.all;
          _listCategory = null;
          _stage = _Stage.list;
        }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.more_horiz, color: Tk.brandDeep, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FirstAidCopy.of(language, 'somethingElse'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Tk.brandDeep),
                    ),
                    Text(
                      FirstAidCopy.of(language, 'somethingElseHint'),
                      style: const TextStyle(fontSize: 13, color: Tk.mute),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Tk.brandDeep),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _listView(FirstAidCatalog catalog, FirstAidLanguage language) {
    final guides = _guidesForList(catalog);
    final title = switch (_listKind) {
      _ListKind.alert => FirstAidCopy.of(language, 'firstAidForEmergency'),
      _ListKind.category => firstAidCategoryLabel(_listCategory ?? '', language),
      _ListKind.search => FirstAidCopy.of(language, 'isThisWhat'),
      _ListKind.all => FirstAidCopy.of(language, 'allGuides'),
    };
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: Tk.ink),
              ),
              if (_listKind == _ListKind.search && _searchThreat) ...[
                const SizedBox(height: 14),
                FirstAidCallPanel(
                  language: language,
                  message: FirstAidCopy.of(language, 'immediateThreat'),
                ),
              ],
              if (guides.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final guide in guides) ...[
                  FirstAidGuideTile(
                    title: guide.titleFor(language),
                    stepsLabel: FirstAidCopy.fill(
                      FirstAidCopy.of(language, 'stepsCount'),
                      {'n': guide.steps.length},
                    ),
                    onTap: () => _openGuide(guide),
                  ),
                  const SizedBox(height: 10),
                ],
              ] else ...[
                const SizedBox(height: 14),
                FirstAidCallPanel(
                  language: language,
                  message: FirstAidCopy.of(
                    language,
                    _guideWaiting
                        ? 'guideWaiting'
                        : (catalog.visibleGuides.isEmpty ? 'noApprovedGuide' : 'noGuideFor'),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Kept out of the scroll so a long category list can never hide the way out.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextButton(
            key: const ValueKey('first_aid_choose_different'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _toPicker,
            child: Text(
              FirstAidCopy.of(language, 'chooseDifferent'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tk.brandDeep),
            ),
          ),
        ),
      ],
    );
  }

  List<FirstAidGuide> _guidesForList(FirstAidCatalog catalog) => switch (_listKind) {
    _ListKind.alert => firstAidGuidesForIncident(
      catalog.visibleGuides,
      category: widget.category,
      subtype: widget.subtype,
    ),
    _ListKind.category => firstAidGuidesForCategory(
      catalog.visibleGuides,
      _listCategory ?? '',
    ),
    _ListKind.search => _searchGuides,
    _ListKind.all => catalog.visibleGuides,
  };

  Widget _flowView(FirstAidCatalog catalog, FirstAidLanguage language) {
    final flow = catalog.flows['medical_start'];
    FirstAidFlowNode? node;
    if (flow != null) node = flow.node(_flowNode ?? flow.nodes.first.id);
    if (flow == null || node == null) {
      // A broken flow falls back to the plain topic list, never to invented questions.
      return _listView(catalog, language);
    }
    final question = node;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(
          firstAidCategoryLabel('Medical Emergency', language),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tk.faint),
        ),
        const SizedBox(height: 10),
        Text(
          question.text.of(language),
          key: const ValueKey('first_aid_flow_question'),
          style: const TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w800, color: Tk.ink),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 64,
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('first_aid_flow_yes'),
            onPressed: () => _answer(catalog, flow, question, yes: true),
            child: Text(
              FirstAidCopy.of(language, 'yes'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          width: double.infinity,
          child: OutlinedButton(
            key: const ValueKey('first_aid_flow_no'),
            onPressed: () => _answer(catalog, flow, question, yes: false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Tk.brand, width: 2),
              foregroundColor: Tk.brandDeep,
            ),
            child: Text(
              FirstAidCopy.of(language, 'no'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: _medicalTopics,
          child: Text(
            FirstAidCopy.of(language, 'seeAllMedical'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tk.brandDeep),
          ),
        ),
        TextButton(
          key: const ValueKey('first_aid_choose_different'),
          onPressed: _toPicker,
          child: Text(
            FirstAidCopy.of(language, 'chooseDifferent'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tk.brandDeep),
          ),
        ),
      ],
    );
  }

  Widget _errorView(FirstAidLanguage language) => Column(
    children: [
      Expanded(
        child: ErrorState(
          title: FirstAidCopy.of(language, 'loadErrorTitle'),
          message: FirstAidCopy.of(language, 'loadErrorBody'),
          retryLabel: FirstAidCopy.of(language, 'tryAgain'),
          onRetry: () => setState(() => _bindCatalog(force: true)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FirstAidCallPanel(language: language),
      ),
    ],
  );
}

({IconData icon, Color background, Color foreground}) _categoryStyle(String category) =>
    switch (category) {
      'Medical Emergency' => (icon: Icons.medical_services, background: const Color(0xFFE8F5E9), foreground: const Color(0xFF2E7D32)),
      'Road Accident' => (icon: Icons.directions_car, background: const Color(0xFFE3F2FD), foreground: const Color(0xFF1565C0)),
      'Fire & Rescue' => (icon: Icons.local_fire_department, background: const Color(0xFFFFF3E0), foreground: const Color(0xFFE65100)),
      'Security Threat' => (icon: Icons.shield, background: const Color(0xFFF3E5F5), foreground: const Color(0xFF6A1B9A)),
      'Abduction' => (icon: Icons.person_search, background: const Color(0xFFFFEBEE), foreground: const Color(0xFFAD1457)),
      _ => (icon: Icons.more_horiz, background: const Color(0xFFF5F5F5), foreground: const Color(0xFF616161)),
    };
