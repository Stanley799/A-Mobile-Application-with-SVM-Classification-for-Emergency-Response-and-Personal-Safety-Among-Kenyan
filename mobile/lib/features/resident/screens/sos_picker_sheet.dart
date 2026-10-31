import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/other_free_text_sheet.dart';

/// The five categories on the SOS picker. "Other / General" is not one of them:
/// the description box below covers anything that does not fit.
const List<String> kSosPickerCategories = [
  'Medical Emergency',
  'Road Accident',
  'Fire & Rescue',
  'Security Threat',
  'Abduction',
];

/// What the person chose in the picker. Nothing has been sent yet.
class SosChoice {
  const SosChoice(this.category, {this.description});

  final String category;

  /// Set when the person described it in words instead of tapping a category.
  final FreeTextResult? description;
}

/// Opened by the SOS button. Pops a [SosChoice], or null when closed.
class SosPickerSheet extends StatelessWidget {
  const SosPickerSheet({super.key});

  void _onDescribed(BuildContext context, FreeTextResult r) {
    final chosen = r.chosenCategory;
    if (chosen == null && r.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      SosChoice(chosen ?? 'Other / General', description: r),
    );
  }

  Widget _tile(BuildContext context, String cat) {
    final style = categoryStyle(cat);
    return Material(
      color: style.background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: ValueKey('sos-cat-$cat'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).pop(SosChoice(cat)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, size: 20, color: style.foreground),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  cat,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pair(BuildContext context, String a, String b) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _tile(context, a)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _tile(context, b)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = kSosPickerCategories;
    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What is happening?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tap the closest match, or describe it below. Nothing is sent until you confirm.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pair(context, c[0], c[1]),
                    const SizedBox(height: AppSpacing.md),
                    _pair(context, c[2], c[3]),
                    const SizedBox(height: AppSpacing.md),
                    _tile(context, c[4]),
                    const SizedBox(height: AppSpacing.xl),
                    const Center(
                      child: Text(
                        'or',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FreeTextStep(
                      key: const ValueKey('sos-describe'),
                      suggestMode: true,
                      initialText: '',
                      initialConsent: false,
                      onContinue: (r) => _onDescribed(context, r),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
