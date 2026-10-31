import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/dispatch_models.dart';
import '../../../core/models/triage_outcome.dart';
import '../../../core/services/priority_classifier.dart';
import '../../../core/services/triage_text_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/triage/subtype_labels.dart';
import '../../../core/triage/triage_schema.dart';
import '../../../core/utils/incident_id.dart';
import '../status/alert_status_body.dart';
import '../map/help_repository.dart';
import 'category_style.dart';
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

enum _Stage { chooseOtherType, safety, quick, done }

class AlertStatusSheet extends StatefulWidget {
  const AlertStatusSheet({
    super.key,
    required this.incidentRef,
    required this.createFuture,
    required this.retryCreate,
    required this.category,
    required this.locationShared,
    this.onRaiseAlert,
    this.repo,
    this.dispatch,
    this.initialDescription,
  });

  final DocumentReference<Map<String, dynamic>> incidentRef;
  final Future<void> createFuture;
  final Future<void> Function() retryCreate;
  final String category;
  final bool locationShared;
  final VoidCallback? onRaiseAlert;
  final HelpRepository? repo;
  final Stream<DispatchInfo>? dispatch;

  /// What the person typed in the SOS picker, if anything. Opens the sheet on the right question.
  final FreeTextResult? initialDescription;

  @override
  State<AlertStatusSheet> createState() => _AlertStatusSheetState();
}

class _AlertStatusSheetState extends State<AlertStatusSheet> {
  late String _category;
  String? _subtype;
  final Map<String, String> _answers = {};
  late _Stage _stage;

  bool _createFailed = false;
  bool _docSeen = false;
  bool _hasPendingWrites = true;
  bool _retrying = false;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  Timer? _retryTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  DateTime? _recordedAt;
  int _quickIndex = 0;
  String _typedText = '';
  bool _textConsent = false;
  List<String> _textFlags = const [];
  bool _detailsCompleted = false;
  bool _supportMode = false;
  bool _classified = false; // a category or a text description was submitted
  bool _cancelWrite = false; // the Cancelled write was already attempted

