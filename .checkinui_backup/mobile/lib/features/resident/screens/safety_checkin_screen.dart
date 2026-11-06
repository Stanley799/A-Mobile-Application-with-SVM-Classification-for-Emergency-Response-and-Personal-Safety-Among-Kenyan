import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/safety_checkin.dart';
import '../../../core/theme/app_theme.dart';

/// Starts, monitors, and closes a resident's timed safety check-in.
class SafetyCheckinScreen extends StatefulWidget {
  const SafetyCheckinScreen({super.key});

  @override
  State<SafetyCheckinScreen> createState() => _SafetyCheckinScreenState();
}

class _SafetyCheckinScreenState extends State<SafetyCheckinScreen> {
  Timer? _clock;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeCheckins;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    _activeCheckins = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'Active')
        .limit(1)
        .snapshots();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Safety Check-In',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _activeCheckins,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildMessageState(
              icon: Icons.cloud_off_outlined,
              title: 'Unable to load check-in',
              message: 'Check your connection and try again.',
              action: FilledButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) return const _CheckInSkeleton();

          final documents = snapshot.data!.docs;
          if (documents.isEmpty) return _buildNoActiveCheckIn();

          final checkin = SafetyCheckIn.fromDocument(documents.first);
          return _buildActiveCheckIn(checkin);
        },
      ),
    );
  }

  Widget _buildNoActiveCheckIn() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - AppSpacing.xxl * 2).clamp(
            0.0,
            double.infinity,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.brandLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    size: 40,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'No Active Check-In',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Set a timer for your activity. If it expires, this check-in '
                  'will be marked overdue. Automatic contact notifications '
                  'are not active yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _showDurationSheet,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    child: const Text(
                      'Start Check-In',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildActiveCheckIn(SafetyCheckIn checkin) {
    final remaining = checkin.expiryTime.difference(DateTime.now());
    final remainingSeconds = remaining.inSeconds;
    final isExpired = remainingSeconds <= 0;
    final totalSeconds = checkin.durationMinutes * 60;
    final progress = totalSeconds <= 0
        ? 0.0
        : (remainingSeconds / totalSeconds).clamp(0.0, 1.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.md),
              _CircularCheckInTimer(
                progress: progress,
                timeLabel: isExpired
                    ? 'Expired'
                    : _formatDuration(remainingSeconds),
              ),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: isExpired
                      ? null
                      : () => _updateStatus(checkin.id, 'CheckedIn'),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text(
                    'Check In Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    disabledBackgroundColor: AppColors.neutralLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => _confirmCancel(checkin.id),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text(
                    'Cancel Check-In',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: AppColors.info),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Check-ins currently show an overdue state when the timer expires. '
                        'Automatic contact notifications are not active yet.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action,
          ],
        ],
      ),
    ),
  );

  Future<void> _showDurationSheet() async {
    int? selectedDuration;
    final duration = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final optionWidth = (MediaQuery.sizeOf(context).width - 60) / 2;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
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
                Text(
                  'How long will you be?',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Choose a check-in timer. Automatic contact notifications '
                  'are not active yet.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final minutes in [15, 30, 45, 60])
                      SizedBox(
                        width: optionWidth,
                        child: _DurationOption(
                          minutes: minutes,
                          selected: selectedDuration == minutes,
                          onTap: () =>
                              setSheetState(() => selectedDuration = minutes),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: selectedDuration == null
                        ? null
                        : () =>
                              Navigator.of(sheetContext).pop(selectedDuration),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      disabledBackgroundColor: AppColors.neutralLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    child: const Text(
                      'Start Timer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (duration != null && mounted) await _startCheckIn(duration);
  }

  Future<void> _startCheckIn(int durationMinutes) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();
    try {
      await FirebaseFirestore.instance.collection('safetyCheckins').add({
        'userId': userId,
        'startTime': FieldValue.serverTimestamp(),
        'expiryTime': Timestamp.fromDate(
          now.add(Duration(minutes: durationMinutes)),
        ),
        'status': 'Active',
        'durationMinutes': durationMinutes,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to start check-in. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmCancel(String checkinId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Cancel Check-In?'),
        content: const Text(
          'This ends the timer. You can start a new check-in at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Keep Active',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Cancel Check-In',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _updateStatus(checkinId, 'Cancelled');
    }
  }

  Future<void> _updateStatus(String checkinId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('safetyCheckins')
          .doc(checkinId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update check-in. Please try again.'),
          ),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '00:00';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${_twoDigits(minutes)}:${_twoDigits(remainingSeconds)}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _CircularCheckInTimer extends StatelessWidget {
  const _CircularCheckInTimer({
    required this.progress,
    required this.timeLabel,
  });

  final double progress;
  final String timeLabel;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 200,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: 200,
          child: CircularProgressIndicator(
            value: 1,
            strokeWidth: 10,
            valueColor: const AlwaysStoppedAnimation(AppColors.divider),
            backgroundColor: AppColors.transparent,
          ),
        ),
        SizedBox.square(
          dimension: 200,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            valueColor: const AlwaysStoppedAnimation(AppColors.brand),
            backgroundColor: AppColors.transparent,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeLabel,
              style: TextStyle(
                fontSize: timeLabel == 'Expired' ? 28 : 36,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (timeLabel != 'Expired') ...[
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Time remaining',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _DurationOption extends StatelessWidget {
  const _DurationOption({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.brandLight : AppColors.surfaceAlt,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            '$minutes minutes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.brand : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}

class _CheckInSkeleton extends StatelessWidget {
  const _CheckInSkeleton();

  @override
  Widget build(BuildContext context) => Center(
    child: Shimmer.fromColors(
      baseColor: AppColors.neutralLight,
      highlightColor: AppColors.surfaceAlt,
      child: Container(
        width: 200,
        height: 200,
        decoration: const BoxDecoration(
          color: AppColors.neutralLight,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}
