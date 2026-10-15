import 'package:flutter/material.dart';

import '../../../core/services/triage_text_service.dart';
import '../../../core/theme/app_theme.dart';
import 'hotline_card.dart';

/// What the resident typed, the box they ticked and the category they confirmed.
class FreeTextResult {
  const FreeTextResult({
    required this.text,
    required this.consent,
    this.suggestion,
    this.chosenCategory,
  });

  final String text;
  final bool consent;
  final TextSuggestion? suggestion;
  final String? chosenCategory;
}

/// An optional description box.
/// With [suggestMode] (used for Other / General) the server suggests a category and the resident confirms it.
/// Without it (used at the end of other categories) the text is just extra detail for responders.
class FreeTextStep extends StatefulWidget {
  const FreeTextStep({
    super.key,
    required this.suggestMode,
    required this.initialText,
    required this.initialConsent,
    required this.onContinue,
  });

  final bool suggestMode;
  final String initialText;
  final bool initialConsent;
  final ValueChanged<FreeTextResult> onContinue;

  @override
  State<FreeTextStep> createState() => _FreeTextStepState();
}

class _FreeTextStepState extends State<FreeTextStep> {
  late final TextEditingController _controller;
  final TriageTextService _service = TriageTextService();
  late bool _consent;
  bool _loading = false;
  bool _failed = false;
  TextSuggestion? _suggestion;
  String? _chosen;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText)
      ..addListener(() => setState(() {}));
    _consent = widget.initialConsent;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text.trim();

  bool get _needsSuggestion =>
      widget.suggestMode && _text.length >= 3 && _suggestion == null && !_failed;

  Future<void> _suggest() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final suggestion = await _service.suggest(_text);
    if (!mounted) return;
    String? pick;
    if (suggestion != null &&
        suggestion.category != null &&
        !suggestion.needsClarification) {
      pick = suggestion.category;
    }
    setState(() {
      _loading = false;
      _suggestion = suggestion;
      _failed = suggestion == null;
      _chosen = pick;
    });
  }

  void _continue() {
    widget.onContinue(
      FreeTextResult(
        text: _text,
        consent: _consent && _text.isNotEmpty,
        suggestion: _suggestion,
        chosenCategory: widget.suggestMode ? _chosen : null,
      ),
    );
  }

  List<String> get _options {
    final s = _suggestion;
    if (s == null) return const [];
    final list = <String>[
      if (s.category != null) s.category!,
      ...s.alternatives,
      'Other / General',
    ];
    return list.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _loading
        ? 'Checking...'
        : _text.isEmpty
        ? 'Skip'
        : _needsSuggestion
        ? 'Suggest what this is'
        : 'Continue';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.suggestMode
              ? 'Tell us what is happening'
              : 'Anything else responders should know?',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 22),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.suggestMode
              ? 'Optional. Write in English or Swahili. We will suggest the right type of help and you confirm it.'
              : 'Optional. Keep it short.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _controller,
          maxLength: 280,
          maxLines: 4,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Describe what is happening',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        if (_suggestion?.mentionsSelfHarm ?? false) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'You are not alone. If you might hurt yourself, please call now:',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final h in hotlinesFor(null)) HotlineCard(hotline: h),
        ],
        if (_failed) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            "We couldn't suggest a type right now. You can continue.",
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (_options.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Text('This looks like:', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in _options)
                ChoiceChip(
                  label: Text(c),
                  selected: _chosen == c,
                  onSelected: (_) => setState(() => _chosen = c),
                ),
            ],
          ),
        ],
        if (_text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: const Text(
              'Save this description (no name or phone number) to help improve the app. You will still get help if you leave this unticked.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _loading ? null : (_needsSuggestion ? _suggest : _continue),
            child: Text(label),
          ),
        ),
      ],
    );
  }
}
