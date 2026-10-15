import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/activity_record.dart';

enum _Filter { all, alerts, checkins }

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key, this.limit});

  final int? limit;

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  _Filter _filter = _Filter.all;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _incidentsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _checkinsStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final limitVal = widget.limit ?? 20;

    _incidentsStream = FirebaseFirestore.instance
        .collection('incidents')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limitVal)
        .snapshots();

    _checkinsStream = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limitVal)
        .snapshots();
  }

  void _retry() {
    setState(() {
      _initStreams();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_incidentsStream == null || _checkinsStream == null) {
      return const SizedBox.shrink();
    }

    final isEmbedded = widget.limit != null;

    final content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _incidentsStream,
      builder: (context, incidentSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _checkinsStream,
          builder: (context, checkinSnapshot) {
            final incidentsError = incidentSnapshot.hasError;
            final checkinsError = checkinSnapshot.hasError;

            if (incidentsError) {
              debugPrint('Incidents stream error: ${incidentSnapshot.error}');
            }
            if (checkinsError) {
              debugPrint('Checkins stream error: ${checkinSnapshot.error}');
            }

            final isWaiting =
                (!incidentSnapshot.hasData && !incidentsError) ||
                (!checkinSnapshot.hasData && !checkinsError);

            if (isWaiting && !incidentSnapshot.hasData && !checkinSnapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final records = <ActivityRecord>[];

            if (incidentSnapshot.hasData) {
              for (final doc in incidentSnapshot.data!.docs) {
                records.add(ActivityRecord.fromIncident(doc.id, doc.data()));
              }
            }

            if (checkinSnapshot.hasData) {
              for (final doc in checkinSnapshot.data!.docs) {
                records.add(ActivityRecord.fromCheckin(doc.id, doc.data()));
              }
            }

            records.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            var filtered = records;
            if (_filter == _Filter.alerts) {
              filtered = records.where((r) => r.isAlert).toList();
            } else if (_filter == _Filter.checkins) {
              filtered = records.where((r) => !r.isAlert).toList();
            }

            if (widget.limit != null && filtered.length > widget.limit!) {
              filtered = filtered.take(widget.limit!).toList();
            }

            final hasPartialError = incidentsError || checkinsError;
            String errorMessage = 'Some activity could not be loaded.';
            final errStr =
                '${incidentSnapshot.error ?? ''} ${checkinSnapshot.error ?? ''}'
                    .toLowerCase();
            if (errStr.contains('index')) {
              errorMessage = 'Setting things up. This should work in a few minutes.';
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEmbedded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                    child: Text(
                      'Recent activity',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      'Your alerts and safety check-ins',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _filter == _Filter.all,
                          onTap: () => setState(() => _filter = _Filter.all),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _FilterChip(
                          label: 'Alerts',
                          selected: _filter == _Filter.alerts,
                          onTap: () => setState(() => _filter = _Filter.alerts),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _FilterChip(
                          label: 'Check-ins',
                          selected: _filter == _Filter.checkins,
                          onTap: () => setState(() => _filter = _Filter.checkins),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (hasPartialError)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: AppSpacing.sm,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              errorMessage,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.warningText,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _retry,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.history,
                            size: 48,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'No activity yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'Your alerts and safety check-ins will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _GroupedActivityList(records: filtered, shrinkWrap: isEmbedded),
              ],
            );
          },
        );
      },
    );

    if (isEmbedded) {
      return content;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: content,
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppColors.brand : AppColors.surface,
          foregroundColor: selected ? AppColors.surface : AppColors.textPrimary,
          side: BorderSide(
            color: selected ? AppColors.brand : AppColors.divider,
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _GroupedActivityList extends StatelessWidget {
  const _GroupedActivityList({required this.records, required this.shrinkWrap});

  final List<ActivityRecord> records;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayList = <ActivityRecord>[];
    final yesterdayList = <ActivityRecord>[];
    final earlierList = <ActivityRecord>[];

    for (final r in records) {
      final date = DateTime(r.createdAt.year, r.createdAt.month, r.createdAt.day);
      if (date == today) {
        todayList.add(r);
      } else if (date == yesterday) {
        yesterdayList.add(r);
      } else {
        earlierList.add(r);
      }
    }

    final children = <Widget>[];

    if (todayList.isNotEmpty) {
      children.add(_GroupHeader(label: 'TODAY'));
      for (final r in todayList) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ActivityCard(record: r),
        ));
      }
    }

    if (yesterdayList.isNotEmpty) {
      children.add(_GroupHeader(label: 'YESTERDAY'));
      for (final r in yesterdayList) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ActivityCard(record: r),
        ));
      }
    }

    if (earlierList.isNotEmpty) {
      children.add(_GroupHeader(label: 'EARLIER'));
      for (final r in earlierList) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ActivityCard(record: r),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.sm),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
