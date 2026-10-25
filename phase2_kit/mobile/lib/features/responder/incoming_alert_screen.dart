// "Responder: incoming alert" (approved design). Dark, big, readable in a moving vehicle.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import 'active_job_screen.dart';
import 'responder_repository.dart';
import 'responder_theme.dart';

Future<void> openInMaps(double? lat, double? lng) async {
  if (lat == null || lng == null) return;
  await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication);
}

String hhmm(DateTime? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class IncomingAlertScreen extends StatefulWidget {
  const IncomingAlertScreen({super.key, required this.offer, required this.repo});
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
  String? _lost; // message when someone else took it, it expired or was cancelled

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _sub = widget.repo.watchOffer(widget.offer.id).listen((o) {
      if (o == null || !mounted) return;
      setState(() => _offer = o);
      if (!o.isOpen && !_busy && o.status != 'accepted') _gone(o);
    });
  }

  void _gone(Offer o) {
    final why = switch (o.withdrawReason) {
      'another_unit_accepted' || 'role_already_filled' => 'Another unit accepted this alert.',
      'incident_cancelled' => 'The resident cancelled this alert.',
      _ => o.status == 'expired' ? 'Time ran out for this alert.' : 'This alert is no longer open.',
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
    setState(() => _busy = true);
    try {
      await widget.repo.respond(_offer.id, status);
      if (!mounted) return;
      if (status == 'accepted') {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ActiveJobScreen(offerId: _offer.id, repo: widget.repo)));
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
    final total = 45;
    final danger = o.flags;
    return Scaffold(
      backgroundColor: RC.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: RC.priority(o.priority), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('NEW ALERT · ${o.priority.toUpperCase()} PRIORITY', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white)),
                    Text(hhmm(o.createdAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.category, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1, color: RC.text)),
                        if (o.subtypeLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_cap(o.subtypeLabel), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: RC.soft)),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 76,
                          height: 76,
                          child: CircularProgressIndicator(value: o.isOpen ? left / total : 0, strokeWidth: 5, backgroundColor: RC.line, color: left <= 10 ? const Color(0xFFFF8A80) : const Color(0xFF80CBC4)),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$left', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1, color: RC.text)),
                            const Text('seconds', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: RC.muted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${o.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1, color: RC.text)),
                        const SizedBox(width: 8),
                        const Text('away, straight line', style: TextStyle(fontSize: 14, color: RC.muted)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: RC.text, side: const BorderSide(color: RC.outline), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => openInMaps(o.latitude, o.longitude),
                        child: const Text('Open location in Maps', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionLabel('WHAT WE KNOW'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in danger) Chip2(f, RC.dangerChipBg, RC.dangerChipFg),
                Chip2(o.peopleCount == 1 ? '1 person' : '${o.peopleCount} people', RC.infoChipBg, RC.infoChipFg),
                if (danger.isEmpty) const Chip2('No danger signs reported yet', RC.infoChipBg, RC.infoChipFg),
              ]),
              if (o.needs.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionLabel('NEEDED FROM YOU'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final n in o.needs) Chip2(roleLabel(n), RC.needBg, RC.needFg)]),
              ],
              if (o.freeText.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionLabel('CALLER SAID'),
                const SizedBox(height: 6),
                Text(o.freeText, style: const TextStyle(fontSize: 14, color: RC.soft, height: 1.4)),
              ],
              const SizedBox(height: 12),
              const Text("The caller's name and phone number are shared after you accept.", style: TextStyle(fontSize: 12, color: RC.muted, height: 1.45)),
              const Spacer(),
              if (_lost != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: RC.card, borderRadius: BorderRadius.circular(16)),
                  child: Text(_lost!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RC.text)),
                )
              else ...[
                BigButton(label: 'Accept and go', onPressed: (_busy || !o.isOpen || left == 0) ? null : () => _answer('accepted')),
                const SizedBox(height: 10),
                BigButton(label: 'Cannot respond', filled: false, height: 52, onPressed: _busy ? null : () => _answer('declined')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
