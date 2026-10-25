import 'package:flutter/material.dart';

import '../../../core/services/triage_text_service.dart';
import '../../../core/theme/app_theme.dart';
import 'category_style.dart';
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

/// The Other / free-text sheet where residents describe the emergency first.
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
  TextSuggestion? _suggestion;
  bool _showManualCategories = false;

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

  Future<void> _analyze() async {
    if (_text.isEmpty) return;
    setState(() => _loading = true);
    final suggestion = await _service.suggest(_text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _suggestion = suggestion;
    });
  }

  void _confirmSelection(String category) {
    widget.onContinue(
      FreeTextResult(
        text: _text,
        consent: _consent && _text.isNotEmpty,
        suggestion: _suggestion,
        chosenCategory: category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = _suggestion;

    if (!widget.suggestMode) {
      // Non-suggest mode (Add more details at the end)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Anything else responders should know?',
            style: theme.textTheme.headlineSmall?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Optional. Keep it short.', style: theme.textTheme.bodyMedium),
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
              onPressed: () => widget.onContinue(
                FreeTextResult(
                  text: _text,
                  consent: _consent && _text.isNotEmpty,
                  suggestion: null,
                ),
              ),
              child: Text(_text.isEmpty ? 'Skip' : 'Continue'),
            ),
          ),
        ],
      );
    }

    // Suggest mode for Other / General / SOS
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tell us what is happening',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 22),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Eleza kwa Kiswahili, Sheng au English / Write in Swahili, Sheng or English',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
        const SizedBox(height: AppSpacing.md),
        if (suggestion == null && !_loading) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _text.isEmpty ? null : _analyze,
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showManualCategories = true),
              child: const Text('Or choose a type yourself'),
            ),
          ),
        ],
        if (_loading) ...[
          const Center(child: CircularProgressIndicator()),
        ],
        if (suggestion != null) ...[
          if (suggestion.mentionsSelfHarm || (suggestion.flags.contains('self_harm'))) ...[
            const Text(
              'You are not alone. Support is available now.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.sos),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final h in hotlinesFor('emotional_distress')) ...[
              HotlineCard(hotline: h),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
          if (suggestion.category != null) ...[
            Text(
              'This looks like ${suggestion.category}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _confirmSelection(suggestion.category!),
                child: const Text("Yes, that's right"),
              ),
            ),
            if (suggestion.alternatives.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Text('Not right? Pick:'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final alt in suggestion.alternatives)
                    ActionChip(
                      label: Text(alt),
                      onPressed: () => _confirmSelection(alt),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _showManualCategories = true),
                child: const Text('Choose another type'),
              ),
            ),
          ] else ...[
            // Unclear message
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'We could not understand what happened from your words. Please add a few more details (what you see, who is hurt) or choose the type yourself below. If someone\'s life is in danger, call 999 or 112 now.',
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'Hatukuelewa kilichotokea kutokana na maneno yako. Tafadhali ongeza maelezo kidogo (unachoona, nani ameumia) au chagua aina mwenyewe hapa chini. Ikiwa maisha ya mtu yako hatarini, piga 999 au 112 sasa.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildManualCategoryGrid(),
          ],
        ],
        if (_showManualCategories && suggestion?.category != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildManualCategoryGrid(),
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
      ],
    );
  }

  Widget _buildManualCategoryGrid() {
    const cats = [
      'Medical Emergency',
      'Road Accident',
      'Fire & Rescue',
      'Security Threat',
      'Abduction',
      'Other / General',
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        mainAxisExtent: 72,
      ),
      itemBuilder: (context, index) {
        final cat = cats[index];
        final style = categoryStyle(cat);
        return Material(
          color: style.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => _confirmSelection(cat),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Icon(style.icon, size: 20, color: style.foreground),
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
    );
  }
}
