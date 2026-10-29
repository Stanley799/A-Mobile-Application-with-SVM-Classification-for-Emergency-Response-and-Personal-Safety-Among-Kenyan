// "Responder: incoming alert" (approved design). Dark, big, readable in a moving vehicle.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import 'active_job_screen.dart';
import 'responder_labels.dart';
import 'responder_repository.dart';
import 'responder_theme.dart';
import 'responder_widgets.dart';
import '../../core/ui/routes.dart';

Future<void> openInMaps(double? lat, double? lng) async {
  if (lat == null || lng == null) return;
  await launchUrl(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
    mode: LaunchMode.externalApplication,
  );
}

String hhmm(DateTime? t) => t == null
    ? ''
    : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class IncomingAlertScreen extends StatefulWidget {
  const IncomingAlertScreen({
    super.key,
    required this.offer,
    required this.repo,
  });
  final Offer offer;
  final ResponderRepository repo;

  @override
  State<IncomingAlertScreen> createState() => _IncomingAlertScreenState();
}

class _IncomingAlertScreenState extends State<IncomingAlertScreen> {
  Timer? _tick;
  StreamSubscription<Offer?>? _sub;
  late Offer _offer = widget.offer;
  bool _busy = false;
  String?
  _lost; // message when someone else took it, it expired or was cancelled

