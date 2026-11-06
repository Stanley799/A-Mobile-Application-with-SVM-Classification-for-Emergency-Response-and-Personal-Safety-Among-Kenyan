import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_theme.dart';
import 'checkin_text.dart';

const List<String> _kOpen = ['Active', 'Grace', 'Level1', 'Level2'];
const List<int> _kLengthsMin = [15, 30, 60, 120, 240, 480];
const List<int> _kRemindMin = [0, 5, 10, 15];
const List<int> _kGraceMin = [2, 5, 10, 15];

FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: 'europe-west1');

String _problem(Object e) {
  if (e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty) return e.message!;
  return 'Something went wrong. Check your connection and try again.';
}

/// Safety Check-In: you choose how long, when to be reminded, who is told and whether Nusuru responders are called.
class SafetyCheckinV2Screen extends StatefulWidget {
  const SafetyCheckinV2Screen({super.key});

  @override
  State<SafetyCheckinV2Screen> createState() => _SafetyCheckinV2ScreenState();
}

class _SafetyCheckinV2ScreenState extends State<SafetyCheckinV2Screen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  Timer? _clock;
  Timer? _beat;
  String? _beatingFor;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _stream = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: _kOpen)
        .limit(1)
        .snapshots();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _beat?.cancel();
    super.dispose();
  }

  /// While this screen is open on an active check-in, tell the server every minute that the phone is alive, and where.
  void _ensureHeartbeat(String? id) {
    if (id == _beatingFor) return;
    _beat?.cancel();
    _beatingFor = id;
    if (id == null) return;
    Future<void> beat() async {
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        );
        await _fn.httpsCallable('checkin_heartbeat').call<dynamic>({'id': id, 'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy});
      } catch (_) {
        try {
          await _fn.httpsCallable('checkin_heartbeat').call<dynamic>({'id': id});
        } catch (_) {}
      }
    }

    beat();
    _beat = Timer.periodic(const Duration(seconds: 60), (_) => beat());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Safety Check-In', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Unable to load your check-in. Check your connection.', textAlign: TextAlign.center)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _ensureHeartbeat(null));
            return const _SetupView();
          }
          final doc = docs.first;
          WidgetsBinding.instance.addPostFrameCallback((_) => _ensureHeartbeat(doc.id));
          return _ActiveView(id: doc.id, data: doc.data());
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- setup
class _Contact {
  _Contact(this.id, this.name, this.phone);
  final String id;
  final String name;
  final String phone;
  bool picked = false;
  bool call = false;
}

