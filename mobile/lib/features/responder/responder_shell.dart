// The whole responder app: verification gate -> Home (duty switch, incoming and active jobs) and History.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/dispatch_models.dart';
import '../../core/services/push_service.dart';
import 'active_job_screen.dart';
import 'duty_heartbeat.dart';
import 'incoming_alert_screen.dart';
import 'responder_repository.dart';
import 'responder_theme.dart';
import 'track_publisher.dart';

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
          return const Scaffold(backgroundColor: RC.bg, body: Center(child: CircularProgressIndicator()));
        }
        final me = snap.data;
        if (me == null) {
          return const _Message(title: 'Profile not found', body: 'Your responder profile has not been set up. Please contact the administrator.');
        }
        if (me.verificationStatus != 'Verified') {
          final rejected = me.verificationStatus == 'Rejected' || me.verificationStatus == 'Suspended';
          return _Message(
            title: rejected ? 'Account ${me.verificationStatus.toLowerCase()}' : 'Waiting for verification',
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: RC.text)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(fontSize: 16, color: RC.soft, height: 1.45)),
          const SizedBox(height: 24),
          BigButton(label: 'Sign out', filled: false, height: 52, onPressed: () => FirebaseAuth.instance.signOut()),
        ]),
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

class _ResponderShellState extends State<ResponderShell> with WidgetsBindingObserver {
  int _tab = 0;
  late final DutyHeartbeat _beat = DutyHeartbeat(widget.repo);
  final Set<String> _shown = {};
  StreamSubscription<List<Offer>>? _sub;
  List<Offer> _offers = const [];
  bool _onDuty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushService.init();
    _onDuty = widget.me.availabilityStatus != 'Offline';
    if (_onDuty) _beat.start();
    _sub = widget.repo.watchOffers().listen((list) {
      if (!mounted) return;
      setState(() => _offers = list);
      TrackPublisher.instance.sync(list); // live location only while a job is held
      for (final o in list) {
        if (o.isOpen && o.secondsLeft() > 0 && _shown.add(o.id)) {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
          Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => IncomingAlertScreen(offer: o, repo: widget.repo)));
          break;
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _onDuty && !_beat.running) _beat.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _beat.dispose();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      final ok = await _beat.start();
      if (!ok) return;
      await widget.repo.setAvailability('Available');
    } else {
      _beat.stop();
      await widget.repo.setAvailability('Offline');
    }
    if (mounted) setState(() => _onDuty = on);
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
        title: Text(widget.me.organizationName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () async {
          _beat.stop();
          try { await widget.repo.setAvailability('Offline'); } catch (_) {}
          await FirebaseAuth.instance.signOut();
        })],
      ),
      body: SafeArea(child: _tab == 0 ? _home(open, active) : _history(past)),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(backgroundColor: RC.card, indicatorColor: RC.line, labelTextStyle: WidgetStateProperty.all(const TextStyle(color: RC.text, fontWeight: FontWeight.w600))),
        child: NavigationBar(selectedIndex: _tab, onDestinationSelected: (i) => setState(() => _tab = i), destinations: const [
          NavigationDestination(icon: Icon(Icons.notifications_active_outlined, color: RC.soft), label: 'Alerts'),
          NavigationDestination(icon: Icon(Icons.history, color: RC.soft), label: 'History'),
        ]),
      ),
    );
  }

  Widget _home(List<Offer> open, List<Offer> active) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(_onDuty ? 'You are on duty' : 'You are off duty', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: RC.text))),
            Switch(value: _onDuty, activeColor: RC.accept, onChanged: _toggle),
          ]),
          const SizedBox(height: 6),
          Text(_onDuty ? 'Keep this app open. Your location is shared with dispatch every 30 seconds so the nearest unit is asked first.' : 'Switch on duty to receive alerts.', style: const TextStyle(fontSize: 13, color: RC.muted, height: 1.4)),
          ValueListenableBuilder<String?>(
            valueListenable: _beat.problem,
            builder: (_, p, __) => p == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 8), child: Text(p, style: const TextStyle(fontSize: 13, color: Color(0xFFFFB4A9), fontWeight: FontWeight.w600))),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (open.isNotEmpty) ...[
        const SectionLabel('WAITING FOR YOUR ANSWER'),
        const SizedBox(height: 8),
        for (final o in open) _card(o, 'Answer now', () => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => IncomingAlertScreen(offer: o, repo: widget.repo)))),
      ],
      if (active.isNotEmpty) ...[
        const SizedBox(height: 8),
        const SectionLabel('YOUR ACTIVE JOBS'),
        const SizedBox(height: 8),
        for (final o in active) _card(o, 'Open', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ActiveJobScreen(offerId: o.id, repo: widget.repo)))),
      ],
      if (open.isEmpty && active.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No alerts right now.', style: TextStyle(fontSize: 16, color: RC.muted)))),
    ]);
  }

  Widget _card(Offer o, String action, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: RC.priority(o.priority), width: 5))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(o.category, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: RC.text)),
        const SizedBox(height: 2),
        Text('${o.priority} · ${o.distanceKm.toStringAsFixed(1)} km · ${_statusLabel(o.status)}', style: const TextStyle(fontSize: 13, color: RC.muted)),
      ])),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: RC.accept, minimumSize: const Size(88, 44)), onPressed: onTap, child: Text(action)),
    ]),
  );

  Widget _history(List<Offer> past) {
    if (past.isEmpty) return const Center(child: Text('Nothing here yet.', style: TextStyle(color: RC.muted, fontSize: 16)));
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: past.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final o = past[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.category, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RC.text)),
              Text('${hhmm(o.createdAt)} · ${o.priority} · ${o.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12, color: RC.muted)),
            ])),
            Chip2(_statusLabel(o.status), RC.infoChipBg, RC.infoChipFg),
          ]),
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
