import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/incident_id.dart';
import '../widgets/activity_record.dart';
import '../widgets/alert_status_sheet.dart';
import '../widgets/category_chip.dart';
import '../widgets/live_location_pill.dart';
import '../widgets/sos_button.dart';
import '../widgets/sos_halo.dart';
import '../widgets/status_card.dart';
import 'activity_history_screen.dart';
import 'safety_checkin_screen.dart';
import 'sos_confirmation_sheet.dart';
import 'trusted_contacts_screen.dart';
import '../../shared/screens/profile_screen.dart';

/// Hosts the resident dashboard and its contacts, history, and profile tabs.
class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _ResidentDashboard(
              onOpenContacts: () => setState(() => _selectedTab = 1),
              onOpenProfile: () => setState(() => _selectedTab = 3),
              onOpenHistory: () => setState(() => _selectedTab = 2),
            ),
            const TrustedContactsScreen(),
            const ActivityHistoryScreen(),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _ResidentNavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
      ),
    );
  }
}

class _ResidentNavigationBar extends StatelessWidget {
  const _ResidentNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _destinations =
      <({String label, IconData icon, IconData selectedIcon})>[
        (label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
        (
          label: 'Contacts',
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
        ),
        (label: 'History', icon: Icons.history, selectedIcon: Icons.history),
        (
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
        ),
      ];

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      boxShadow: AppShadows.navigation,
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (var index = 0; index < _destinations.length; index++)
              Expanded(
                child: _NavigationDestination(
                  destination: _destinations[index],
                  selected: selectedIndex == index,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({String label, IconData icon, IconData selectedIcon}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showLabel = MediaQuery.sizeOf(context).width >= 320;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 56,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.brandLight
                      : AppColors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: selected ? AppColors.brand : AppColors.textTertiary,
                ),
              ),
              if (showLabel) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppColors.brand : AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResidentDashboard extends StatelessWidget {
  static const _categories =
      <
        ({
          String category,
          String label,
          IconData icon,
          Color background,
          Color foreground,
        })
      >[
        (
          category: 'Medical Emergency',
          label: 'Medical\nEmergency',
          icon: Icons.medical_services,
          background: AppColors.medicalBg,
          foreground: AppColors.medicalFg,
        ),
        (
          category: 'Road Accident',
          label: 'Road\nAccident',
          icon: Icons.directions_car,
          background: AppColors.roadBg,
          foreground: AppColors.roadFg,
        ),
        (
          category: 'Fire & Rescue',
          label: 'Fire &\nRescue',
          icon: Icons.local_fire_department,
          background: AppColors.fireBg,
          foreground: AppColors.fireFg,
        ),
        (
          category: 'Security Threat',
          label: 'Security\nThreat',
          icon: Icons.shield,
          background: AppColors.securityBg,
          foreground: AppColors.securityFg,
        ),
        (
          category: 'Abduction',
          label: 'Abduction',
          icon: Icons.person_search,
          background: AppColors.abductionBg,
          foreground: AppColors.abductionFg,
        ),
        (
          category: 'Other / General',
          label: 'Other /\nGeneral',
          icon: Icons.more_horiz,
          background: AppColors.otherBg,
          foreground: AppColors.otherFg,
        ),
      ];

  const _ResidentDashboard({
    required this.onOpenContacts,
    required this.onOpenProfile,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenContacts;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final userDocument = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocument,
      builder: (context, snapshot) {
        final firstName = snapshot.data?.data()?['firstName'] as String? ?? '';
        final displayName = firstName.trim();
        final greetingText = displayName.isEmpty
            ? _greeting()
            : '${_greeting()}, $displayName 👋';
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greetingText,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Stay safe. We're here for you.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open profile',
                      onPressed: onOpenProfile,
                      icon: CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.brandLight,
                        child: Text(
                          _initials(displayName),
                          style: const TextStyle(
                            color: AppColors.brand,
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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: LiveLocationPill(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: SosHalo(
                    size: 200,
                    child: SosButton(
                      onPressed: () =>
                          _confirmEmergency(context, 'SOS'),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text(
                  'Quick Emergency Options',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.crossAxisExtent < 220
                      ? 1
                      : constraints.crossAxisExtent < 360
                      ? 2
                      : 3;
                  return SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final category = _categories[index];
                      return CategoryChip(
                        label: category.label,
                        icon: category.icon,
                        background: category.background,
                        foreground: category.foreground,
                        onTap: () =>
                            _confirmEmergency(context, category.category),
                      );
                    }, childCount: _categories.length),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                      mainAxisExtent: 120,
                    ),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(child: _SafetyCheckinPreview()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _TrustedContactsPreview(onManage: onOpenContacts),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              sliver: SliverToBoxAdapter(
                child: _RecentActivityPreview(onViewAll: onOpenHistory),
              ),
            ),
          ],
        );
      },
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 22) return 'Good evening';
    return 'Good night';
  }

  String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  Future<void> _confirmEmergency(BuildContext context, String category) async {
    final confirmCat = category == 'SOS' ? 'Other / General' : category;
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final actualCategory = category == 'SOS' ? 'Other / General' : category;

    final id = newIncidentId(category: actualCategory);
    final ref = FirebaseFirestore.instance.collection('incidents').doc(id);

    // 1. Fetch location robustly (Web + Mobile) in parallel with sheet
    final locationFuture = _getCurrentLocationRobust();

    final initialData = <String, Object?>{
      'userId': userId,
      'category': actualCategory,
      'status': 'Active',
      'location': null,
      'priority': 'High',
      'prioritySource': 'safe_fallback',
      'needsHumanReview': true,
      'triageStatus': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final createFuture = ref.set(initialData);

    // Update location as soon as it resolves
    unawaited(
      locationFuture.then((loc) {
        if (loc != null) {
          ref.update({
            'location': loc,
            'updatedAt': FieldValue.serverTimestamp(),
          }).catchError((_) {});
        }
      }),
    );

    // 2. Show 5-second diagnostic confirmation sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SosConfirmationSheet(
        category: confirmCat,
        incidentRef: ref,
      ),
    );

    if (confirmed == false) {
      unawaited(
        ref.update({
          'status': 'Cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }).catchError((e) {
          debugPrint('Cancel incident error: $e');
        }),
      );
      return;
    }

    if (confirmed != true || !context.mounted) return;

    final location = await locationFuture;

    // 3. Proceed seamlessly to AlertStatusSheet with the SAME createFuture
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        enableDrag: false,
        isDismissible: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.94,
          child: AlertStatusSheet(
            incidentRef: ref,
            createFuture: createFuture,
            retryCreate: () => ref.set(initialData),
            category: category,
            locationShared: location != null,
          ),
        ),
      ),
    );
  }