  @override
  void initState() {
    super.initState();
    // The category was already chosen and confirmed before this sheet opened. Go straight to the quick questions.
    // 'SOS' is the old name for "nothing chosen yet" and still means Other / General.
    _category = widget.category == 'SOS' ? 'Other / General' : widget.category;
    _stage = _Stage.quick;
    final described = widget.initialDescription;
    if (described != null) {
      _applyDescription(described);
      _saveDescriptionFeedback();
      _saveQuickProgress();
    } else if (_category == 'Other / General') {
      _stage = _Stage.chooseOtherType;
    }
    _classified = described != null || _category != 'Other / General';

    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    widget.createFuture
        .then((_) {
          if (mounted) {
            setState(() {
              _recordedAt ??= DateTime.now();
            });
          }
        })
        .catchError((err) {
          debugPrint('Create incident error: $err');
          if (mounted) {
            setState(() {
              _createFailed = true;
            });
            _startAutoRetry();
          }
        });

    _docSub = widget.incidentRef
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _docSeen = snap.exists;
              _hasPendingWrites = snap.metadata.hasPendingWrites;
            });
            if (snap.exists && !snap.metadata.hasPendingWrites) {
              setState(() {
                _recordedAt ??= DateTime.now();
              });
            }
          },
          onError: (err) {
            debugPrint('Incident doc snapshot error: $err');
          },
        );
  }

  /// While the banner is on screen we keep trying, silently, every five seconds.
  void _startAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _retrying || !_createFailed) return;
      unawaited(_handleRetry());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    _docSub?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_retrying) return;
    _retrying = true;
    setState(() {
      _createFailed = false;
    });
    try {
      final serverSnap = await widget.incidentRef.get(
        const GetOptions(source: Source.server),
      );
      if (serverSnap.exists && mounted) {
        _retryTimer?.cancel();
        setState(() {
          _recordedAt ??= DateTime.now();
        });
        return;
      }
    } catch (_) {}

    try {
      await widget.retryCreate();
      if (mounted) {
        _retryTimer?.cancel();
        setState(() {
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
    } finally {
      _retrying = false;
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
        if (_typedText.trim().isNotEmpty) 'input': 'text_description',
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

  bool get _canShareText =>
      (kSubtypeRules[_subtype]?.shareFreeTextWithResponder ?? true) &&
      !(_category == 'Other / General' && _subtype == null);

  void _saveDescriptionFeedback() {
    if (!_textConsent || _typedText.trim().isEmpty || !_canShareText) return;
    unawaited(
      TriageTextService().saveFeedback(
        text: _typedText,
        confirmedCategory: _category,
        confirmedSubtype: _subtype,
      ),
    );
  }

  /// Applies what was typed in the SOS picker. No setState: only called from initState.
  void _applyDescription(FreeTextResult result) {
    final category = result.chosenCategory;
    final suggestion = result.suggestion;
    _typedText = result.text;
    _textConsent = result.consent;
    _textFlags = suggestion?.flags ?? const [];
    if (category != null) {
      _category = category;
      _subtype =
          suggestion?.category == category &&
              (kCategorySubtypes[category] ?? const <String>[]).contains(
                suggestion?.subtype,
              )
          ? suggestion?.subtype
          : null;
    }
    _answers.clear();
    _quickIndex = 0;
    _stage = _subtype == 'emotional_distress'
        ? _Stage.safety
        : _category == 'Other / General' && _subtype == null
        ? _Stage.chooseOtherType
        : _Stage.quick;
  }

  void _onSelectOtherSubtype(String sub) {
    _classified = true;
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
      _saveDescriptionFeedback();
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
    final isLastAnswer = _quickIndex >= _quickQuestionIds.length - 1;
    setState(() {
      _answers[questionId] = val;
      if (!isLastAnswer) {
        _quickIndex++;
      } else {
        _stage = _Stage.done;
      }
    });
    if (isLastAnswer) {
      unawaited(_completeQuickTriage());
    } else {
      _saveQuickProgress();
    }
  }

  Future<void> _completeQuickTriage() async {
    await PriorityClassifier.instance.ensureLoaded();
    if (!mounted) return;
    final result = PriorityClassifier.instance.classify(
      category: _category,
      answers: _answers,
      subtype: _subtype,
    );
    _saveCompleteOutcome(
      TriageOutcome(
        category: _category,
        subtype: _subtype,
        answers: Map<String, String>.of(_answers),
        priority: result.priority,
        confidence: result.confidence,
        needsHumanReview: result.needsHumanReview,
        source: result.source,
        fallbackReason: result.fallbackReason,
        description: _canShareText && _typedText.trim().isNotEmpty
            ? _typedText.trim()
            : null,
        flags: _textFlags,
        saveForTraining: false,
        supportOnly: false,
        schemaVersion: kTriageSchemaVersion,
      ),
    );
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

  Future<void> _onCloseRequested() async {
    if (_classified) {
      Navigator.of(context).pop();
      return;
    }
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this alert?'),
        content: const Text(
          'No emergency category or description was given, so no help is being sent. The alert will be saved as Cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep alert'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel alert'),
          ),
        ],
      ),
    );
    if (cancel == true && mounted) Navigator.of(context).pop();
  }

  /// Runs when the sheet actually pops: an unclassified alert must not keep dispatching.
  Future<void> _cancelIfUnclassified() async {
    if (_classified || _cancelWrite || _createFailed) return;
    _cancelWrite = true;
    try {
      await widget.incidentRef.update({
        'status': 'Cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (err) {
      debugPrint('Cancel unclassified incident error: $err');
    }
  }

  Future<void> _call999() async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: '999'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not open the dialer. Please dial 999.')),
        );
      }
    }
  }

  /// Sending failed: one plain sentence, one big call button, and a quiet retry loop underneath.
  Widget _buildFailureBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.sosLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your alert has not been sent yet. Call 999 now.',
            style: TextStyle(
              fontSize: 18,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: AppColors.sosDeep,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 56,
            child: Semantics(
              button: true,
              label: 'Call 999 now',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sos,
                  foregroundColor: AppColors.surface,
                ),
                onPressed: _call999,
                icon: const Icon(Icons.call, size: 24),
                label: const Text(
                  'Call 999',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'We keep trying to send it every 5 seconds.',
            style: TextStyle(fontSize: 13, color: AppColors.sosDeep),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _retrying ? null : _handleRetry,
              child: Text(_retrying ? 'Trying again…' : 'Try again now'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cStyle = categoryStyle(_category);
    final refStr = incidentReference(widget.incidentRef.id);
    final phase = alertPhase(
      createDone: _recordedAt != null,
      createFailed: _createFailed,
      hasPendingWrites: _hasPendingWrites,
      docSeen: _docSeen,
      secondsSinceStart: _stopwatch.elapsed.inSeconds,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_cancelIfUnclassified());
        } else {
          unawaited(_onCloseRequested());
        }
      },
      child: Column(
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
              Expanded(
                child: Column(
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
                          Flexible(
                            child: Text(
                              _category,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cStyle.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _classified ? 'Close' : 'Cancel alert',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
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
            child: _createFailed
                ? _buildFailureBanner()
                : _supportMode
                ? _buildSupportContent()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The quick questions sit above the status while the alert goes out.
                      if (_stage != _Stage.done) ...[
                        _buildStageContent(),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      KeyedSubtree(
                        key: const ValueKey('alert-status-body'),
                        child: AlertStatusBody(
                        incidentId: widget.incidentRef.id,
                        categoryLabel: _category,
                        priorityLabel: 'High',
                        reference: refStr,
                        receivedAt: _recordedAt ?? DateTime.now(),
                        detailsPending: !_detailsCompleted,
                        onAddDetails: _openMoreDetailsSheet,
                        repo: widget.repo,
                        dispatch: widget.dispatch,
                        sending:
                            phase == AlertPhase.sending ||
                            phase == AlertPhase.savedOffline,
                        onRaiseAlert: widget.onRaiseAlert,
                        ),
                      ),
                      if (_stage == _Stage.done) ...[
                        const SizedBox(height: AppSpacing.md),
                        _buildHotlines(),
                      ],
                    ],
                  ),
          ),
        ),
      ],
      ),
    );
  }



  Widget _buildStageContent() {
    switch (_stage) {
      case _Stage.chooseOtherType:
        return _buildChooseOtherType();
      case _Stage.safety:
        return _buildSafetyQuestion();
      case _Stage.quick:
        return _buildQuickQuestions();
      case _Stage.done:
        return const SizedBox.shrink();
    }
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
    final prompt =
        rule?.safetyQuestion ?? 'Are you thinking of harming yourself?';

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
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

  /// Shown instead of the dispatch status when the person said they are not thinking of harming themselves.
  Widget _buildSupportContent() {
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

  /// Extra helplines for this kind of emergency (for example the GBV or child helpline).
  /// The 999 and 922 buttons are already part of the status above.
  Widget _buildHotlines() {
    final extra = [
      for (final h in hotlinesFor(_subtype))
        if (h.showWhen != 'always') h,
    ];
    if (extra.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in extra) ...[
          HotlineCard(hotline: h),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}
