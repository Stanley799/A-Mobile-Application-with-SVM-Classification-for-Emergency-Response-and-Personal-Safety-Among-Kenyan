// After accepting: who to call, where to go, and the three steps (on my way, arrived, completed).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import 'incoming_alert_screen.dart' show openInMaps;
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

  Future<void> _move(String status) async {
    setState(() => _busy = true);
    try {
      await widget.repo.respond(widget.offerId, status);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update. Check your connection and try again.')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmComplete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Complete this job?'),
        content: const Text('Only complete it when the person has been helped or handed over.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Complete'))],
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
          appBar: AppBar(backgroundColor: RC.bg, foregroundColor: RC.text, elevation: 0, title: const Text('Active job')),
          body: o == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [_body(o)]),
                ),
        );
      },
    );
  }

  Widget _body(Offer o) {
    final closed = o.status == 'withdrawn' || o.status == 'completed' || o.status == 'expired';
    final name = (o.residentFirstName ?? '').trim();
    final phone = o.residentPhone ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder<String?>(
        valueListenable: TrackPublisher.instance.problem,
        builder: (context, problem, _) {
          if (problem == null || problem.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF4F4), borderRadius: BorderRadius.circular(10)),
            child: Text(problem, style: const TextStyle(color: Color(0xFFB33A3A), fontSize: 13, fontWeight: FontWeight.w600)),
          );
        },
      ),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: RC.priority(o.priority), borderRadius: BorderRadius.circular(14)),
        child: Text('${o.priority.toUpperCase()} PRIORITY · ${o.category}${o.subtypeLabel.isEmpty ? '' : ' · ${o.subtypeLabel}'}', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      const SizedBox(height: 16),
      if (closed)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(16)),
          child: Text(
            o.status == 'completed'
                ? 'Job completed. Thank you.'
                : o.withdrawReason == 'incident_cancelled'
                    ? 'The resident cancelled this alert. You can stand down.'
                    : 'This job is no longer open.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RC.text),
          ),
        ),
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('CALLER'),
          const SizedBox(height: 8),
          Text(name.isEmpty ? 'Resident' : name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: RC.text)),
          if (phone.isNotEmpty) Text(phone, style: const TextStyle(fontSize: 15, color: RC.soft)),
          const SizedBox(height: 12),
          BigButton(label: phone.isEmpty ? 'Phone not available' : 'Call caller', height: 52, color: RC.accept, onPressed: phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: phone))),
          const SizedBox(height: 10),
          BigButton(label: 'Open location in Maps', filled: false, height: 52, onPressed: () => openInMaps(o.latitude, o.longitude)),
          const SizedBox(height: 8),
          Text('${o.distanceKm.toStringAsFixed(1)} km from where you were, straight line', style: const TextStyle(fontSize: 12, color: RC.muted)),
        ]),
      ),
      const SizedBox(height: 16),
      const SectionLabel('WHAT WE KNOW'),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in o.flags) Chip2(f, RC.dangerChipBg, RC.dangerChipFg),
        Chip2(o.peopleCount == 1 ? '1 person' : '${o.peopleCount} people', RC.infoChipBg, RC.infoChipFg),
      ]),
      const SizedBox(height: 24),
      if (!closed) ...[
        if (o.status == 'accepted') BigButton(label: "I'm on my way", onPressed: _busy ? null : () => _move('enroute')),
        if (o.status == 'enroute') BigButton(label: 'I have arrived', onPressed: _busy ? null : () => _move('arrived')),
        if (o.status == 'arrived') BigButton(label: 'Complete job', onPressed: _busy ? null : _confirmComplete),
      ],
    ]);
  }
}