  Future<GeoPoint?> _getCurrentLocationRobust() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      ).timeout(const Duration(seconds: 6));
      return GeoPoint(position.latitude, position.longitude);
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return GeoPoint(lastKnown.latitude, lastKnown.longitude);
        }
      } catch (_) {}
      return null;
    }
  }
}

class _TrustedContactsPreview extends StatelessWidget {
  const _TrustedContactsPreview({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final contacts = FirebaseFirestore.instance
        .collection('trustedContacts')
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: contacts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatusCard(
            icon: Icons.people_outline,
            iconBackground: AppColors.infoLight,
            iconColor: AppColors.info,
            title: 'Trusted Contacts',
            subtitle: 'Unable to load contacts',
            action: const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
            ),
            onTap: onManage,
          );
        }
        if (!snapshot.hasData) return const _StatusCardSkeleton();
        return StatusCard(
          icon: Icons.people_outline,
          iconBackground: AppColors.infoLight,
          iconColor: AppColors.info,
          title: 'Trusted Contacts',
          subtitle: '${snapshot.data!.docs.length} contacts',
          action: TextButton(
            onPressed: onManage,
            child: const Text(
              'Manage',
              style: TextStyle(color: AppColors.info),
            ),
          ),
          onTap: onManage,
        );
      },
    );
  }
}

class _SafetyCheckinPreview extends StatefulWidget {
  @override
  State<_SafetyCheckinPreview> createState() => _SafetyCheckinPreviewState();
}

