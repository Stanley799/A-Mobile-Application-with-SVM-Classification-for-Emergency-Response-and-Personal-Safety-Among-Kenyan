import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/incident_id.dart';

/// Fast diagnostic and location confirmation sheet (replaces slow 5-second countdown).
class SosConfirmationSheet extends StatefulWidget {
  const SosConfirmationSheet({
    super.key,
    required this.category,
    required this.incidentRef,
  });

  final String category;
  final DocumentReference<Map<String, dynamic>> incidentRef;

  @override
  State<SosConfirmationSheet> createState() => _SosConfirmationSheetState();
}

class _SosConfirmationSheetState extends State<SosConfirmationSheet> {
  @override
  void initState() {
    super.initState();
    // Capture GPS and record details instantly, proceeding after a brief 1.2s verification pulse
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final refStr = incidentReference(widget.incidentRef.id);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Connecting Emergency',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Locking ${widget.category} alert & GPS location...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            const SizedBox.square(
              dimension: 56,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation(AppColors.sos),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_fixed, size: 16, color: AppColors.brand),
                  const SizedBox(width: AppSpacing.sm),
                  const Flexible(
                    child: Text(
                      'Capturing precise location & Ref ID...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ref $refStr',
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.sos,
                  side: const BorderSide(color: AppColors.sos),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel Alert (Accidental Tap)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
