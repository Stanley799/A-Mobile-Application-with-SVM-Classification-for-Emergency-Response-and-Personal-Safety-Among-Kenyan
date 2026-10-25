import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/models/dispatch_models.dart';
import '../../../core/models/triage_outcome.dart';
import '../../../core/services/triage_text_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/triage/subtype_labels.dart';
import '../../../core/triage/triage_schema.dart';
import '../../../core/utils/incident_id.dart';
import 'category_style.dart';
import 'dispatch_card.dart';
import '../map/help_map_entry.dart';
import 'hotline_card.dart';
import 'other_free_text_sheet.dart';
import 'triage_question_sheet.dart';

enum AlertPhase { sending, recorded, savedOffline, failed }

AlertPhase alertPhase({
  required bool createDone,
  required bool createFailed,
  required bool hasPendingWrites,
  required bool docSeen,
  required int secondsSinceStart,
}) {
  if (createFailed) return AlertPhase.failed;
  if (createDone || (docSeen && !hasPendingWrites)) return AlertPhase.recorded;
  if (secondsSinceStart >= 8) return AlertPhase.savedOffline;
  return AlertPhase.sending;
}

enum _Stage { chooseCategory, chooseOtherType, safety, quick, done }

class AlertStatusSheet extends StatefulWidget {
  const AlertStatusSheet({
    super.key,
    required this.incidentRef,
    required this.createFuture,
    required this.retryCreate,
    required this.category,
    required this.locationShared,
  });

  final DocumentReference<Map<String, dynamic>> incidentRef;
  final Future<void> createFuture;
  final Future<void> Function() retryCreate;
  final String category;
  final bool locationShared;

  @override
  State<AlertStatusSheet> createState() => _AlertStatusSheetState();
}

class _AlertStatusSheetState extends State<AlertStatusSheet> {
  late String _category;
  String? _subtype;
  final Map<String, String> _answers = {};
  late _Stage _stage;

  bool _createDone = false;
  bool _createFailed = false;
  bool _docSeen = false;
  bool _hasPendingWrites = true;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  DateTime? _recordedAt;
  int _quickIndex = 0;
  bool _isFreeTextMode = false;
  String _typedText = '';
  bool _textConsent = false;
  bool _detailsCompleted = false;
  bool _supportMode = false;

