import 'package:flutter/material.dart';

import '../../../core/models/triage_outcome.dart';
import '../../../core/services/priority_classifier.dart';
import '../../../core/services/triage_text_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/triage/subtype_labels.dart';
import '../../../core/triage/triage_schema.dart';
import 'hotline_card.dart';
import 'other_free_text_sheet.dart';

String _valueLabel(TriageQuestion q, String value) =>
    q.labels[value] ?? (value == 'Unknown' ? 'Not sure' : value);

enum _Kind { describe, subtype, safety, question, details, result }

class _Step {
  const _Step(this.kind, [this.questionId]);
  final _Kind kind;
  final String? questionId;
}

/// Quick follow-up questions shown AFTER the alert has been sent.
/// Closing the sheet early is always allowed: the alert stays High until it is completed.
/// Pops a [TriageOutcome] when finished, or null when skipped.
class TriageQuestionSheet extends StatefulWidget {
  const TriageQuestionSheet({
    super.key,
    required this.category,
    required this.startWithDescribe,
    this.initialAnswers = const {},
    this.initialSubtype,
  });

  final String category;
  final bool startWithDescribe;
  final Map<String, String> initialAnswers;
  final String? initialSubtype;

  @override
  State<TriageQuestionSheet> createState() => _TriageQuestionSheetState();
}

class _TriageQuestionSheetState extends State<TriageQuestionSheet> {
  late String _category = widget.category;
  late final Map<String, String> _answers = Map.of(widget.initialAnswers);
  late String? _subtype = widget.initialSubtype;
  String? _suggestedSubtype;
  bool _distressChecked = false;
  String _text = '';
  bool _consent = false;
  TextSuggestion? _suggestion;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    PriorityClassifier.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  // ---- which questions apply -------------------------------------------------------------------------------------

  List<String> _askedQuestions() {
    final asked = <String>[];
    for (final id in kCategoryQuestions[_category] ?? const <String>[]) {
      final q = kQuestions[id];
      if (q == null) continue;
      final applies = q.askIf.entries.every(
        (e) => e.value.contains(_answers[e.key]),
      );
      if (applies) asked.add(id);
    }
    return asked;
  }

  void _prune() {
    final asked = _askedQuestions().toSet();
    // Do not prune initial answers that were passed into the sheet.
    _answers.removeWhere((id, _) => !asked.contains(id) && !widget.initialAnswers.containsKey(id));
  }

  bool get _canShareText =>
      kSubtypeRules[_subtype]?.shareFreeTextWithResponder ?? true;

  List<_Step> _steps() {
    final steps = <_Step>[
      if (widget.startWithDescribe) const _Step(_Kind.describe),
      if (_subtype == null) const _Step(_Kind.subtype),
    ];
    if (_subtype == 'emotional_distress' || _distressChecked) {
      steps.add(const _Step(_Kind.safety));
    }
    if (_subtype == 'emotional_distress' && !_distressChecked) return steps;
    if (kSubtypeRules[_subtype]?.dispatchResponder == false) {
      steps.add(const _Step(_Kind.result));
      return steps;
    }
    for (final id in _askedQuestions()) {
      if (!widget.initialAnswers.containsKey(id)) {
        steps.add(_Step(_Kind.question, id));
      }
    }
    if (!widget.startWithDescribe && _canShareText) {
      steps.add(const _Step(_Kind.details));
    }
    steps.add(const _Step(_Kind.result));
    return steps;
  }

  // ---- answers ---------------------------------------------------------------------------------------------------

  void _onDescribed(FreeTextResult r) => setState(() {
    _text = r.text;
    _consent = r.consent;
    _suggestion = r.suggestion;
    final chosen = r.chosenCategory;
    if (chosen != null && chosen != _category) {
      _category = chosen;
      _answers.clear();
      _subtype = null;
      _distressChecked = false;
    }
    final s = r.suggestion;
    _suggestedSubtype =
        (s != null &&
            s.category == _category &&
            (kCategorySubtypes[_category] ?? const <String>[]).contains(s.subtype))
        ? s.subtype
        : null;
    _index++;
  });

  void _onSubtype(String? value) => setState(() {
    _subtype = value;
    _distressChecked = false;
    _prune();
    _index++;
  });

  void _onSafety(bool thinkingOfHarm) => setState(() {
    _distressChecked = true;
    _subtype = thinkingOfHarm ? 'mental_health_crisis' : 'emotional_distress';
    _index++;
  });

  void _onAnswer(String id, String value) => setState(() {
    _answers[id] = value;
    _prune();
    _index++;
  });

  void _onDetails(FreeTextResult r) => setState(() {
    _text = r.text;
    _consent = r.consent;
    _index++;
  });

  // ---- result ----------------------------------------------------------------------------------------------------

