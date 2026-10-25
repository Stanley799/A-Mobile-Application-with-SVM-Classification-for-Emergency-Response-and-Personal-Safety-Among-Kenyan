import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/triage/triage_schema.dart';

/// Verified hotlines for [subtype]. 922 is always included; 999/112/116 stay hidden until verified.
List<Hotline> hotlinesFor(String? subtype) => [
  for (final h in kHotlines)
    if (h.verified &&
        (h.showWhen == 'always' ||
            (subtype != null && h.showWhen.split(',').contains(subtype))))
      h,
];

/// A phone number with a one-tap call button.
class HotlineCard extends StatelessWidget {
  const HotlineCard({super.key, required this.hotline});

  final Hotline hotline;

  Future<void> _call(BuildContext context) async {
    var launched = false;
    try {
      launched = await launchUrl(Uri(scheme: 'tel', path: hotline.number));
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please dial ${hotline.number}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      boxShadow: AppShadows.card,
    ),
    child: Row(
      children: [
        const Icon(Icons.phone_in_talk, color: AppColors.sos),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hotline.number,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                hotline.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.sos,
            minimumSize: const Size(88, 48),
          ),
          onPressed: () => _call(context),
          child: const Text('Call'),
        ),
      ],
    ),
  );
}
