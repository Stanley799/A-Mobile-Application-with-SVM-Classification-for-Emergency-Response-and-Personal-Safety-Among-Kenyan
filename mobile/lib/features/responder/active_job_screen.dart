// After accepting: who to call, where to go, the three steps, transport, notes, chat and the completion summary.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/dispatch_models.dart';
import '../resident/status/location_confidence.dart' show accuracyShort;
import 'incoming_alert_screen.dart' show openInMaps;
import 'job_chat_screen.dart';
import 'job_map_screen.dart';
import 'more_units_sheet.dart';
import 'responder_repository.dart';
import 'responder_theme.dart';
import 'sos_sheet.dart';
import 'track_publisher.dart';
import 'transport_models.dart';
import 'transport_screen.dart';

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
  bool _wellbeingDismissed = false;
  DateTime? _chatOpenedAt;
  List<JobMessage> _messages = const [];
  StreamSubscription<List<JobMessage>>? _messagesSub;
  String _incidentId = '';

  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  bool _notesLoaded = false;
  bool _notesDirty = false;
  bool _notesSaving = false;
  String? _notesError;
  String _savedNote = '';

  @override
  void initState() {
    super.initState();
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus && _notesDirty) unawaited(_saveNotes());
    });
  }

  /// Runs from the one offer stream the screen already listens to.
  void _syncFromOffer(Offer o) {
    if (o.incidentId.isNotEmpty && o.incidentId != _incidentId) {
      _watchMessages(o.incidentId);
    }
    if (!_notesLoaded) {
      _notesLoaded = true;
      _notes.text = o.note;
      _savedNote = o.note;
    }
  }

  void _watchMessages(String incidentId) {
    _incidentId = incidentId;
    _messagesSub?.cancel();
    _messagesSub = widget.repo.watchMessages(incidentId).listen(
      (m) {
        if (mounted) setState(() => _messages = m);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _notesFocus.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _unread {
    final since = _chatOpenedAt;
    return _messages
        .where(
          (m) =>
              m.fromDispatch &&
              (since == null || (m.at != null && m.at!.isAfter(since))),
        )
        .length;
  }

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
      // The server releases this unit's availability when it records the withdrawal.
      await widget.repo.respond(widget.offerId, 'withdrawn', withdrawReason: picked);
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

  Future<void> _openChat(Offer o) async {
    setState(() => _chatOpenedAt = DateTime.now());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobChatScreen(
          incidentId: o.incidentId,
          repo: widget.repo,
          systemLine: _moreUnitsLine(o),
        ),
      ),
    );
    if (mounted) setState(() => _chatOpenedAt = DateTime.now());
  }

  String? _moreUnitsLine(Offer o) {
    final mu = o.moreUnits;
    if (mu == null) return null;
    final at = mu.requestedAt;
    final when = at == null
        ? ''
        : ' at ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final count = mu.count == 1 ? '1 unit' : '${mu.count} units';
    return 'You asked dispatch for $count · ${moreUnitRoleLabel(mu.role)}$when. Dispatch has this request.';
  }

  Future<void> _openMoreUnits() async {
    final done = await showMoreUnitsSheet(
      context,
      onSubmit: (role, count, note) => widget.repo.requestMoreUnits(
        widget.offerId,
        role: role,
        count: count,
        note: note,
      ),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dispatch has been asked. Keep working. You will see an update here.',
          ),
        ),
      );
    }
  }

  Future<void> _startTransport(Offer o) async {
    final lat = o.latitude, lng = o.longitude;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The scene has no map position. Use Google Maps.')),
      );
      return;
    }
    final picked = await showTransportPicker(
      context,
      load: () => widget.repo.hospitalsNear(lat, lng),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.startTransport(
        widget.offerId,
        destinationId: picked.id,
        destinationName: picked.name,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start transport. Check your connection and try again.'),
          ),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _hospitalArrived() async {
    setState(() => _busy = true);
    try {
      await widget.repo.arriveAtHospital(widget.offerId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update. Check your connection and try again.'),
          ),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openTransportRoute(Offer o) async {
    final leg = o.transport;
    if (leg == null) return;
    final place = await widget.repo.facility(leg.destinationId);
    final fallback = place ??
        TransportDestination(
          id: leg.destinationId,
          name: leg.destinationName,
          type: 'hospital',
          latitude: o.latitude,
          longitude: o.longitude,
        );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransportMapScreen(offer: o, destination: fallback),
      ),
    );
  }

  Future<void> _saveNotes() async {
    final text = _notes.text.trim();
    if (text == _savedNote) {
      if (mounted) setState(() => _notesDirty = false);
      return;
    }
    setState(() {
      _notesSaving = true;
      _notesError = null;
    });
    try {
      await widget.repo.saveNote(widget.offerId, text);
      _savedNote = text;
      if (mounted) {
        setState(() {
          _notesDirty = false;
          _notesSaving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _notesSaving = false;
          _notesError = 'Not saved. Check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Offer?>(
      stream: widget.repo.watchOffer(widget.offerId),
      builder: (context, snap) {
        final o = snap.data;
        if (o != null) _syncFromOffer(o);
        return Scaffold(
          backgroundColor: RC.bg,
          appBar: AppBar(
            backgroundColor: RC.bg,
            foregroundColor: RC.text,
            elevation: 0,
            title: const Text('Active job'),
            actions: [
              if (o != null && o.isActiveJob)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: 'Chat with dispatch',
                    onPressed: () => _openChat(o),
                    icon: Badge(
                      isLabelVisible: _unread > 0,
                      smallSize: 9,
                      child: const Icon(Icons.forum_outlined),
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (value) {
                  if (value == 'sos') {
                    showSosSheet(context, widget.repo, incidentId: o?.incidentId);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'sos',
                    child: Row(
                      children: [
                        Icon(Icons.sos_rounded, color: RC.alert),
                        SizedBox(width: 10),
                        Text(
                          'I need help',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: RC.alert,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
    final held = o.isActiveJob;
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
            (o.freeText.isNotEmpty && !o.confidential) ||
            o.landmark.isNotEmpty) ...[
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
                if (o.landmark.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Landmark: ${o.landmark}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: RC.soft,
                      height: 1.4,
                    ),
                  ),
                ],
                if (accuracyShort(o.accuracyM) case final String line) ...[
                  const SizedBox(height: 6),
                  Text(
                    line,
                    style: const TextStyle(fontSize: 13, color: RC.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (closed) ...[
          const SizedBox(height: 16),
          _closedCard(o),
        ],
        if (o.status == 'completed') ...[
          const SizedBox(height: 12),
          _summaryCard(o),
          if (o.priority == 'High' && !_wellbeingDismissed) ...[
            const SizedBox(height: 12),
            _wellbeingCard(),
          ],
        ],
        if (o.transport != null) ...[
          const SizedBox(height: 12),
          _transportCard(o),
        ],
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
        if (held || o.status == 'completed') ...[
          const SizedBox(height: 16),
          _notesCard(),
        ],
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
        if (held) ...[
          const SizedBox(height: 16),
          _moreUnitsCard(o),
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
          if (o.status == 'arrived') ...[
            if (_needsTransport(o) && o.transport == null) ...[
              BigButton(
                label: 'Start transport',
                color: RC.accent,
                onPressed: _busy ? null : () => _startTransport(o),
              ),
              const SizedBox(height: 10),
            ],
            if (_needsTransport(o) && o.transport != null && !o.transport!.hasArrived) ...[
              BigButton(
                label: 'I have arrived at the hospital',
                color: RC.accent,
                onPressed: _busy ? null : _hospitalArrived,
              ),
              const SizedBox(height: 10),
            ],
            BigButton(
              label: 'Complete job',
              onPressed: _busy ? null : _confirmComplete,
            ),
          ],
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

  static bool _needsTransport(Offer o) =>
      o.role == 'medical_transport' || o.needs.contains('medical_transport');

  Widget _closedCard(Offer o) => Container(
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
  );

  /// 2.6: Beacon-style response times, from server-stamped offer times.
  Widget _summaryCard(Offer o) {
    final received = o.createdAt;
    final accepted = o.timeFor('accepted');
    final arrived = o.timeFor('arrived');
    final done = o.timeFor('completed') ?? o.respondedAt;
    final feedback = o.callerFeedbackSafe;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RC.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('RESPONSE TIMES'),
          const SizedBox(height: 10),
          _summaryRow('Received to accepted', received, accepted),
          _summaryRow('Accepted to arrived', accepted, arrived),
          _summaryRow('Arrived to complete', arrived, done),
          if (feedback != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  feedback ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: feedback ? RC.accept : RC.medium,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    feedback
                        ? 'Caller confirmed safe'
                        : 'Caller reported still needing help',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: feedback ? RC.accept : RC.medium,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, DateTime? from, DateTime? to) {
    final raw = from == null || to == null
        ? null
        : to.difference(from).inSeconds;
    final seconds = raw == null || raw >= 0 ? raw : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13.5, color: RC.soft),
            ),
          ),
          Text(
            seconds == null
                ? 'Not recorded'
                : seconds < 60
                ? '${seconds < 0 ? 0 : seconds} s'
                : '${seconds ~/ 60} min ${seconds % 60} s',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: seconds == null ? RC.muted : RC.text,
            ),
          ),
        ],
      ),
    );
  }

  /// 2.8: shown once after a High priority completion. Nothing is stored.
  Widget _wellbeingCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: RC.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: RC.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'That was a demanding call. If you want to talk to someone, ask your supervisor about peer support.',
          style: TextStyle(fontSize: 14.5, color: RC.text, height: 1.4),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _wellbeingDismissed = true),
            child: const Text('Dismiss'),
          ),
        ),
      ],
    ),
  );

  Widget _transportCard(Offer o) {
    final leg = o.transport!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RC.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            leg.hasArrived ? 'TRANSPORT COMPLETE' : 'TRANSPORTING TO',
          ),
          const SizedBox(height: 8),
          Text(
            leg.destinationName,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: RC.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            leg.hasArrived
                ? 'Arrived${_travelText(leg) == null ? '' : ' · ${_travelText(leg)} from the scene'}'
                : 'Take the patient there now. The route is in the app.',
            style: const TextStyle(fontSize: 13, color: RC.soft, height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _openTransportRoute(o),
            icon: const Icon(Icons.route_outlined, size: 18),
            label: const Text('Open route'),
          ),
        ],
      ),
    );
  }

  static String? _travelText(TransportLeg leg) {
    final d = leg.travelTime;
    if (d == null) return null;
    final s = d.inSeconds;
    return s < 60 ? '$s s' : '${s ~/ 60} min ${s % 60} s';
  }

  /// 2.7: notes are available at any time while the unit holds the job, saved when the field loses focus.
  Widget _notesCard() => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: RC.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('INCIDENT NOTES'),
        const SizedBox(height: 4),
        const Text(
          'Only you and dispatch can see these.',
          style: TextStyle(fontSize: 12, color: RC.muted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          focusNode: _notesFocus,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(color: RC.text, fontSize: 14.5, height: 1.4),
          onChanged: (_) {
            if (!_notesDirty) setState(() => _notesDirty = true);
          },
          decoration: InputDecoration(
            hintText: 'Street, gate, patient condition, anything the next unit should know.',
            hintStyle: const TextStyle(color: RC.muted, height: 1.4),
            filled: true,
            fillColor: RC.surface2,
            counterStyle: const TextStyle(color: RC.muted, fontSize: 11),
            border: const OutlineInputBorder(
              borderSide: BorderSide(color: RC.line),
            ),
          ),
        ),
        Row(
          children: [
            if (_notesSaving)
              const Text(
                'Saving…',
                style: TextStyle(fontSize: 12, color: RC.muted),
              )
            else if (_notesError != null)
              Expanded(
                child: Text(
                  _notesError!,
                  style: const TextStyle(fontSize: 12, color: RC.alert),
                ),
              )
            else if (_notesDirty)
              const Text(
                'Tap outside the box to save.',
                style: TextStyle(fontSize: 12, color: RC.muted),
              )
            else if (_savedNote.isNotEmpty)
              const Text(
                'Saved',
                style: TextStyle(fontSize: 12, color: RC.accept),
              ),
            const Spacer(),
            if (_notesError != null)
              TextButton(
                onPressed: _saveNotes,
                child: const Text('Retry'),
              ),
          ],
        ),
      ],
    ),
  );

  /// 2.3: request more units (once per offer), and the request status afterwards.
  Widget _moreUnitsCard(Offer o) {
    final mu = o.moreUnits;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RC.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('MORE UNITS'),
          const SizedBox(height: 8),
          if (mu == null) ...[
            const Text(
              'Need backup? Dispatch will alert the next nearest unit.',
              style: TextStyle(fontSize: 13.5, color: RC.soft, height: 1.4),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openMoreUnits,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Request more units'),
            ),
          ] else ...[
            Text(
              _moreUnitsLine(o) ?? '',
              style: const TextStyle(fontSize: 13.5, color: RC.text, height: 1.4),
            ),
            if (mu.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Your note: ${mu.note}',
                style: const TextStyle(fontSize: 12.5, color: RC.muted),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Dispatch has been asked. Keep working. You will see an update here.',
              style: TextStyle(fontSize: 12.5, color: RC.accept, height: 1.4),
            ),
          ],
        ],
      ),
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
