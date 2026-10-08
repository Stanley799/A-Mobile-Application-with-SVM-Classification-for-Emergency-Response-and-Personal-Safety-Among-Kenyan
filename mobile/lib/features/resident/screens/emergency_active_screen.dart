import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/models/emergency_enums.dart';
import '../../../core/theme/app_theme.dart';

/// Confirmation screen shown after any successful activation path.
class EmergencyActiveScreen extends StatefulWidget {
  const EmergencyActiveScreen({
    super.key,
    required this.incidentId,
    required this.category,
    required this.priority,
    required this.createdAt,
    this.cancelIncident,
  });

  final String incidentId;
  final EmergencyCategory category;
  final PriorityLevel priority;
  final DateTime createdAt;
  final Future<void> Function()? cancelIncident;

  @override
  State<EmergencyActiveScreen> createState() => _EmergencyActiveScreenState();
}

class _EmergencyActiveScreenState extends State<EmergencyActiveScreen> {
  bool _isCancelling = false;

  Future<void> _cancelAlert(BuildContext context) async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this alert?'),
        content: const Text(
          'This will mark your alert as cancelled. If a responder has already been assigned, contact them to confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Active'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Cancel Alert'),
          ),
        ],
      ),
    );

    if (shouldCancel != true || !context.mounted) {
      if (mounted) setState(() => _isCancelling = false);
      return;
    }

    try {
      if (widget.cancelIncident != null) {
        await widget.cancelIncident!();
      } else {
        await FirebaseFirestore.instance
            .collection('incidents')
            .doc(widget.incidentId)
            .update({
              'status': IncidentStatus.cancelled.firestoreValue,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to cancel the alert. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = widget.createdAt.toLocal().toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.successLight,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 62,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Emergency alert sent',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your alert has been recorded. Responder assignment has not been confirmed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Category', value: widget.category.label),
                      const SizedBox(height: 10),
                      _InfoRow(label: 'Priority', value: widget.priority.label),
                      const SizedBox(height: 10),
                      _InfoRow(label: 'Created', value: formattedTime),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isCancelling
                        ? null
                        : () => _cancelAlert(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.warning),
                      foregroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      _isCancelling ? 'Cancelling...' : 'Cancel Alert',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
