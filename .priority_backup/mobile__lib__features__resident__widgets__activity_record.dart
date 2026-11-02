import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/triage/subtype_labels.dart';
import '../../../core/triage/triage_schema.dart';
import '../../../core/utils/incident_id.dart';
import 'category_style.dart';

enum StatusTone { info, success, warning, neutral, support }

class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.isAlert,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.priority,
    required this.statusLabel,
    required this.statusTone,
    required this.triageStatus,
    this.category,
  });

  final String id;
  final bool isAlert;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String? priority;
  final String statusLabel;
  final StatusTone statusTone;
  final String triageStatus;
  final String? category;

  factory ActivityRecord.fromIncident(String id, Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.now();

    final cat = data['category'] as String? ?? 'Emergency';
    final subtype = data['subtype'] as String?;
    final isConfidential = kSubtypeRules[subtype]?.confidential ?? false;

    final now = DateTime.now();
    final isToday = createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
    final timeFormat = isToday
        ? DateFormat('h:mm a')
        : DateFormat('MMM d, h:mm a');
    final formattedTime = timeFormat.format(createdAt);
    final ref = incidentReference(id);

    final parts = <String>[];
    if (subtype != null && subtype.isNotEmpty && !isConfidential) {
      parts.add(subtypeLabel(subtype));
    }
    parts.add(formattedTime);
    parts.add('Ref $ref');
    final subtitle = parts.join(' · ');

    final rawStatus = data['status'] as String? ?? 'Active';
    String statusLabel;
    StatusTone tone;

    switch (rawStatus) {
      case 'Active':
        statusLabel = 'Alert sent';
        tone = StatusTone.info;
        break;
      case 'SupportOnly':
        statusLabel = 'Support offered';
        tone = StatusTone.support;
        break;
      case 'Cancelled':
        statusLabel = 'Cancelled';
        tone = StatusTone.neutral;
        break;
      case 'Resolved':
        statusLabel = 'Resolved';
        tone = StatusTone.neutral;
        break;
      default:
        statusLabel = rawStatus;
        tone = StatusTone.neutral;
        break;
    }

    final priority = data['priority'] as String?;
    final triageStatus = data['triageStatus'] as String? ?? 'pending';

    return ActivityRecord(
      id: id,
      isAlert: true,
      title: cat,
      subtitle: subtitle,
      createdAt: createdAt,
      priority: priority,
      statusLabel: statusLabel,
      statusTone: tone,
      triageStatus: triageStatus,
      category: cat,
    );
  }

  factory ActivityRecord.fromCheckin(String id, Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.now();

    final now = DateTime.now();
    final isToday = createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
    final timeFormat = isToday
        ? DateFormat('h:mm a')
        : DateFormat('MMM d, h:mm a');
    final formattedTime = timeFormat.format(createdAt);

    final duration = data['durationMinutes'];
    final subtitle = duration != null
        ? '$duration minutes · $formattedTime'
        : formattedTime;

    final rawStatus = data['status'] as String? ?? 'Active';
    String statusLabel;
    StatusTone tone;

    switch (rawStatus) {
      case 'Active':
        statusLabel = 'In progress';
        tone = StatusTone.warning;
        break;
      case 'CheckedIn':
        statusLabel = 'Checked in';
        tone = StatusTone.success;
        break;
      case 'Cancelled':
        statusLabel = 'Cancelled';
        tone = StatusTone.neutral;
        break;
      case 'Expired':
        statusLabel = 'Expired';
        tone = StatusTone.warning;
        break;
      default:
        statusLabel = rawStatus;
        tone = StatusTone.neutral;
        break;
    }

    return ActivityRecord(
      id: id,
      isAlert: false,
      title: 'Safety check-in',
      subtitle: subtitle,
      createdAt: createdAt,
      priority: null,
      statusLabel: statusLabel,
      statusTone: tone,
      triageStatus: 'complete',
      category: null,
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.record});

  final ActivityRecord record;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color bg;
    final Color fg;

    if (record.isAlert && record.category != null) {
      final style = categoryStyle(record.category!);
      icon = style.icon;
      bg = style.background;
      fg = style.foreground;
    } else {
      icon = Icons.verified_user_outlined;
      bg = AppColors.successLight;
      fg = AppColors.success;
    }

    Color statusBg;
    Color statusFg;

    switch (record.statusTone) {
      case StatusTone.info:
        statusBg = AppColors.infoLight;
        statusFg = AppColors.info;
        break;
      case StatusTone.success:
        statusBg = AppColors.successLight;
        statusFg = AppColors.success;
        break;
      case StatusTone.warning:
        statusBg = AppColors.warningLight;
        statusFg = AppColors.warningText;
        break;
      case StatusTone.support:
        statusBg = AppColors.brandLight;
        statusFg = AppColors.brand;
        break;
      case StatusTone.neutral:
        statusBg = AppColors.neutralLight;
        statusFg = AppColors.neutral;
        break;
    }

    final showPriority = record.isAlert && record.statusTone != StatusTone.support;
    final isComplete = record.triageStatus == 'complete';

    Color priorityBg = AppColors.neutralLight;
    Color priorityFg = AppColors.neutral;
    String priorityLabel = record.priority ?? 'High';

    if (showPriority) {
      if (!isComplete) {
        priorityBg = AppColors.neutralLight;
        priorityFg = AppColors.neutral;
        priorityLabel = 'Pending assessment / Inasubiri tathmini';
      } else {
        switch (record.priority) {
          case 'High':
            priorityBg = AppColors.sosLight;
            priorityFg = AppColors.sosDeep;
            break;
          case 'Medium':
            priorityBg = AppColors.warningLight;
            priorityFg = AppColors.warningText;
            break;
          case 'Low':
          default:
            priorityBg = AppColors.neutralLight;
            priorityFg = AppColors.neutral;
            break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: fg),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  record.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  record.statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusFg,
                  ),
                ),
              ),
              if (showPriority) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: priorityBg,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    priorityLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: priorityFg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