  TriageOutcome _outcome() {
    final answers = Map<String, String>.of(_answers);
    final text = _text.trim();
    final share = _canShareText && text.isNotEmpty;
    final supportOnly = kSubtypeRules[_subtype]?.dispatchResponder == false;
    final PriorityResult r = supportOnly
        ? const PriorityResult(
            priority: 'Low',
            confidence: 1,
            needsHumanReview: true,
            source: 'support_only',
          )
        : PriorityClassifier.instance.classify(
            category: _category,
            answers: answers,
            subtype: _subtype,
          );
    return TriageOutcome(
      category: _category,
      subtype: _subtype,
      answers: answers,
      priority: r.priority,
      confidence: r.confidence,
      needsHumanReview: r.needsHumanReview,
      source: r.source,
      fallbackReason: r.fallbackReason,
      description: share ? text : null,
      flags: _suggestion?.flags ?? const [],
      saveForTraining: share && _consent,
      supportOnly: supportOnly,
      schemaVersion: kTriageSchemaVersion,
    );
  }

  // ---- screen ----------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    final index = _index < steps.length ? _index : steps.length - 1;
    final step = steps[index];
    final onResult = step.kind == _Kind.result;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: index > 0 && !onResult
                        ? IconButton(
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => setState(() => _index = index - 1),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      onResult ? 'Done' : 'More details',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: onResult
                        ? null
                        : TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Skip'),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: LinearProgressIndicator(
                value: (index + 1) / steps.length,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
                backgroundColor: AppColors.divider,
                color: AppColors.brand,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                child: _body(step),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(_Step step) {
    switch (step.kind) {
      case _Kind.describe:
        return FreeTextStep(
          key: const ValueKey('describe'),
          suggestMode: true,
          initialText: _text,
          initialConsent: _consent,
          onContinue: _onDescribed,
        );
      case _Kind.details:
        return FreeTextStep(
          key: const ValueKey('details'),
          suggestMode: false,
          initialText: _text,
          initialConsent: _consent,
          onContinue: _onDetails,
        );
      case _Kind.subtype:
        return _OptionsStep(
          key: ValueKey('subtype-$_category'),
          title: 'What best describes what is happening?',
          subtitle: _category,
          options: [
            for (final id in kCategorySubtypes[_category] ?? const <String>[])
              (value: id, label: subtypeLabel(id)),
          ],
          selected: _subtype,
          badgeValue: _suggestedSubtype,
          onPick: _onSubtype,
          skipLabel: 'Not sure, skip',
          onSkip: () => _onSubtype(null),
        );
      case _Kind.safety:
        return _OptionsStep(
          key: const ValueKey('safety'),
          title: kSubtypeRules['emotional_distress']?.safetyQuestion ??
              'Are you thinking of harming yourself?',
          subtitle: 'Your answer helps us decide what support to offer.',
          options: const [
            (value: 'yes', label: 'Yes'),
            (value: 'no', label: 'No'),
          ],
          selected: _distressChecked
              ? (_subtype == 'mental_health_crisis' ? 'yes' : 'no')
              : null,
          onPick: (v) => _onSafety(v == 'yes'),
        );
      case _Kind.question:
        final q = kQuestions[step.questionId]!;
        if (q.type == 'int') {
          return _OptionsStep(
            key: ValueKey(q.id),
            title: q.prompt,
            options: [
              for (var n = q.min; n <= q.max; n++)
                (value: '$n', label: n == q.max ? '$n or more' : '$n'),
            ],
            selected: _answers[q.id],
            onPick: (v) => _onAnswer(q.id, v!),
          );
        }
        return _OptionsStep(
          key: ValueKey(q.id),
          title: q.prompt,
          options: [for (final v in q.values) (value: v, label: _valueLabel(q, v))],
          selected: _answers[q.id],
          onPick: (v) => _onAnswer(q.id, v!),
        );
      case _Kind.result:
        return _ResultStep(outcome: _outcome());
    }
  }
}

typedef _Option = ({String value, String label});

/// One question, one big tap per answer.
class _OptionsStep extends StatelessWidget {
  const _OptionsStep({
    super.key,
    required this.title,
    required this.options,
    required this.onPick,
    this.subtitle,
    this.selected,
    this.badgeValue,
    this.skipLabel,
    this.onSkip,
  });

  final String title;
  final String? subtitle;
  final List<_Option> options;
  final String? selected;
  final String? badgeValue;
  final ValueChanged<String?> onPick;
  final String? skipLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subtitle != null) ...[
          Text(subtitle!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontSize: 22)),
        const SizedBox(height: AppSpacing.xl),
        for (final o in options) ...[
          Material(
            color: o.value == selected ? AppColors.brandLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => onPick(o.value),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: o.value == selected ? AppColors.brand : AppColors.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (o.value == badgeValue)
                      const Text(
                        'Suggested',
                        style: TextStyle(fontSize: 12, color: AppColors.brand),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (skipLabel != null && onSkip != null)
          TextButton(onPressed: onSkip, child: Text(skipLabel!)),
      ],
    );
  }
}

/// Last screen: confirms the alert was updated and shows the verified hotlines.
class _ResultStep extends StatelessWidget {
  const _ResultStep({required this.outcome});

  final TriageOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidential = kSubtypeRules[outcome.subtype]?.confidential ?? false;
    final message = outcome.supportOnly
        ? 'Thank you for telling us. You are not alone. Support is below, and you can call at any time.'
        : 'Your alert has been updated with these details.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, size: 56, color: AppColors.success),
        const SizedBox(height: AppSpacing.lg),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        if (confidential) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Anything you typed is not shared with responders.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        for (final h in hotlinesFor(outcome.subtype)) ...[
          HotlineCard(hotline: h),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.of(context).pop(outcome),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