class _SafetyCheckinPreviewState extends State<_SafetyCheckinPreview> {
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeCheckins,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatusCard(
            icon: Icons.verified_user_outlined,
            iconBackground: AppColors.successLight,
            iconColor: AppColors.success,
            title: 'Safety Check-In',
            subtitle: 'Keep your loved ones informed',
            action: const _StatusPill(
              label: 'Unavailable',
              color: AppColors.neutral,
              background: AppColors.neutralLight,
            ),
            onTap: () => _openSafetyCheckin(context),
          );
        }
        if (!snapshot.hasData) return const _StatusCardSkeleton();
        final data = snapshot.data?.docs.firstOrNull?.data();
        final expiry = data?['expiryTime'];
        final remaining = expiry is Timestamp
            ? expiry.toDate().difference(DateTime.now())
            : null;
        final active = remaining != null && remaining > Duration.zero;
        final timeLabel = active
            ? '${(remaining.inMinutes).toString().padLeft(2, '0')}:${remaining.inSeconds.remainder(60).toString().padLeft(2, '0')} remaining'
            : 'Not Active';
        return StatusCard(
          icon: Icons.verified_user_outlined,
          iconBackground: AppColors.successLight,
          iconColor: AppColors.success,
          title: 'Safety Check-In',
          subtitle: 'Keep your loved ones informed',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusPill(
                label: timeLabel,
                color: active ? AppColors.success : AppColors.neutral,
                background: active
                    ? AppColors.successLight
                    : AppColors.neutralLight,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
          onTap: () => _openSafetyCheckin(context),
        );
      },
    );
  }

  Future<void> _openSafetyCheckin(BuildContext context) => Navigator.of(context)
      .push<void>(
        MaterialPageRoute<void>(
          builder: (context) => const SafetyCheckinScreen(),
        ),
      );
}

class _RecentActivityPreview extends StatefulWidget {
  const _RecentActivityPreview({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  State<_RecentActivityPreview> createState() => _RecentActivityPreviewState();
}

class _RecentActivityPreviewState extends State<_RecentActivityPreview> {
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

    _incidentsStream = FirebaseFirestore.instance
        .collection('incidents')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(3)
        .snapshots();

    _checkinsStream = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(3)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(onPressed: widget.onViewAll, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _incidentsStream,
          builder: (context, incidentSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _checkinsStream,
              builder: (context, checkinSnapshot) {
                final incidentsError = incidentSnapshot.hasError;
                final checkinsError = checkinSnapshot.hasError;

                if (incidentsError) {
                  debugPrint('Incidents preview error: ${incidentSnapshot.error}');
                }
                if (checkinsError) {
                  debugPrint('Checkins preview error: ${checkinSnapshot.error}');
                }

                if (incidentsError && checkinsError) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Activity unavailable',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final isWaiting =
                    (!incidentSnapshot.hasData && !incidentsError) ||
                    (!checkinSnapshot.hasData && !checkinsError);

                if (isWaiting && !incidentSnapshot.hasData && !checkinSnapshot.hasData) {
                  return const _ActivityListSkeleton();
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
                final visible = records.take(3).toList();

                if (visible.isEmpty) {
                  return const _ActivityEmptyState(
                    title: 'No recent activity',
                    subtitle: 'Your safety check-ins and emergency alerts will appear here',
                  );
                }

                return Column(
                  children: [
                    for (final item in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ActivityCard(record: item),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
    ),
  );
}

class _StatusCardSkeleton extends StatelessWidget {
  const _StatusCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      boxShadow: AppShadows.card,
    ),
    child: const Row(
      children: [
        _SkeletonBlock(width: 40, height: 40, circular: true),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBlock(width: 112, height: 12),
              SizedBox(height: AppSpacing.sm),
              _SkeletonBlock(width: 148, height: 10),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.md),
        _SkeletonBlock(width: 52, height: 14),
      ],
    ),
  );
}

class _ActivityListSkeleton extends StatelessWidget {
  const _ActivityListSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < 3; index++) ...[
        Container(
          height: 68,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.card,
          ),
          child: const Row(
            children: [
              _SkeletonBlock(width: 36, height: 36, circular: true),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBlock(width: 132, height: 12),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonBlock(width: 96, height: 10),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.md),
              _SkeletonBlock(width: 52, height: 16),
            ],
          ),
        ),
        if (index < 2) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.xxl,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.xl),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.inbox_outlined,
          size: 48,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.circular = false,
  });

  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.neutralLight,
      borderRadius: circular ? null : BorderRadius.circular(AppRadius.sm),
      shape: circular ? BoxShape.circle : BoxShape.rectangle,
    ),
  );
}
