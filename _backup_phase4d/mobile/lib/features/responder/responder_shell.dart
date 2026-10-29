// The whole responder app: verification gate -> Home (duty switch, incoming and active jobs) and History.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/dispatch_models.dart';
import '../../core/services/push_service.dart';
import '../../core/ui/states.dart';
import 'active_job_screen.dart';
import 'duty_heartbeat.dart';
import 'incoming_alert_screen.dart';
import 'responder_repository.dart';
import 'responder_labels.dart';
import 'responder_offer_queue.dart';
import 'responder_theme.dart';
import 'responder_widgets.dart';
import 'track_publisher.dart';
import '../../core/ui/routes.dart';

/// Put this where the app opens the home screen for a user whose role is "Responder".
class ResponderGate extends StatelessWidget {
  const ResponderGate({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ResponderRepository();
    return StreamBuilder<ResponderRecord?>(
      stream: repo.watchMe(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: RC.bg,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return const _Message(
            title: 'Connection problem',
            body: 'Your responder profile could not be loaded. Check your connection and reopen the app; sign-in is unchanged.',
          );
        }
        final me = snap.data;
        if (me == null) {
          return const _Message(
            title: 'Profile not found',
            body: 'Your responder profile has not been set up. Please contact the administrator.',
          );
        }
        if (me.verificationStatus != 'Verified') {
          final rejected =
              me.verificationStatus == 'Rejected' ||
              me.verificationStatus == 'Suspended';
          return _Message(
            title: rejected
                ? 'Account ${me.verificationStatus.toLowerCase()}'
                : 'Waiting for verification',
            body: rejected
                ? 'Your responder account is ${me.verificationStatus.toLowerCase()}. Please contact the administrator.'
                : 'An administrator is checking ${me.organizationName} (registration ${me.registrationNumber}). You will receive alerts once you are verified.',
          );
        }
        return ResponderShell(repo: repo, me: me);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: RC.bg,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: RC.text,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(
                fontSize: 16,
                color: RC.soft,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            BigButton(
              label: 'Sign out',
              filled: false,
              height: 52,
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
        ),
      ),
    ),
  );
}

class ResponderShell extends StatefulWidget {
  const ResponderShell({super.key, required this.repo, required this.me});
  final ResponderRepository repo;
  final ResponderRecord me;