class _SetupView extends StatefulWidget {
  const _SetupView();

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  int _lengthMin = 30;
  int _remindMin = 5;
  int _graceMin = 5;
  bool _responders = true;
  bool _share = false;
  bool _busy = false;
  String? _error;
  final _note = TextEditingController();
  List<_Contact>? _contacts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final q = await FirebaseFirestore.instance
          .collection('trustedContacts')
          .where('userId', isEqualTo: uid)
          .where('isActive', isEqualTo: true)
          .get();
      final list = [
        for (final d in q.docs)
          if (((d.data()['phoneNumber'] as String?) ?? '').isNotEmpty)
            _Contact(d.id, (d.data()['name'] as String?) ?? '', d.data()['phoneNumber'] as String),
      ];
      if (mounted) setState(() => _contacts = list);
    } catch (_) {
      if (mounted) setState(() => _contacts = []);
    }
  }

  Future<void> _customLength() async {
    final c = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom length'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Minutes (5 to 720)')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(int.tryParse(c.text.trim())), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v >= 5 && v <= 720 && mounted) setState(() => _lengthMin = v);
  }

  Future<void> _start() async {
    final picked = (_contacts ?? []).where((c) => c.picked).toList();
    if (picked.length > 5) {
      setState(() => _error = 'Choose at most 5 contacts.');
      return;
    }
    if (picked.isEmpty && !_responders) {
      setState(() => _error = 'Choose a contact, or allow Nusuru responders to be alerted.');
      return;
    }
    if (_remindMin > 0 && _remindMin * 60 >= _lengthMin * 60) {
      setState(() => _error = 'The reminder must come before the end of the check-in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Map<String, dynamic>? loc;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
        loc = {'lat': p.latitude, 'lng': p.longitude, 'acc': p.accuracy};
      }
    } catch (_) {}
    try {
      await _fn.httpsCallable('checkin_start').call<dynamic>({
        'durationSec': _lengthMin * 60,
        'note': _note.text.trim(),
        'location': loc,
        'plan': {
          'graceSec': _graceMin * 60,
          'remindBeforeSec': _remindMin == 0 ? <int>[] : [_remindMin * 60],
          'escalateToResponders': _responders,
          'shareLocation': _share,
          'contacts': [
            for (final c in picked) {'id': c.id, 'name': c.name, 'phone': c.phone, 'methods': c.call ? ['sms', 'voice'] : ['sms']},
          ],
        },
      });
    } catch (e) {
      if (mounted) setState(() => _error = _problem(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _chips<T>(List<T> values, T current, String Function(T) label, void Function(T) pick) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values) ChoiceChip(label: Text(label(v)), selected: v == current, onSelected: (_) => setState(() => pick(v))),
        ],
      );

  Widget _section(String title, String? help, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (help != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(help, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          const SizedBox(height: AppSpacing.sm),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final custom = !_kLengthsMin.contains(_lengthMin);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tell Nusuru when to expect you.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('If you do not check in, we remind you first, then tell your contacts, then (if you allow it) alert nearby responders.',
                style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xl),
            _section(
              'How long?',
              null,
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in _kLengthsMin) ChoiceChip(label: Text(checkinLengthLabel(m * 60)), selected: m == _lengthMin, onSelected: (_) => setState(() => _lengthMin = m)),
                ChoiceChip(label: Text(custom ? checkinLengthLabel(_lengthMin * 60) : 'Custom'), selected: custom, onSelected: (_) => _customLength()),
              ]),
            ),
            _section('Remind me', 'A notification before your time is up.', _chips<int>(_kRemindMin, _remindMin, (m) => m == 0 ? 'No reminder' : '$m min before', (m) => _remindMin = m)),
            _section('Grace period', 'Extra time after your deadline before your contacts are told.', _chips<int>(_kGraceMin, _graceMin, (m) => '$m min', (m) => _graceMin = m)),
            _section(
              'Who should be told?',
              'They get an SMS with a page where they can say they are checking on you.',
              _contacts == null
                  ? const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
                  : _contacts!.isEmpty
                      ? const Text('You have no trusted contacts yet. Add them from your profile, then come back.', style: TextStyle(color: AppColors.textSecondary))
                      : Column(children: [
                          for (final c in _contacts!)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.divider)),
                              child: Column(children: [
                                CheckboxListTile(
                                  value: c.picked,
                                  onChanged: (v) => setState(() => c.picked = v ?? false),
                                  title: Text(c.name.isEmpty ? c.phone : c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(c.phone),
                                ),
                                if (c.picked)
                                  SwitchListTile(
                                    dense: true,
                                    value: c.call,
                                    onChanged: (v) => setState(() => c.call = v),
                                    title: const Text('Also call them if they do not answer the SMS'),
                                  ),
                              ]),
                            ),
                        ]),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _responders,
              onChanged: (v) => setState(() => _responders = v),
              title: const Text('Alert Nusuru responders if nobody responds', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('About 15 minutes after your contacts are told, an alert goes out with your last known location.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _share,
              onChanged: (v) => setState(() => _share = v),
              title: const Text('Show my last location to my contacts', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Responders always get it. Contacts only if this is on.'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: 'Note for your contacts (optional)', hintText: 'e.g. Walking home from campus via Ole Sangale')),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _start,
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text('Start ${checkinLengthLabel(_lengthMin * 60)} check-in', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- active
class _ActiveView extends StatefulWidget {
  const _ActiveView({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  State<_ActiveView> createState() => _ActiveViewState();
}

class _ActiveViewState extends State<_ActiveView> {
  bool _busy = false;

  Future<void> _close(String status) async {
    setState(() => _busy = true);
    try {
      await _fn.httpsCallable('checkin_close').call<dynamic>({'id': widget.id, 'status': status});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_problem(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel check-in?'),
        content: const Text('This ends the timer. Anyone already told is sent an all-clear.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancel check-in')),
        ],
      ),
    );
    if (ok == true) await _close('Cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final status = (d['status'] as String?) ?? 'Active';
    final ts = d['expiryTime'];
    final expiry = ts is Timestamp ? ts.toDate() : DateTime.now();
    final plan = (d['plan'] as Map?) ?? const {};
    final graceSec = (plan['graceSec'] as num?)?.toInt() ?? 300;
    final totalSec = ((d['durationMinutes'] as num?)?.toInt() ?? 0) * 60;
    final now = DateTime.now();
    final remaining = expiry.difference(now).inSeconds;
    final progress = totalSec <= 0 ? 0.0 : (remaining / totalSec).clamp(0.0, 1.0);
    final late = status != 'Active' || remaining <= 0;
    final names = [for (final c in (plan['contacts'] as List? ?? const [])) if (c is Map && (c['name'] ?? '').toString().isNotEmpty) c['name'].toString()];
    final color = status == 'Level2' ? Colors.red.shade700 : (late ? AppColors.warning : AppColors.brand);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: color.withValues(alpha: 0.4))),
              child: Text(checkinStatusText(status, expiry: expiry, graceSec: graceSec, now: now), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color, height: 1.35)),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 220, height: 220, child: CircularProgressIndicator(value: late ? 1.0 : progress, strokeWidth: 10, color: color, backgroundColor: AppColors.neutralLight)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(late ? 'Overdue' : checkinClock(remaining), style: TextStyle(fontSize: late ? 28 : 40, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  if (!late) const Text('left', style: TextStyle(color: AppColors.textSecondary)),
                ]),
              ]),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _close('CheckedIn'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("I'm safe, check in", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(backgroundColor: AppColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _busy ? null : _confirmCancel, child: const Text('Cancel check-in', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600))),
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.divider)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(names.isEmpty ? 'No contacts chosen.' : 'Contacts: ${names.join(', ')}', style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(plan['escalateToResponders'] == false ? 'Responders will not be alerted.' : 'Nusuru responders are alerted if nobody responds.', style: const TextStyle(color: AppColors.textSecondary)),
                if (((d['note'] as String?) ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Note: ${d['note']}', style: const TextStyle(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 8),
                const Text('Keep this screen open so your location stays fresh. Background tracking comes in the next update.', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
