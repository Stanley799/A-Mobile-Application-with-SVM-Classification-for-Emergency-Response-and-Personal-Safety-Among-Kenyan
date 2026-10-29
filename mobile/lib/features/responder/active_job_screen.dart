// After accepting: who to call, where to go, and the three steps (on my way, arrived, completed).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import 'incoming_alert_screen.dart' show openInMaps;
import 'job_map_screen.dart';
import 'responder_repository.dart';
import 'responder_theme.dart';
import 'track_publisher.dart';

class ActiveJobScreen extends StatefulWidget {
  const ActiveJobScreen({super.key, required this.offerId, required this.repo});
  final String offerId;
  final ResponderRepository repo;

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen> {
  bool _busy = false;
  bool _stoodDown = false;

  Future<void> _move(String status) async {
    setState(() => _busy = true);
    try {
      await widget.repo.respond(widget.offerId, status);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update. Check your connection and try again.',
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  static const _withdrawReasons = [
    ('cannot_reach', 'I cannot get there', 'Blocked route, no vehicle or too far.'),
    ('scene_unsafe', 'The scene is not safe for me', 'I need backup or a different unit.'),
    ('unit_broken_down', 'My unit has broken down', 'Vehicle or equipment failure.'),
    ('no_longer_available', 'I am no longer available', 'Something else came up.'),
  ];

  Future<void> _standDown() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              'Stand down from this job?',
              style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Only do this if you truly cannot respond. The system will immediately alert the next nearest unit, and the caller stays informed.',
              style: TextStyle(color: RC.soft, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final (value, label, hint) in _withdrawReasons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(hint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, value),
              ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Keep the job'),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.respond(widget.offerId, 'withdrawn', withdrawReason: picked);
      // The server only flips Busy -> Available on its own withdrawals; after standing down we release ourselves.
      await widget.repo.setAvailability('Available');
      if (mounted) {
        setState(() => _stoodDown = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You stood down. The next nearest unit is being alerted.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stand down. Check your connection and try again.')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmComplete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Complete this job?'),
        content: const Text(
          'Only complete it when the person has been helped or handed over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (yes == true) await _move('completed');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Offer?>(
      stream: widget.repo.watchOffer(widget.offerId),
      builder: (context, snap) {
        final o = snap.data;
        return Scaffold(
          backgroundColor: RC.bg,
          appBar: AppBar(
            backgroundColor: RC.bg,
            foregroundColor: RC.text,
            elevation: 0,
            title: const Text('Active job'),
          ),
          body: snap.hasError
              ? const Center(
                  child: Text(
                    'Unable to load this response. Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: RC.soft),
                  ),
                )
              : o == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    children: [_body(o)],
                  ),
                ),
        );
      },
    );
  }

  Widget _body(Offer o) {
    final closed =
        o.status == 'withdrawn' ||
        o.status == 'completed' ||
        o.status == 'expired';
    final name = (o.residentFirstName ?? '').trim();
    final phone = o.residentPhone ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: TrackPublisher.instance.problem,
          builder: (context, problem, _) {
            if (problem == null || problem.isEmpty) {
              return const SizedBox.shrink();
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                problem,
                style: const TextStyle(
                  color: Color(0xFFB33A3A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RC.priority(o.priority),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '${o.priority.toUpperCase()} PRIORITY · ${o.category}${o.subtypeLabel.isEmpty ? '' : ' · ${o.subtypeLabel}'}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        if (o.isActiveJob || o.status == 'completed') ...[
          const SizedBox(height: 12),
          _progress(o.status),
        ],
        if (o.summary.isNotEmpty ||
            (o.freeText.isNotEmpty && !o.confidential)) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: RC.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('INCIDENT BRIEF'),
                if (o.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    o.summary,
                    style: const TextStyle(
                      fontSize: 15,
                      color: RC.text,
                      height: 1.4,
                    ),
                  ),
                ],
                if (o.freeText.isNotEmpty && !o.confidential) ...[
                  const SizedBox(height: 10),
                  Text(
                    o.freeText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: RC.soft,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (closed)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: RC.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.status == 'completed'
                      ? 'Job completed. Thank you.'
                      : _stoodDown
                      ? 'You stood down from this job. Dispatch has alerted the next nearest unit, and the caller can see the update.'
                      : o.withdrawReason == 'incident_cancelled'
                      ? 'The resident cancelled this alert. You can stand down.'
                      : 'This job is no longer open.',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: RC.text,
                  ),
                ),
                if (_stoodDown) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'You are back to Available, so you can take the next call.',
                    style: TextStyle(fontSize: 13, color: RC.soft, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: RC.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('CALLER'),
              const SizedBox(height: 8),
              Text(
                name.isEmpty ? 'Resident' : name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: RC.text,
                ),
              ),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  style: const TextStyle(fontSize: 15, color: RC.soft),
                ),
              const SizedBox(height: 12),
              BigButton(
                label: phone.isEmpty ? 'Phone not available' : 'Call caller',
                height: 52,
                color: RC.accept,
                onPressed: phone.isEmpty
                    ? null
                    : () => launchUrl(Uri(scheme: 'tel', path: phone)),
              ),
              const SizedBox(height: 10),
              if (o.isActiveJob) ...[
                BigButton(
                  label: 'Live map — see the caller move',
                  height: 52,
                  color: RC.accent,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => JobMapScreen(offer: o)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              BigButton(
                label: 'Open location in Google Maps',
                filled: false,
                height: 52,
                onPressed: () => openInMaps(o.latitude, o.longitude),
              ),
              const SizedBox(height: 8),
              Text(
                '${o.distanceKm.toStringAsFixed(1)} km from where you were, straight line',
                style: const TextStyle(fontSize: 12, color: RC.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('WHAT WE KNOW'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in o.flags) Chip2(f, RC.dangerChipBg, RC.dangerChipFg),
            Chip2(
              o.peopleCount == 1 ? '1 person' : '${o.peopleCount} people',
              RC.infoChipBg,
              RC.infoChipFg,
            ),
          ],
        ),
        if (o.needs.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('RESPONSE CAPABILITIES'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final need in o.needs)
                Chip2(roleLabel(need), RC.needBg, RC.needFg),
            ],
          ),
        ],
        const SizedBox(height: 24),
        if (!closed) ...[
          if (o.status == 'accepted')
            BigButton(
              label: "I'm on my way",
              onPressed: _busy ? null : () => _move('enroute'),
            ),
          if (o.status == 'enroute')
            BigButton(
              label: 'I have arrived',
              onPressed: _busy ? null : () => _move('arrived'),
            ),
          if (o.status == 'arrived')
            BigButton(
              label: 'Complete job',
              onPressed: _busy ? null : _confirmComplete,
            ),
          if (o.status == 'accepted' || o.status == 'enroute') ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : _standDown,
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text("I can't take this job"),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _progress(String status) {
    final current = switch (status) {
      'accepted' => 0,
      'enroute' => 1,
      'arrived' => 2,
      'completed' => 3,
      _ => 0,
    };
    const steps = ['Accepted', 'En route', 'Arrived', 'Complete'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RC.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('RESPONSE PROGRESS'),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var index = 0; index < steps.length; index++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index <= current ? RC.accept : RC.line,
                        ),
                        child: index < current
                            ? const Icon(
                                Icons.check,
                                size: 15,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        steps[index],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: index <= current ? RC.text : RC.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