  @override
  State<ResponderShell> createState() => _ResponderShellState();
}

class _ResponderShellState extends State<ResponderShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  late final DutyHeartbeat _beat = DutyHeartbeat(widget.repo);
  final Set<String> _shown = {};
  bool _incomingOpen = false;
  String? _waitingOfferId;
  StreamSubscription<ResponderOfferFeed>? _sub;
  List<Offer> _offers = const [];
  bool _onDuty = false;
  bool _availabilityBusy = false;
  bool _isFromCache = true;
  bool _hasServerSnapshot = false;
  bool _offersError = false;
  bool _offersLoading = true;
  Timer? _ticker;
  late final Future<String?> _firstName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushService.init();
    _firstName = widget.repo.firstName();
    _onDuty = widget.me.availabilityStatus != 'Offline';
    if (_onDuty) unawaited(_restoreDuty());
    _listenOffers();
  }

  void _listenOffers() {
    _sub?.cancel();
    _sub = widget.repo.watchOfferFeed().listen(
      (feed) {
        if (!mounted) return;
        setState(() {
          _offers = feed.offers;
          _isFromCache = feed.isFromCache;
          _offersError = false;
          _offersLoading = false;
          if (!feed.isFromCache) _hasServerSnapshot = true;
        });
        _syncTicker(feed.offers.any((o) => o.isOpen && o.secondsLeft() > 0));
        TrackPublisher.instance.sync(
          feed.offers,
        ); // live location only while a job is held
        for (final o in ResponderOfferQueue.openOffers(feed.offers)) {
          if (o.isOpen && o.secondsLeft() > 0 && _shown.add(o.id)) {
            if (_incomingOpen) {
              _waitingOfferId ??= o.id;
            } else {
              unawaited(_presentIncoming(o));
            }
            break;
          }
        }
      },
      onError: (Object _) {
        if (mounted) {
          setState(() {
            _offersError = true;
            _offersLoading = false;
          });
        }
      },
    );
  }

  void _retryOffers() {
    setState(() {
      _offersLoading = true;
      _offersError = false;
    });
    _listenOffers();
  }

  /// Open-offer countdowns tick every second; the stream alone never fires that often.
  void _syncTicker(bool hasOpenOffers) {
    if (hasOpenOffers) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _presentIncoming(Offer offer) async {
    if (_incomingOpen || !mounted) {
      _waitingOfferId ??= offer.id;
      return;
    }
    _incomingOpen = true;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    try {
      await Navigator.of(context).push<void>(
        appRoute<void>(
          (_) => IncomingAlertScreen(offer: offer, repo: widget.repo),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _incomingOpen = false;
      if (mounted) setState(() {});
    }
  }

  void _openWaitingOffer() {
    final id = _waitingOfferId;
    if (id == null) return;
    Offer? offer;
    for (final item in _offers) {
      if (item.id == id && item.isOpen && item.secondsLeft() > 0) {
        offer = item;
        break;
      }
    }
    setState(() => _waitingOfferId = null);
    if (offer != null) unawaited(_presentIncoming(offer));
  }

  Future<void> _restoreDuty() async {
    final ok = await _beat.start();
    if (!ok) {
      try {
        await widget.repo.setAvailability('Offline');
      } catch (_) {}
      if (mounted) setState(() => _onDuty = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _onDuty && !_beat.running) {
      _beat.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _ticker?.cancel();
    _beat.dispose();
    TrackPublisher.instance.stop();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    if (_availabilityBusy) return;
    setState(() => _availabilityBusy = true);
    try {
      if (on) {
        final ok = await _beat.start();
        if (!ok) return;
        await widget.repo.setAvailability('Available');
      } else {
        await widget.repo.setAvailability('Offline');
        _beat.stop();
      }
      if (mounted) setState(() => _onDuty = on);
    } catch (_) {
      if (on) _beat.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update duty status. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _availabilityBusy = false);
    }
  }

  Future<void> _retryGps() async {
    if (_availabilityBusy) return;
    setState(() => _availabilityBusy = true);
    try {
      await _beat.refreshGps();
    } finally {
      if (mounted) setState(() => _availabilityBusy = false);
    }
  }

  Future<void> _signOut() async {
    if (_offers.any((offer) => offer.isActiveJob)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete your active response before signing out.'),
        ),
      );
      return;
    }
    if (_onDuty) {
      final confirm = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(ResponderSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Go off duty and sign out?',
                style: ResponderTextStyles.section,
              ),
              const SizedBox(height: ResponderSpacing.sm),
              const Text(
                'You will stop receiving responder alerts on this device.',
                style: ResponderTextStyles.body,
              ),
              const SizedBox(height: ResponderSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Go off duty and sign out'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
      if (confirm != true || !mounted) return;
    }
    try {
      await widget.repo.setAvailability('Offline');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not go off duty. Check your connection and try again.',
            ),
          ),
        );
      }
      return;
    }
    _beat.stop();
    TrackPublisher.instance.stop();
    await FirebaseAuth.instance.signOut();
  }

  ReadinessState _readinessState(List<Offer> active) {
    if (_offersError || (_hasServerSnapshot && _isFromCache)) {
      return ReadinessState.noConnection;
    }
    if (active.isNotEmpty) return ReadinessState.onJob;
    if (!_onDuty) return ReadinessState.offDuty;
    final problem = _beat.problem.value;
    if (problem != null &&
        (problem.contains('location (GPS)') ||
            problem.contains('Allow location'))) {
      return ReadinessState.locationOff;
    }
    final lastFix = _beat.lastFixAt.value;
    if (lastFix == null || DateTime.now().difference(lastFix).inSeconds > 90) {
      return ReadinessState.gpsStale;
    }
    return ReadinessState.onDuty;
  }

  @override
  Widget build(BuildContext context) {
    final open = _offers.where((o) => o.isOpen && o.secondsLeft() > 0).toList();
    final active = _offers.where((o) => o.isActiveJob).toList();
    final past = _offers.where((o) => o.isFinished).toList();
    return Scaffold(
      backgroundColor: RC.bg,
      appBar: AppBar(
        backgroundColor: RC.bg,
        foregroundColor: RC.text,
        elevation: 0,
        title: FutureBuilder<String?>(
          future: _firstName,
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.me.organizationName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${snapshot.data ?? 'Responder'} · ${widget.me.organizationType}',
                style: const TextStyle(
                  fontSize: 12,
                  color: RC.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Profile options',
            onSelected: (value) {
              if (value == 'signOut') _signOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'signOut', child: Text('Sign out')),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ValueListenableBuilder<DateTime?>(
              valueListenable: _beat.lastFixAt,
              builder: (context, lastFix, _) => ValueListenableBuilder<double?>(
                valueListenable: _beat.lastAccuracyMeters,
                builder: (context, accuracy, _) => ReadinessBar(
                  state: _readinessState(active),
                  lastFixAt: lastFix,
                  accuracyMeters: accuracy,
                  capabilities: [
                    for (final code in widget.me.effectiveCapabilities)
                      ResponderLabels.capability(code),
                  ],
                  onRetryGps: _onDuty ? _retryGps : null,
                ),
              ),
            ),
            Expanded(
              child: switch (_tab) {
                0 => _home(open, active),
                1 => _activeJobs(active),
                _ => _history(past),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: RC.card,
          indicatorColor: RC.line,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: RC.text, fontWeight: FontWeight.w600),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: open.isNotEmpty,
                label: Text('${open.length}'),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: RC.soft,
                ),
              ),
              label: 'Offers',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: active.isNotEmpty,
                smallSize: 8,
                child: const Icon(Icons.emergency_outlined, color: RC.soft),
              ),
              label: 'Active',
            ),
            NavigationDestination(
              icon: Icon(Icons.history, color: RC.soft),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }

  Widget _home(List<Offer> open, List<Offer> active) {
    final orderedOpen = ResponderOfferQueue.openOffers(open);
    final earlierToday = ResponderOfferQueue.earlierToday(_offers);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        if (_waitingOfferId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ResponderSpacing.md),
            child: FilledButton.icon(
              onPressed: _openWaitingOffer,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Another alert waiting'),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: RC.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      active.isNotEmpty
                          ? 'Active response'
                          : _onDuty
                          ? 'You are on duty'
                          : 'You are off duty',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: RC.text,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 156,
                    height: 56,
                    child: FilledButton(
                      onPressed: _availabilityBusy || active.isNotEmpty
                          ? null
                          : () => _toggle(!_onDuty),
                      style: FilledButton.styleFrom(
                        backgroundColor: _onDuty ? RC.surface2 : RC.accept,
                        foregroundColor: _onDuty
                            ? RC.text
                            : const Color(0xFF04130C),
                        disabledBackgroundColor: RC.surface2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            ResponderRadius.card,
                          ),
                        ),
                      ),
                      child: _availabilityBusy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: RC.text,
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _onDuty
                                        ? Icons.pause_circle_outline
                                        : Icons.play_arrow_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    active.isNotEmpty
                                        ? 'ON A JOB'
                                        : _onDuty
                                        ? 'GO OFF DUTY'
                                        : 'GO ON DUTY',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                active.isNotEmpty
                    ? 'Finish the active response before going off duty.'
                    : _onDuty
                    ? 'Keep this app open. Your location is shared with dispatch every 30 seconds so the nearest unit is asked first.'
                    : 'Switch on duty to receive alerts.',
                style: const TextStyle(
                  fontSize: 13,
                  color: RC.muted,
                  height: 1.4,
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _beat.problem,
                builder: (_, p, _) => p == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          p,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFFFB4A9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_offersLoading)
          const SkeletonList(rows: 2)
        else if (_offersError)
          ErrorState(
            message: 'Live offers could not be loaded.',
            onRetry: _retryOffers,
          )
        else if (orderedOpen.isNotEmpty) ...[
          const SectionLabel('WAITING FOR YOUR ANSWER'),
          const SizedBox(height: ResponderSpacing.md),
          for (var index = 0; index < orderedOpen.length; index++)
            _offerCard(orderedOpen[index], urgent: index == 0),
        ],
        if (!_offersLoading && !_offersError && earlierToday.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            iconColor: RC.muted,
            collapsedIconColor: RC.muted,
            title: Text(
              'Earlier today · ${earlierToday.length}',
              style: ResponderTextStyles.section,
            ),
            children: [
              for (final offer in earlierToday) _closedOfferCard(offer),
            ],
          ),
        if (!_offersLoading &&
            !_offersError &&
            orderedOpen.isEmpty &&
            active.isEmpty)
          EmptyState(
            icon: _onDuty ? Icons.notifications_none : Icons.power_settings_new,
            title: _onDuty ? 'No open alerts' : 'You are off duty',
            body: _onDuty
                ? 'New offers will appear here while this app is open.'
                : 'Go on duty to receive alerts.',
            actionLabel: _onDuty ? null : 'Go on duty',
            onAction: _onDuty ? null : () => _toggle(true),
          ),
      ],
    );
  }

  Widget _offerCard(Offer offer, {required bool urgent}) => Container(
    margin: const EdgeInsets.only(bottom: ResponderSpacing.md),
    padding: EdgeInsets.all(urgent ? ResponderSpacing.lg : ResponderSpacing.md),
    decoration: BoxDecoration(
      color: urgent ? RC.surface2 : RC.card,
      borderRadius: BorderRadius.circular(ResponderRadius.card),
      border: Border.all(color: urgent ? RC.outline : RC.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PriorityTag(priority: offer.priority),
            const Spacer(),
            Text(
              '${offer.secondsLeft()} s',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: RC.text,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: ResponderSpacing.md),
        Text(
          ResponderLabels.category(offer.category),
          style: ResponderTextStyles.section,
        ),
        if (offer.subtypeLabel.isNotEmpty)
          Text(offer.subtypeLabel, style: ResponderTextStyles.caption),
        const SizedBox(height: ResponderSpacing.sm),
        Wrap(
          spacing: ResponderSpacing.sm,
          runSpacing: ResponderSpacing.sm,
          children: [
            Chip2(ResponderLabels.capability(offer.role), RC.needBg, RC.needFg),
            Chip2(
              '${offer.distanceKm.toStringAsFixed(1)} km · straight line',
              RC.infoChipBg,
              RC.infoChipFg,
            ),
          ],
        ),
        const SizedBox(height: ResponderSpacing.md),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: () => unawaited(_presentIncoming(offer)),
            child: const Text('Open alert'),
          ),
        ),
      ],
    ),
  );

  Widget _closedOfferCard(Offer offer) => Padding(
    padding: const EdgeInsets.only(bottom: ResponderSpacing.sm),
    child: SectionCard(
      title: ResponderLabels.category(offer.category),
      trailing: Text(
        ResponderLabels.offerStatus(
          offer.status,
          withdrawReason: offer.withdrawReason,
        ),
        style: ResponderTextStyles.caption,
      ),
      child: InfoRow(
        label: '${hhmm(offer.createdAt)} · ${offer.priority}',
        value: '${offer.distanceKm.toStringAsFixed(1)} km · straight line',
      ),
    ),
  );

  Widget _activeJobs(List<Offer> active) {
    if (_offersLoading) return const SkeletonList(rows: 1);
    if (_offersError) {
      return ErrorState(
        message: 'Active responses could not be loaded.',
        onRetry: _retryOffers,
      );
    }
    if (active.isEmpty) {
      return const Center(
        child: Text(
          'No active responses.',
          style: TextStyle(fontSize: 16, color: RC.muted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        const SectionLabel('IN PROGRESS'),
        const SizedBox(height: 12),
        for (final offer in active)
          _card(
            offer,
            'Open response',
            () => Navigator.of(context).push(
              appRoute<void>(
                (_) => ActiveJobScreen(offerId: offer.id, repo: widget.repo),
              ),
            ),
          ),
      ],
    );
  }

  Widget _card(Offer o, String action, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: RC.card,
      borderRadius: BorderRadius.circular(16),
      border: Border(
        left: BorderSide(color: RC.priority(o.priority), width: 5),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                o.category,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: RC.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${o.priority} · ${o.distanceKm.toStringAsFixed(1)} km · ${_statusLabel(o.status)}',
                style: const TextStyle(fontSize: 13, color: RC.muted),
              ),
            ],
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: RC.accept,
            minimumSize: const Size(88, 44),
          ),
          onPressed: onTap,
          child: Text(action),
        ),
      ],
    ),
  );

  Widget _history(List<Offer> past) {
    if (past.isEmpty) {
      return const Center(
        child: Text(
          'Nothing here yet.',
          style: TextStyle(color: RC.muted, fontSize: 16),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: past.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final o = past[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RC.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.category,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: RC.text,
                      ),
                    ),
                    Text(
                      '${hhmm(o.createdAt)} · ${o.priority} · ${o.distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 12, color: RC.muted),
                    ),
                  ],
                ),
              ),
              Chip2(_statusLabel(o.status), RC.infoChipBg, RC.infoChipFg),
            ],
          ),
        );
      },
    );
  }

  static String _statusLabel(String s) => switch (s) {
    'offered' => 'Waiting',
    'accepted' => 'Accepted',
    'enroute' => 'On the way',
    'arrived' => 'Arrived',
    'completed' => 'Completed',
    'declined' => 'Declined',
    'expired' => 'Missed',
    'withdrawn' => 'Stood down',
    _ => s,
  };
}