  @override
  void initState() {
    super.initState();
    _category = widget.category == 'SOS' ? 'Other / General' : widget.category;

    if (widget.category == 'SOS') {
      _stage = _Stage.chooseCategory;
      _isFreeTextMode = false;
    } else if (widget.category == 'Other / General') {
      _stage = _Stage.chooseCategory;
      _isFreeTextMode = true;
    } else {
      _stage = _Stage.quick;
    }

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    widget.createFuture.then((_) {
      if (mounted) {
        setState(() {
          _createDone = true;
          _recordedAt ??= DateTime.now();
        });
      }
    }).catchError((err) {
      debugPrint('Create incident error: $err');
      if (mounted) {
        setState(() {
          _createFailed = true;
        });
      }
    });

    _docSub = widget.incidentRef
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _docSeen = snap.exists;
        _hasPendingWrites = snap.metadata.hasPendingWrites;
        if (snap.exists && !snap.metadata.hasPendingWrites) {
          _recordedAt ??= DateTime.now();
        }
      });
    }, onError: (err) {
      debugPrint('Incident doc snapshot error: $err');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _docSub?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  AlertPhase get _phase => alertPhase(
        createDone: _createDone,
        createFailed: _createFailed,
        hasPendingWrites: _hasPendingWrites,
        docSeen: _docSeen,
        secondsSinceStart: _stopwatch.elapsed.inSeconds,
      );

  Future<void> _handleRetry() async {
    setState(() {
      _createFailed = false;
    });
    try {
      final serverSnap = await widget.incidentRef
          .get(const GetOptions(source: Source.server));
      if (serverSnap.exists && mounted) {
        setState(() {
          _createDone = true;
          _recordedAt ??= DateTime.now();
        });
        return;
      }
    } catch (_) {}

    try {
      await widget.retryCreate();
      if (mounted) {
        setState(() {
          _createDone = true;
          _recordedAt ??= DateTime.now();
        });
      }
    } catch (err) {
      debugPrint('Retry create error: $err');
      if (mounted) {
        setState(() {
          _createFailed = true;
        });
      }
    }
  }

  void _saveQuickProgress() {
    final data = <String, Object?>{
      'category': _category,
      if (_subtype != null) 'subtype': _subtype,
      'triage': {
        'answers': Map<String, String>.of(_answers),
        'schemaVersion': kTriageSchemaVersion,
        'stage': 'quick',
      },
      'triageStatus': 'quick',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    unawaited(
      widget.incidentRef.update(data).catchError((err) {
        debugPrint('Quick update error: $err');
      }),
    );
  }

  void _saveCompleteOutcome(TriageOutcome outcome) {
    final data = <String, Object?>{
      ...outcome.toIncidentFields(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    unawaited(
      widget.incidentRef.update(data).catchError((err) {
        debugPrint('Complete update error: $err');
      }),
    );
  }

  Future<void> _callHotline(String number) async {
    var launched = false;
    try {
      launched = await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please dial $number')),
      );
    }
  }

  List<String> get _quickQuestionIds {
    final list = kQuickQuestions[_category] ?? const <String>[];
    assert(() {
      for (final id in list) {
        final q = kQuestions[id];
        if (q == null || q.askIf.isNotEmpty) return false;
      }
      return true;
    }(), 'Quick questions must exist in kQuestions and have empty askIf');
    return list;
  }

  void _onSelectCategoryTile(String cat) {
    if (cat == 'Other / General') {
      setState(() {
        _stage = _Stage.chooseOtherType;
      });
    } else {
      setState(() {
        _category = cat;
        _answers.clear();
        _stage = _Stage.quick;
        _quickIndex = 0;
      });
      _saveQuickProgress();
    }
  }

  void _onSelectOtherSubtype(String sub) {
    if (sub == 'emotional_distress') {
      setState(() {
        _subtype = sub;
        _stage = _Stage.safety;
      });
    } else {
      setState(() {
        _subtype = sub;
        _stage = _Stage.quick;
        _quickIndex = 0;
      });
      _saveQuickProgress();
    }
  }

  void _onSafetyAnswer(bool thinkingOfHarm) {
    if (thinkingOfHarm) {
      setState(() {
        _subtype = 'mental_health_crisis';
        _stage = _Stage.quick;
        _quickIndex = 0;
      });
      _saveQuickProgress();
    } else {
      final outcome = TriageOutcome.supportOnly(
        category: 'Other / General',
        subtype: 'emotional_distress',
      );
      _saveCompleteOutcome(outcome);
      setState(() {
        _subtype = 'emotional_distress';
        _supportMode = true;
        _stage = _Stage.done;
      });
    }
  }

  void _onQuickAnswer(String questionId, String val) {
    setState(() {
      _answers[questionId] = val;
      if (_quickIndex < _quickQuestionIds.length - 1) {
        _quickIndex++;
      } else {
        _stage = _Stage.done;
      }
    });
    _saveQuickProgress();
  }

  Future<void> _openMoreDetailsSheet() async {
    final outcome = await showModalBottomSheet<TriageOutcome>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => TriageQuestionSheet(
        category: _category,
        startWithDescribe: false,
        initialAnswers: _answers,
        initialSubtype: _subtype,
      ),
    );

    if (outcome == null || !mounted) return;

    if (outcome.saveForTraining && outcome.description != null) {
      unawaited(
        TriageTextService().saveFeedback(
          text: outcome.description!,
          confirmedCategory: outcome.category,
          confirmedSubtype: outcome.subtype,
        ),
      );
    }

    _saveCompleteOutcome(outcome);

    setState(() {
      _category = outcome.category;
      _subtype = outcome.subtype;
      _detailsCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cStyle = categoryStyle(_category);
    final refStr = incidentReference(widget.incidentRef.id);

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EMERGENCY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cStyle.background,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cStyle.icon, size: 14, color: cStyle.foreground),
                        const SizedBox(width: 4),
                        Text(
                          _category,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cStyle.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              100,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(refStr),
                const SizedBox(height: AppSpacing.md),
                if (kDispatchEnabled && _phase == AlertPhase.recorded) ...[
                  StreamBuilder<DispatchInfo>(
                    stream: watchDispatch(widget.incidentRef.id),
                    builder: (c, s) => DispatchCard(
                      info: s.data ?? DispatchInfo.empty,
                      onAddDetails: _detailsCompleted ? null : _openMoreDetailsSheet,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  HelpMapEntry(incidentId: widget.incidentRef.id),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (kDispatchEnabled) ...[
                  _buildTimelineCard(),
                  const SizedBox(height: AppSpacing.md),
                ],
                _buildStageContent(),
              ],
            ),
          ),
        ),
        if (!(kDispatchEnabled && _phase == AlertPhase.recorded))
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              boxShadow: AppShadows.navigation,
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sos,
                    foregroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  onPressed: () => _callHotline('922'),
                  icon: const Icon(Icons.phone_in_talk),
                  label: const Text(
                    'Call 922 now',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusCard(String refStr) {
    final phase = _phase;
    Widget iconWidget;
    String title;
    String subtitle;

    switch (phase) {
      case AlertPhase.sending:
        iconWidget = Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.brandLight,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(8),
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
        title = 'Sending your alert';
        subtitle = 'Keep this screen open.';
        break;
      case AlertPhase.recorded:
        iconWidget = Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.successLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle, color: AppColors.success, size: 24),
        );
        title = 'Alert recorded';
        final timeStr = _recordedAt != null
            ? DateFormat('h:mm:ss a').format(_recordedAt!)
            : DateFormat('h:mm:ss a').format(DateTime.now());
        subtitle = 'Received at $timeStr';
        break;
      case AlertPhase.savedOffline:
        iconWidget = Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.warningLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.warning_amber, color: AppColors.warning, size: 24),
        );
        title = 'Saved on this phone';
        subtitle = 'It will send as soon as you are online. Call 922 now.';
        break;
      case AlertPhase.failed:
        iconWidget = Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.sosLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline, color: AppColors.sosDeep, size: 24),
        );
        title = 'We could not record this alert';
        subtitle = 'Please call 922 now.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconWidget,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (phase == AlertPhase.failed) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _handleRetry,
                child: const Text('Retry'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.sosLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: const Text(
                  'High priority',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sosDeep,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.locationShared
                      ? AppColors.brandLight
                      : AppColors.neutralLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  widget.locationShared
                      ? 'Location shared'
                      : 'Location not shared',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.locationShared
                        ? AppColors.brand
                        : AppColors.neutral,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.neutralLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'Ref $refStr',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.neutral,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.success),
              SizedBox(width: AppSpacing.md),
              Text(
                'Alert sent',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.radio_button_checked, size: 18, color: AppColors.brand),
              SizedBox(width: AppSpacing.md),
              Text(
                'Finding the nearest help',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.radio_button_checked, size: 18, color: AppColors.textTertiary),
              SizedBox(width: AppSpacing.md),
              Text(
                'A responder confirms',
                style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case _Stage.chooseCategory:
        return _buildChooseCategory();
      case _Stage.chooseOtherType:
        return _buildChooseOtherType();
      case _Stage.safety:
        return _buildSafetyQuestion();
      case _Stage.quick:
        return _buildQuickQuestions();
      case _Stage.done:
        return _buildDoneContent();
    }
  }

  Widget _buildChooseCategory() {
    if (_isFreeTextMode) {
      return FreeTextStep(
        suggestMode: true,
        initialText: _typedText,
        initialConsent: _textConsent,
        onContinue: (res) {
          setState(() {
            _typedText = res.text;
            _textConsent = res.consent;
            if (res.chosenCategory != null) {
              _onSelectCategoryTile(res.chosenCategory!);
            } else {
              _onSelectCategoryTile('Other / General');
            }
          });
        },
      );
    }

    final categories = <String>[
      'Medical Emergency',
      'Road Accident',
      'Fire & Rescue',
      'Security Threat',
      'Abduction',
      'Something else',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What is happening?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap the closest match. Help does not wait for this.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              mainAxisExtent: 72,
            ),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final realCat = cat == 'Something else' ? 'Other / General' : cat;
              final style = categoryStyle(realCat);

              return Material(
                color: style.background,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: () => _onSelectCategoryTile(cat),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(style.icon, size: 18, color: style.foreground),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            cat,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _isFreeTextMode = true),
              child: const Text('Describe it in words instead'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChooseOtherType() {
    final subtypes = kCategorySubtypes['Other / General'] ?? const <String>[];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What best describes it?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final sub in subtypes) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  side: const BorderSide(color: AppColors.divider),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => _onSelectOtherSubtype(sub),
                child: Text(
                  subtypeLabel(sub),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  Widget _buildSafetyQuestion() {
    final rule = kSubtypeRules['emotional_distress'];
    final prompt = rule?.safetyQuestion ?? 'Are you thinking of harming yourself?';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      side: const BorderSide(color: AppColors.divider),
                    ),
                    onPressed: () => _onSafetyAnswer(true),
                    child: const Text(
                      'Yes',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      side: const BorderSide(color: AppColors.divider),
                    ),
                    onPressed: () => _onSafetyAnswer(false),
                    child: const Text(
                      'No',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestions() {
    final ids = _quickQuestionIds;
    if (_quickIndex >= ids.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _stage = _Stage.done);
      });
      return const SizedBox.shrink();
    }

    final qId = ids[_quickIndex];
    final q = kQuestions[qId]!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '3 QUICK TAPS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${_quickIndex + 1} of ${ids.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < ids.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _quickIndex
                          ? AppColors.brand
                          : AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < ids.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            q.prompt,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final val in q.values) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  side: const BorderSide(color: AppColors.divider),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                ),
                onPressed: () => _onQuickAnswer(qId, val),
                child: Text(
                  q.labels[val] ?? (val == 'Unknown' ? 'Not sure' : val),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (_quickIndex > 0)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _quickIndex--),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _stage = _Stage.done),
                child: const Text('Skip, help is already coming'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDoneContent() {
    if (_supportMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppShadows.card,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are not alone. Support is below.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Reach out anytime to speak with someone who can help.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final h in hotlinesFor('emotional_distress')) ...[
            HotlineCard(hotline: h),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppShadows.card,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What to do now',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'If you need an ambulance, call 922. For police or fire, call 999.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final h in hotlinesFor(_subtype)) ...[
          HotlineCard(hotline: h),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!_detailsCompleted)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add more details',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Optional. Helps responders prepare. About 30 seconds.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton(
                  onPressed: _openMoreDetailsSheet,
                  child: const Text('Add'),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 20),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'Details added',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
