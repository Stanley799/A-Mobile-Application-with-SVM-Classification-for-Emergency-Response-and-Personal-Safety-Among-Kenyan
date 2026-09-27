import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/activity_item.dart';
import '../widgets/category_chip.dart';
import '../widgets/sos_button.dart';
import '../widgets/status_card.dart';
import 'activity_history_screen.dart';
import 'safety_checkin_screen.dart';
import 'sos_confirmation_sheet.dart';
import 'trusted_contacts_screen.dart';
import '../../shared/screens/profile_screen.dart';

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
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: destination.label,
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 56,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.brandLight : AppColors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 22,
              color: selected ? AppColors.brand : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            destination.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.brand : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    ),
  );
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
        final firstName =
            snapshot.data?.data()?['firstName'] as String? ?? 'there';
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
                            '${_greeting()}, $firstName 👋',
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
                          _initials(firstName),
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
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Location shared when alert is sent',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppRadius.full),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 7, color: AppColors.success),
                          SizedBox(width: 5),
                          Text(
                            'Ready',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: SosButton(
                    onPressed: () =>
                        _confirmEmergency(context, 'Other / General'),
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
                      crossAxisCount: 3,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                      childAspectRatio: constraints.crossAxisExtent < 300
                          ? 0.65
                          : constraints.crossAxisExtent < 340
                          ? 0.78
                          : 0.95,
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SosConfirmationSheet(category: category),
    );
    if (confirmed != true || !context.mounted) return;

    final userId = FirebaseAuth.instance.currentUser!.uid;
    final location = await _optionalCurrentLocation();
    try {
      await FirebaseFirestore.instance.collection('incidents').add({
        'userId': userId,
        'category': category,
        'status': 'Active',
        'location': location,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Emergency alert sent.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to send alert. Please try again.'),
          ),
        );
      }
    }
  }

  Future<GeoPoint?> _optionalCurrentLocation() async {
    if (kIsWeb || !await Geolocator.isLocationServiceEnabled()) return null;
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
          timeLimit: Duration(seconds: 4),
        ),
      ).timeout(const Duration(seconds: 4));
      return GeoPoint(position.latitude, position.longitude);
    } catch (_) {
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

  Future<void> _openSafetyCheckin(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.background,
        builder: (context) => const Padding(
          padding: EdgeInsets.only(top: AppSpacing.lg),
          child: SafetyCheckinScreen(),
        ),
      );
}

class _RecentActivityPreview extends StatelessWidget {
  const _RecentActivityPreview({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final incidents = FirebaseFirestore.instance
        .collection('incidents')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(3)
        .snapshots();
    final checkins = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(3)
        .snapshots();
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
            TextButton(onPressed: onViewAll, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: incidents,
          builder: (context, incidentSnapshot) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: checkins,
                builder: (context, checkinSnapshot) {
                  if (incidentSnapshot.hasError || checkinSnapshot.hasError) {
                    return const _ActivityEmptyState(
                      title: 'Activity unavailable',
                      subtitle: 'Please try again in a moment.',
                    );
                  }
                  if (incidentSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      checkinSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const _ActivityListSkeleton();
                  }
                  if (!incidentSnapshot.hasData || !checkinSnapshot.hasData) {
                    return const _ActivityEmptyState(
                      title: 'No recent activity',
                      subtitle: 'Your safety check-ins and emergency alerts will appear here',
                    );
                  }
                  final items = <_DashboardActivity>[
                    for (final doc in incidentSnapshot.data!.docs)
                      _DashboardActivity(
                        title: doc.data()['category'] as String? ?? 'Emergency',
                        status: doc.data()['status'] as String? ?? 'Unknown',
                        timestamp: doc.data()['createdAt'],
                        isIncident: true,
                      ),
                    for (final doc in checkinSnapshot.data!.docs)
                      _DashboardActivity(
                        title: 'Safety Check-In',
                        status: doc.data()['status'] as String? ?? 'Unknown',
                        timestamp: doc.data()['createdAt'],
                        isIncident: false,
                      ),
                  ]..sort((a, b) => b.date.compareTo(a.date));
                  final visibleItems = items.take(3).toList();
                  if (visibleItems.isEmpty) {
                    return const _ActivityEmptyState(
                      title: 'No recent activity',
                      subtitle: 'Your safety check-ins and emergency alerts will appear here',
                    );
                  }
                  return Column(
                    children: [
                      for (final item in visibleItems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ActivityItem(
                            title: item.title,
                            dateLabel: DateFormat('MMM d · h:mm a')
                                .format(item.date),
                            status: item.status,
                            isIncident: item.isIncident,
                          ),
                        ),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }
}

class _DashboardActivity {
  const _DashboardActivity({
    required this.title,
    required this.status,
    required this.timestamp,
    required this.isIncident,
  });

  final String title;
  final String status;
  final Object? timestamp;
  final bool isIncident;

  DateTime get date => timestamp is Timestamp
      ? (timestamp as Timestamp).toDate()
      : DateTime(1970);
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
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: AppColors.neutralLight,
    highlightColor: AppColors.background,
    child: Container(
      height: 72,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          const _SkeletonBlock(width: 40, height: 40, circular: true),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
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
          const SizedBox(width: AppSpacing.md),
          const _SkeletonBlock(width: 52, height: 14),
        ],
      ),
    ),
  );
}

class _ActivityListSkeleton extends StatelessWidget {
  const _ActivityListSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < 3; index++) ...[
        Shimmer.fromColors(
          baseColor: AppColors.neutralLight,
          highlightColor: AppColors.background,
          child: Container(
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