  @override
  void initState() {
    super.initState();
    // 2.1: the first time this screen is shown, record it on the offer (rules accept this once, while it is open).
    if (widget.offer.seenAt == null) {
      unawaited(widget.repo.markSeen(widget.offer.id).catchError((Object _) {}));
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Grace of a few seconds past zero: client clocks can run ahead of the
      // server, which is what actually expires the offer.
      if (_offer.isOpen && _offer.secondsLeft() <= -3 && _lost == null) {
        setState(() => _lost = 'The response window closed.');
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).pop();
        });
        return;
      }
      setState(() {});
    });
    _sub = widget.repo.watchOffer(widget.offer.id).listen((o) {
      if (o == null || !mounted) return;
      setState(() => _offer = o);
      if (!o.isOpen && !_busy && o.status != 'accepted') _gone(o);
    });
  }

  void _gone(Offer o) {
    if (_lost != null) return;
    final why = switch (o.withdrawReason) {
      'another_unit_accepted' ||
      'role_already_filled' => 'Another unit accepted this alert.',
      'incident_cancelled' => 'The resident cancelled this alert.',
      _ =>
        o.status == 'expired'
            ? 'Time ran out for this alert.'
            : 'This alert is no longer open.',
    };
    setState(() => _lost = why);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _answer(String status) async {
    if (!_offer.isOpen || _offer.secondsLeft() == 0) return;
    setState(() => _busy = true);
    try {
      await widget.repo.respond(_offer.id, status);
      if (!mounted) return;
      if (status == 'accepted') {
        Navigator.of(context).pushReplacement(
          appRoute<void>(
            (_) => ActiveJobScreen(offerId: _offer.id, repo: widget.repo),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lost = 'Too late. This alert was taken, cancelled or has expired.';
      });
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _offer;
    final left = o.secondsLeft();
    final canAnswer = !_busy && o.isOpen && left > 0;
    return Scaffold(
      backgroundColor: RC.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _lost != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(ResponderSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 44,
                              color: RC.muted,
                            ),
                            const SizedBox(height: ResponderSpacing.md),
                            Text(
                              _lost!,
                              textAlign: TextAlign.center,
                              style: ResponderTextStyles.section,
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        ResponderSpacing.lg,
                        ResponderSpacing.lg,
                        ResponderSpacing.lg,
                        ResponderSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              PriorityTag(priority: o.priority),
                              const SizedBox(width: ResponderSpacing.sm),
                              Expanded(
                                child: Text(
                                  _receivedAge(o.createdAt),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ResponderTextStyles.caption,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: ResponderSpacing.md),
                          Text(
                            ResponderLabels.category(o.category),
                            style: ResponderTextStyles.title,
                          ),
                          if (o.subtypeLabel.isNotEmpty) ...[
                            const SizedBox(height: ResponderSpacing.xs),
                            Text(
                              o.subtypeLabel,
                              style: ResponderTextStyles.body,
                            ),
                          ],
                          const SizedBox(height: ResponderSpacing.lg),
                          Center(
                            child: CountdownRing(
                              secondsLeft: left,
                              totalSeconds: _windowSeconds(o),
                            ),
                          ),
                          const SizedBox(height: ResponderSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  value:
                                      '${o.distanceKm.toStringAsFixed(1)} km',
                                  label: 'Straight-line distance',
                                  icon: Icons.near_me_outlined,
                                ),
                              ),
                              const SizedBox(width: ResponderSpacing.sm),
                              Expanded(
                                child: StatTile(
                                  value: '${o.peopleCount}',
                                  label: o.peopleCount == 1
                                      ? 'Person reported'
                                      : 'People reported',
                                  icon: Icons.people_outline,
                                ),
                              ),
                            ],
                          ),
                          if (o.needs.isNotEmpty) ...[
                            const SizedBox(height: ResponderSpacing.lg),
                            const Text(
                              'Needed from you',
                              style: ResponderTextStyles.section,
                            ),
                            const SizedBox(height: ResponderSpacing.sm),
                            Wrap(
                              spacing: ResponderSpacing.sm,
                              runSpacing: ResponderSpacing.sm,
                              children: [
                                for (final need in o.needs)
                                  Chip2(
                                    ResponderLabels.capability(need),
                                    RC.needBg,
                                    RC.needFg,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: ResponderSpacing.xl),
                          SectionCard(
                            title: 'More details',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'What we know',
                                  style: ResponderTextStyles.section,
                                ),
                                const SizedBox(height: ResponderSpacing.sm),
                                if (o.flags.isEmpty)
                                  const Text(
                                    'No danger signs reported yet.',
                                    style: ResponderTextStyles.caption,
                                  )
                                else
                                  Wrap(
                                    spacing: ResponderSpacing.sm,
                                    runSpacing: ResponderSpacing.sm,
                                    children: [
                                      for (final flag in o.flags)
                                        Chip2(
                                          flag,
                                          RC.dangerChipBg,
                                          RC.dangerChipFg,
                                        ),
                                    ],
                                  ),
                                if (o.landmark.isNotEmpty) ...[
                                  const SizedBox(height: ResponderSpacing.lg),
                                  const Text(
                                    'Landmark',
                                    style: ResponderTextStyles.section,
                                  ),
                                  const SizedBox(height: ResponderSpacing.xs),
                                  Text(
                                    o.landmark,
                                    style: ResponderTextStyles.body,
                                  ),
                                ],
                                if (o.freeText.isNotEmpty &&
                                    !o.confidential) ...[
                                  const SizedBox(height: ResponderSpacing.lg),
                                  const Text(
                                    'Caller description',
                                    style: ResponderTextStyles.section,
                                  ),
                                  const SizedBox(height: ResponderSpacing.xs),
                                  Text(
                                    o.freeText,
                                    style: ResponderTextStyles.body,
                                  ),
                                ],
                                const SizedBox(height: ResponderSpacing.md),
                                const Text(
                                  'Caller name and phone are shared after you accept.',
                                  style: ResponderTextStyles.caption,
                                ),
                                const SizedBox(height: ResponderSpacing.md),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      openInMaps(o.latitude, o.longitude),
                                  icon: const Icon(Icons.map_outlined),
                                  label: const Text('Open location in Maps'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            PrimaryActionBar(
              primary: _lost != null
                  ? FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back to alerts'),
                    )
                  : FilledButton(
                      onPressed: canAnswer ? () => _answer('accepted') : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: RC.accept,
                        foregroundColor: const Color(0xFF04130C),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF04130C),
                              ),
                            )
                          : const Text(
                              'Accept and go',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
              secondary: _lost != null
                  ? null
                  : OutlinedButton(
                      onPressed: canAnswer && !_busy
                          ? () => _answer('declined')
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RC.text,
                        side: const BorderSide(color: RC.outline),
                      ),
                      child: const Text('Cannot respond'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Offer windows differ (automatic 45s, admin-assigned 90s): derive the ring's total from the timestamps.
  static int _windowSeconds(Offer o) {
    final created = o.createdAt;
    final expires = o.expiresAt;
    if (created == null || expires == null) return 45;
    return expires.difference(created).inSeconds.clamp(1, 600);
  }

  String _receivedAge(DateTime? createdAt) {
    if (createdAt == null) return 'Just received';
    final seconds = DateTime.now()
        .difference(createdAt)
        .inSeconds
        .clamp(0, 999999);
    return seconds < 60
        ? 'Received ${seconds}s ago'
        : 'Received ${seconds ~/ 60}m ago';
  }
}
