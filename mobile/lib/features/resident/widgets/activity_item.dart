import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Displays an activity summary with a labeled status indicator.
class ActivityItem extends StatelessWidget {
  const ActivityItem({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.status,
    required this.isIncident,
  });

  final String title;
  final String dateLabel;
  final String status;
  final bool isIncident;

  @override
  Widget build(BuildContext context) {
    final background = isIncident ? AppColors.fireBg : AppColors.successLight;
    final foreground = isIncident ? AppColors.fireFg : AppColors.success;
    // Firestore stores this state without a space; the UI uses natural wording.
    final normalizedStatus = status.toLowerCase() == 'checkedin'
        ? 'Checked In'
        : status;
    final statusColor = status.toLowerCase() == 'active'
        ? AppColors.warningText
        : status.toLowerCase() == 'resolved' ||
              status.toLowerCase() == 'cancelled'
        ? AppColors.textSecondary
        : AppColors.success;
    final statusBackground = status.toLowerCase() == 'active'
        ? AppColors.warningLight
        : statusColor == AppColors.textSecondary
        ? AppColors.neutralLight
        : AppColors.successLight;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIncident ? Icons.warning_amber : Icons.check_circle,
              size: 18,
              color: foreground,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: statusBackground,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              normalizedStatus,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
