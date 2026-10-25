// "Help is being sent" (approved resident design). Shows what the dispatch engine wrote to incident.dispatch.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/dispatch_models.dart';

/// Live dispatch information for one incident. Never errors: on failure the card simply shows "recorded".
Stream<DispatchInfo> watchDispatch(String incidentId) => FirebaseFirestore.instance
    .collection('incidents')
    .doc(incidentId)
    .snapshots()
    .map((s) => DispatchInfo.fromMap(s.data()?['dispatch']))
    .handleError((_) {});

Future<void> _call(String number) => launchUrl(Uri(scheme: 'tel', path: number));

class DispatchCard extends StatelessWidget {
  const DispatchCard({super.key, required this.info, this.onAddDetails});
  final DispatchInfo info;

  /// Shows the optional "Add more details" row when not null.
  final VoidCallback? onAddDetails;

  static const _ink = Color(0xFF1A1A1A);
  static const _mute = Color(0xFF5F5F5F);
  static const _danger = Color(0xFFB33A3A);

  IconData _icon(String role) => switch (role) {
    'fire_suppression' || 'extrication' => Icons.local_fire_department_outlined,
    'law_enforcement' => Icons.shield_outlined,
    _ => Icons.add,
  };

  Color _iconBg(String role) => switch (role) {
    'fire_suppression' || 'extrication' => const Color(0xFFFFF3E0),
    'law_enforcement' => const Color(0xFFE3F2FD),
    _ => const Color(0xFFE8F5E9),
  };

  Color _iconFg(String role) => switch (role) {
    'fire_suppression' || 'extrication' => const Color(0xFFE65100),
    'law_enforcement' => const Color(0xFF1565C0),
    _ => const Color(0xFF2E7D32),
  };

  (Color, Color) _pill(String status) => switch (status) {
    'offered' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
    'accepted' || 'enroute' || 'arrived' || 'completed' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
    _ => (const Color(0xFFFFF3E0), const Color(0xFF9C3700)),
  };

  @override
  Widget build(BuildContext context) {
    final good = !(info.state == 'unfilled' || info.state == 'no_location' || info.state == 'needs_review' || info.state == 'cancelled');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(shape: BoxShape.circle, color: good ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0)),
          child: Icon(good ? Icons.check : Icons.phone_in_talk_outlined, size: 20, color: good ? const Color(0xFF2E7D32) : const Color(0xFFE65100)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(info.headline, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15, color: _ink))),
      ]),
      const SizedBox(height: 6),
      Text(info.subline, style: const TextStyle(fontSize: 14, color: _mute, height: 1.45)),
      const SizedBox(height: 14),
      if (!info.hasUnits && good && info.state != 'support_only' && info.state != 'completed')
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)), SizedBox(width: 12), Expanded(child: Text('Looking for the nearest available responders…', style: TextStyle(fontSize: 14, color: _mute)))]),
        ),
      for (final u in info.units) _unit(u),
      if (info.hasUnits)
        const Padding(padding: EdgeInsets.only(top: 2, bottom: 10), child: Text('Distances are straight-line estimates.', style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)))),
      if (onAddDetails != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4))]),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Add more details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
              SizedBox(height: 2),
              Text('Optional. Helps responders prepare. About 30 seconds.', style: TextStyle(fontSize: 12, color: _mute)),
            ])),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), minimumSize: const Size(64, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: onAddDetails, child: const Text('Add')),
          ]),
        ),
      if (info.showCallBlock)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF4F4), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF2C4C4))),
          child: Text(info.reason.isNotEmpty ? info.reason : 'Please call 922 or 999 now.', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _danger, height: 1.4)),
        ),
      Row(children: [
        Expanded(child: _callBtn('Call 922', const Color(0xFFD94A4A), () => _call('922'))),
        const SizedBox(width: 10),
        Expanded(child: _callBtn('Call 999', _danger, () => _call('999'))),
      ]),
    ]);
  }

  Widget _callBtn(String label, Color c, VoidCallback f) => SizedBox(
    height: 56,
    child: FilledButton(style: FilledButton.styleFrom(backgroundColor: c, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: f, child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
  );

  Widget _unit(DispatchUnit u) {
    final (pillBg, pillFg) = _pill(u.status);
    final dist = u.distanceKm == null ? '' : ' · ${u.distanceKm!.toStringAsFixed(1)} km away';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4))]),
      child: Column(children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: _iconBg(u.role), borderRadius: BorderRadius.circular(14)), child: Icon(_icon(u.role), color: _iconFg(u.role))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 2),
            Text('${roleLabel(u.role)}$dist', style: const TextStyle(fontSize: 13, color: _mute)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)), child: Text(u.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pillFg))),
        ]),
        if (u.phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: _danger, side: const BorderSide(color: Color(0xFFD94A4A)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () => _call(u.phone), child: const Text('Call this unit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ),
        ],
      ]),
    );
  }
}
