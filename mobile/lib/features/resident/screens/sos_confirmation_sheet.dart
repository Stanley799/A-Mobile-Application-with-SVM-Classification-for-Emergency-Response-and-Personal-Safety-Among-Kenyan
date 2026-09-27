import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SosConfirmationSheet extends StatefulWidget {
  const SosConfirmationSheet({super.key, required this.category});

  final String category;

  @override
  State<SosConfirmationSheet> createState() => _SosConfirmationSheetState();
}

class _SosConfirmationSheetState extends State<SosConfirmationSheet> {
  Timer? _timer;
  int _secondsRemaining = 5;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
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
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Report Emergency',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sending ${widget.category} alert in...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox.square(
            dimension: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _secondsRemaining / 5,
                  strokeWidth: 5,
                  backgroundColor: AppColors.fireBg,
                  valueColor: const AlwaysStoppedAnimation(AppColors.sos),
                ),
                Text(
                  '$_secondsRemaining',
                  style: const TextStyle(
                    color: AppColors.sos,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.sos,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
