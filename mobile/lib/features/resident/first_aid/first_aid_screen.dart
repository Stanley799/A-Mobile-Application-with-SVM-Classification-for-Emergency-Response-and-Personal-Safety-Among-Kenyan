import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Guided first aid. Part 3 adds the entries; Part 6 supplies the approved guides.
class FirstAidScreen extends StatelessWidget {
  const FirstAidScreen({super.key, this.category, this.subtype});
  final String? category;
  final String? subtype;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('First aid')),
    body: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (category != null) ...[
            Text(category!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
          ],
          const Text(
            'The guided steps for this emergency are being prepared. If someone is in danger, call 999 now.',
            style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}
