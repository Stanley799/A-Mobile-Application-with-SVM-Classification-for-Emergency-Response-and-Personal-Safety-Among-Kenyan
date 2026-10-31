import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/category_style.dart';

/// "Send alert for the category?" Shown before any alert is created, from the SOS picker and the dashboard tiles.
/// Pops true on "Send alert" and false on "Cancel". Nothing here closes by itself.
class SosConfirmationSheet extends StatelessWidget {
  const SosConfirmationSheet({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(category);
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: style.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, size: 32, color: style.foreground),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Send alert for $category?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Emergency responders will be alerted and your location shared with them.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 60,
              child: FilledButton(
                key: const ValueKey('sos-confirm-send'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sos,
                  foregroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Send alert',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                key: const ValueKey('sos-confirm-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
