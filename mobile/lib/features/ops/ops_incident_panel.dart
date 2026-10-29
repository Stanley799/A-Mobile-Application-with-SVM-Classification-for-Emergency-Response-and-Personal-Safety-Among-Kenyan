// The incident panel shared by the dispatcher and the administrator: Overview, Candidates, Timeline,
// Messages, Caller check-in and Actions. The same widget is used read-only from the Incidents page.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import '../resident/status/location_confidence.dart';
import 'ops_logic.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

enum OpsPanelTab { overview, candidates, timeline, messages, checkin, actions }

const Map<String, String> _eventWords = {
  'incident_created': 'Alert created',
  'classified': 'Category and priority set',
  'priority_set': 'Priority set',
  'offer_sent': 'Unit alerted',
  'offer_seen': 'Unit saw the alert',
  'offer_accepted': 'Unit accepted',
  'offer_declined': 'Unit declined',
  'offer_expired': 'Offer expired',
  'offer_withdrawn': 'Offer withdrawn',
  'unit_en_route': 'Unit on the way',
  'unit_arrived': 'Unit arrived',
  'transport_started': 'Transport started',
  'transport_arrived': 'Arrived at facility',
  'extra_resources_requested': 'Extra units requested',
  'admin_assigned': 'Dispatcher assigned a unit',
  'admin_revealed_contact': 'Contact revealed',
  'admin_message_sent': 'Message sent',
  'checkin_sent': 'Check-in sent to caller',
  'checkin_replied': 'Caller answered a check-in',
  'attention_raised': 'Flagged for attention',
  'responder_sos': 'Responder SOS',
  'incident_cancelled': 'Caller cancelled',
  'incident_closed': 'Incident closed',
};

String eventWords(String type) => _eventWords[type] ?? type.replaceAll('_', ' ');

class OpsIncidentPanel extends StatefulWidget {
  const OpsIncidentPanel({
    super.key,
    required this.repo,
    required this.incidentId,
    required this.responders,
    required this.offers,
    required this.readOnly,
    this.initialTab = OpsPanelTab.overview,
    this.messageFocusToken = 0,
    this.onClose,
  });

  final OpsRepository repo;
  final String incidentId;
  final List<ResponderRecord> responders;
  final List<Offer> offers;
  final bool readOnly;
  final OpsPanelTab initialTab;
  final int messageFocusToken;
  final VoidCallback? onClose;

  @override
  State<OpsIncidentPanel> createState() => _OpsIncidentPanelState();
}

class _OpsIncidentPanelState extends State<OpsIncidentPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _message = TextEditingController();
  final _messageFocus = FocusNode();

  late Stream<IncidentRecord?> _incident;
  late Stream<List<OpsEvent>> _events;
  late Stream<List<OpsMessage>> _messages;
  late Stream<List<OpsCheckin>> _checkins;

  String? _street;
  String? _streetFor;
  ({String firstName, String phone})? _contact;
  bool _revealBusy = false;
  bool _sendBusy = false;

  static int _indexOf(OpsPanelTab t) => switch (t) {
    OpsPanelTab.overview => 0,
    OpsPanelTab.candidates => 1,
    OpsPanelTab.timeline => 2,
    OpsPanelTab.messages => 3,
    OpsPanelTab.checkin => 4,
    OpsPanelTab.actions => 5,
  };

  @override
  void initState() {
    super.initState();
    final count = widget.readOnly ? 5 : 6;
    _tabs = TabController(length: count, initialIndex: _indexOf(widget.initialTab).clamp(0, count - 1), vsync: this);
    _bind(widget.incidentId);
    if (widget.initialTab == OpsPanelTab.messages) WidgetsBinding.instance.addPostFrameCallback((_) => _focusMessage());
  }

  void _bind(String id) {
    _incident = widget.repo.watchIncident(id);
    _events = widget.repo.watchEvents(id);
    _messages = widget.repo.watchMessages(id);
    _checkins = widget.repo.watchCheckins(id);
  }

  @override
  void didUpdateWidget(covariant OpsIncidentPanel old) {
    super.didUpdateWidget(old);
    if (old.incidentId != widget.incidentId) {
      _bind(widget.incidentId);
      _street = null;
      _streetFor = null;
      _contact = null;
      _message.clear();
      _tabs.index = _indexOf(widget.initialTab).clamp(0, _tabs.length - 1);
    }
    if (old.messageFocusToken != widget.messageFocusToken) {
      _tabs.index = _indexOf(OpsPanelTab.messages).clamp(0, _tabs.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusMessage());
    }
  }

  void _focusMessage() {
    if (!mounted || widget.readOnly) return;
    _tabs.animateTo(_indexOf(OpsPanelTab.messages).clamp(0, _tabs.length - 1));
    _messageFocus.requestFocus();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _message.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _loadStreet(IncidentRecord inc) async {
    if (_streetFor == inc.id || inc.latitude == null || inc.longitude == null) return;
    _streetFor = inc.id;
    final s = await widget.repo.streetLabel(inc.latitude!, inc.longitude!);
    if (mounted && _streetFor == inc.id) setState(() => _street = s);
  }

  Future<void> _reveal(IncidentRecord inc) async {
    setState(() => _revealBusy = true);
    try {
      final c = await widget.repo.revealContact(inc.id);
      if (!mounted) return;
      setState(() => _contact = c);
    } catch (e) {
      _toast('Could not reveal: $e');
    } finally {
      if (mounted) setState(() => _revealBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IncidentRecord?>(
      stream: _incident,
      builder: (context, snap) {
        final inc = snap.data;
        return Container(
          decoration: OT.panelDecoration(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (snap.hasError)
              Padding(padding: const EdgeInsets.all(OT.pad), child: ErrorState(message: 'Could not load this incident: ${snap.error}', onRetry: () => setState(() => _bind(widget.incidentId))))
            else if (inc == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              _header(inc),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: OT.text,
                unselectedLabelColor: OT.muted,
                indicatorColor: OT.accent,
                dividerColor: OT.line,
                tabs: [
                  const Tab(text: 'Overview'),
                  const Tab(text: 'Candidates'),
                  const Tab(text: 'Timeline'),
                  const Tab(text: 'Messages'),
                  const Tab(text: 'Caller check-in'),
                  if (!widget.readOnly) const Tab(text: 'Actions'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _overview(inc),
                    _candidates(inc),
                    _timeline(inc),
                    _messagesTab(inc),
                    _checkinTab(inc),
                    if (!widget.readOnly) _actions(inc),
                  ],
                ),
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _header(IncidentRecord inc) {
    final closed = !inc.isOpen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(OT.pad, 12, 8, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              PriorityTag(inc.priority),
              OpsTag(inc.category),
              if (closed) OpsTag(inc.status, bg: OT.raised, fg: OT.soft),
              if (inc.needsAttention) OpsTag('Needs attention', bg: const Color(0xFF3A2020), fg: const Color(0xFFFFB8B0), border: const Color(0xFF7A3A3A)),
            ]),
            const SizedBox(height: 6),
            Text(
              inc.subtype == null ? inc.category : inc.subtype!.replaceAll('_', ' '),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: OT.text),
            ),
            Text('${inc.id}${widget.readOnly ? ' · read-only' : ''}', style: const TextStyle(fontSize: 11.5, color: OT.muted)),
          ]),
        ),
        if (widget.onClose != null) IconButton(tooltip: 'Close panel (Esc)', onPressed: widget.onClose, icon: const Icon(Icons.close)),
      ]),
    );
  }

  // ----------------------------------------------------------------- Overview
  Widget _overview(IncidentRecord inc) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStreet(inc));
    final required = requiredRolesFor(category: inc.category, subtype: inc.subtype, answers: inc.answers);
    final held = [for (final u in inc.units) if (kHeldStatuses.contains(u.status)) u];
    final offered = [for (final u in inc.units) if (u.status == 'offered') u];
    final hint = _contact;
    final shownName = hint == null ? '' : hint.firstName;
    final shownPhone = hint == null ? '' : maskPhone(hint.phone);
    final m = inc.metrics;
    return ListView(padding: const EdgeInsets.all(OT.pad), children: [
      _kv('Street', _street == null ? (inc.latitude == null ? 'No location' : 'Locating…') : (_street!.isEmpty ? 'Street name unavailable' : _street!)),
      if (inc.landmark.isNotEmpty) _kv('Landmark', inc.landmark),
      _kv('Location accuracy', accuracyWords(inc.locationAccuracyM) ?? 'Not reported'),
      _kv('People', inc.peopleCount == 1 ? '1 person' : '${inc.peopleCount} people'),
      _kv('Danger signs', inc.dangerFlags.isEmpty ? 'None reported' : inc.dangerFlags.join(' · ')),
      _kv('Elapsed', _elapsed(inc.createdAt)),
      const SizedBox(height: 12),
      const _SubTitle('Roles needed'),
      if (required.isEmpty)
        Text(inc.subtype != null && kSupportOnlySubtypes.contains(inc.subtype) ? 'Support only: no responder is sent for this kind of alert.' : 'Any responder.', style: const TextStyle(color: OT.muted, fontSize: 13))
      else
        for (final role in required)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: Text(roleLabel(role), style: const TextStyle(fontSize: 13, color: OT.soft))),
              ..._holdersFor(role, held, offered),
            ]),
          ),
      const SizedBox(height: 12),
      const _SubTitle('Caller contact'),
      Row(children: [
        Expanded(
          child: Text(
            hint == null ? '••• ••• •••' : '${shownName.isEmpty ? 'Caller' : shownName} · $shownPhone',
            style: const TextStyle(fontSize: 13.5, color: OT.soft),
          ),
        ),
        OutlinedButton(
          onPressed: widget.readOnly || _revealBusy ? null : () => _reveal(inc),
          child: _revealBusy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(hint == null ? 'Reveal contact' : 'Show number'),
        ),
      ]),
      if (hint != null && hint.phone.isNotEmpty) ...[
        const SizedBox(height: 6),
        SelectableText(hint.phone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: OT.text)),
        const Text('Revealing is written to the incident timeline.', style: TextStyle(fontSize: 11, color: OT.muted)),
      ],
      if (inc.description.isNotEmpty) ...[
        const SizedBox(height: 12),
        const _SubTitle('Caller description'),
        Text(inc.description, style: const TextStyle(fontSize: 13, color: OT.soft, height: 1.4)),
      ],
      if (inc.priorityReasons.isNotEmpty) ...[
        const SizedBox(height: 12),
        const _SubTitle('Why this priority'),
        for (final r in inc.priorityReasons) Text('• $r', style: const TextStyle(fontSize: 12.5, color: OT.muted)),
      ],
      if (!inc.isOpen) ...[
        const SizedBox(height: 12),
        const _SubTitle('Outcome'),
        _kv('Closed', inc.resolvedAt != null ? _stamp(inc.resolvedAt!) : inc.cancelledAt != null ? _stamp(inc.cancelledAt!) : inc.status),
        if (inc.callerFeedbackSafe != null) _kv('Caller says safe', inc.callerFeedbackSafe! ? 'Yes' : 'No'),
        if (inc.callerRating != null) _kv('Caller rating', '${inc.callerRating} of 5'),
        if (m != null) _kv('Time to first accept', m.secondsToFirstAccept == null ? 'Not recorded' : _seconds(m.secondsToFirstAccept!)),
        if (m != null) _kv('Time to first arrival', m.secondsToFirstArrival == null ? 'Not recorded' : _seconds(m.secondsToFirstArrival!)),
      ],
    ]);
  }

  List<Widget> _holdersFor(String role, List<DispatchUnit> held, List<DispatchUnit> offered) {
    final h = [for (final u in held) if (u.role == role || u.role == 'any_responder') u];
    if (h.isNotEmpty) return [for (final u in h.take(2)) OpsTag('${u.name} · ${u.statusLabel}', bg: const Color(0xFF15352F), fg: const Color(0xFF8FE8D8))];
    final o = [for (final u in offered) if (u.role == role || u.role == 'any_responder') u];
    if (o.isNotEmpty) return [OpsTag('${o.length} alerted', bg: OT.raised, fg: OT.muted)];
    return [const OpsTag('Not yet', bg: Color(0xFF2A2020), fg: Color(0xFFFFB8B0))];
  }

  // ----------------------------------------------------------------- Candidates
  Widget _candidates(IncidentRecord inc) {
    if (!inc.isOpen) return const EmptyState(icon: Icons.lock_outline, title: 'This incident is closed', message: 'Candidates are only listed while an incident is open.');
    final required = requiredRolesFor(category: inc.category, subtype: inc.subtype, answers: inc.answers);
    final asked = {for (final o in widget.offers) o.responderId};
    final filled = filledRoleCount(required, inc.units);
    final unfilled = <String>[];
    if (required.isEmpty) {
      if (filled == 0) unfilled.add('any_responder');
    } else {
      final heldRoles = {for (final u in inc.units) if (kHeldStatuses.contains(u.status)) u.role};
      for (final r in required) {
        if (!heldRoles.contains(r) && !heldRoles.contains('any_responder')) unfilled.add(r);
      }
    }
    if (unfilled.isEmpty) return const EmptyState(icon: Icons.check_circle_outline, title: 'Every role is filled', message: 'No manual assignment is needed.');
    return ListView(padding: const EdgeInsets.all(OT.pad), children: [
      for (final role in unfilled) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Text(roleLabel(role), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OT.text))),
            const OpsTag('Unfilled', bg: Color(0xFF3A2020), fg: Color(0xFFFFB8B0)),
          ]),
        ),
        ...(() {
          final list = rankCandidates(lat: inc.latitude, lng: inc.longitude, role: role == 'any_responder' ? null : role, responders: widget.responders, alreadyAsked: asked, limit: 5);
          if (list.isEmpty) {
            return [const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('No verified unit with that ability is available and close by.', style: TextStyle(fontSize: 12.5, color: OT.muted)))];
          }
          return [
            for (final c in list)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: OT.raised, borderRadius: BorderRadius.circular(10), border: Border.all(color: OT.line)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OT.text)),
                      const SizedBox(height: 2),
                      Text([
                        c.responder.organizationType,
                        if (c.distanceKm != null) '${c.distanceKm!.toStringAsFixed(1)} km',
                        if (c.etaMinutes != null) '~${c.etaMinutes} min',
                        _reliability(c.responder.id),
                      ].join(' · '), style: const TextStyle(fontSize: 11.5, color: OT.muted)),
                      const SizedBox(height: 5),
                      Wrap(spacing: 4, runSpacing: 4, children: [for (final cap in c.responder.effectiveCapabilities) OpsTag(roleLabel(cap))]),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if (!widget.readOnly) FilledButton(onPressed: () => _assign(inc, c, role), child: const Text('Assign')),
                ]),
              ),
          ];
        })(),
        const SizedBox(height: 8),
      ],
    ]);
  }

  String _reliability(String responderId) {
    final s = unitStats(widget.offers, responderId);
    if (s.offers == 0) return 'no recent offers';
    return 'accepts ${(s.acceptanceRate! * 100).round()}% of ${s.offers}';
  }

  Future<void> _assign(IncidentRecord inc, Candidate c, String role) async {
    final reason = TextEditingController();
    var confirmed = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Assign ${c.name}?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${roleLabel(role)}${c.distanceKm == null ? '' : ' · ${c.distanceKm!.toStringAsFixed(1)} km away'}', style: const TextStyle(color: OT.muted)),
            const SizedBox(height: 10),
            TextField(controller: reason, maxLength: 140, decoration: const InputDecoration(labelText: 'Reason for the manual override', border: OutlineInputBorder())),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => set((() => confirmed = v == true)),
              title: const Text('I have checked this unit can take the job.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final err = assignReasonError(reason.text);
                if (err != null) {
                  ScaffoldMessenger.of(d).showSnackBar(SnackBar(content: Text(err)));
                  return;
                }
                if (!confirmed) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('Confirm the check first.')));
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    try {
      await widget.repo.assign(inc.id, c.responder.id, role: role == 'any_responder' ? null : role, reason: reason.text.trim());
      _toast('Offer sent to ${c.name}.');
    } catch (e) {
      _toast('Could not assign: $e');
    }
  }

  // ----------------------------------------------------------------- Timeline
  Widget _timeline(IncidentRecord inc) => StreamBuilder<List<OpsEvent>>(
    stream: _events,
    builder: (context, s) {
      if (s.hasError) return ErrorState(message: 'Could not load the timeline.', onRetry: () => setState(() => _bind(widget.incidentId)));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final list = [...(s.data ?? const <OpsEvent>[])]..sort((a, b) => (a.at ?? DateTime(2000)).compareTo(b.at ?? DateTime(2000)));
      if (list.isEmpty) return const EmptyState(icon: Icons.timeline, title: 'No events yet', message: 'The first event is written when the alert is created.');
      final created = inc.createdAt;
      return ListView.builder(
        padding: const EdgeInsets.all(OT.pad),
        itemCount: list.length,
        itemBuilder: (_, k) {
          final e = list[k];
          final rel = (e.at != null && created != null && !e.at!.isBefore(created)) ? '+${mmss(e.at!.difference(created))}' : '';
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 54, child: Text(rel, style: const TextStyle(fontSize: 11.5, color: OT.muted, fontFeatures: [FontFeature.tabularFigures()]))),
              Column(children: [
                Container(width: 9, height: 9, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: k == 0 ? OT.accent : OT.muted, shape: BoxShape.circle)),
                if (k != list.length - 1) Expanded(child: Container(width: 1, color: OT.line)),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(eventWords(e.type), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OT.text)),
                    if (e.data.isNotEmpty) Text(e.data.entries.map((x) => '${x.key}: ${x.value}').join(' · '), style: const TextStyle(fontSize: 11.5, color: OT.muted)),
                    if (e.actorRole.isNotEmpty) Text('by ${e.actorRole}', style: const TextStyle(fontSize: 11, color: OT.muted)),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
    },
  );

  // ----------------------------------------------------------------- Messages
  Widget _messagesTab(IncidentRecord inc) => Column(children: [
    const Padding(
      padding: EdgeInsets.fromLTRB(OT.pad, 10, OT.pad, 4),
      child: Align(alignment: Alignment.centerLeft, child: Text('Responders only · the caller cannot see this thread', style: TextStyle(fontSize: 11.5, color: OT.muted))),
    ),
    Expanded(
      child: StreamBuilder<List<OpsMessage>>(
        stream: _messages,
        builder: (context, s) {
          if (s.hasError) return ErrorState(message: 'Could not load messages.', onRetry: () => setState(() => _bind(widget.incidentId)));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final list = s.data ?? const <OpsMessage>[];
          if (list.isEmpty) return const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', message: 'Use a quick message or type below.');
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(OT.pad),
            itemCount: list.length,
            itemBuilder: (_, k) {
              final m = list[list.length - 1 - k];
              final mine = m.senderRole == 'admin';
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(color: mine ? const Color(0xFF153A36) : OT.raised, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.text, style: const TextStyle(fontSize: 13, color: OT.text)),
                    const SizedBox(height: 2),
                    Text(mine ? 'Dispatch · ${_clock(m.at)}' : 'Unit · ${_clock(m.at)}', style: const TextStyle(fontSize: 10, color: OT.muted)),
                  ]),
                ),
              );
            },
          );
        },
      ),
    ),
    if (!widget.readOnly && inc.isOpen) ...[
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: OT.pad), children: [
          for (final q in const ['On our way', 'Send your location', 'Stand by'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(label: Text(q, style: const TextStyle(fontSize: 12)), onPressed: _sendBusy ? null : () => _send(inc, q)),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(OT.pad),
        child: Row(children: [
          Expanded(child: TextField(controller: _message, focusNode: _messageFocus, maxLength: 500, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'Message the units on this job', border: OutlineInputBorder(), counterText: ''))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _sendBusy ? null : () => _send(inc, _message.text), icon: const Icon(Icons.send)),
        ]),
      ),
    ] else if (!inc.isOpen)
      const Padding(padding: EdgeInsets.all(OT.pad), child: Text('This incident is closed. The thread is read-only.', style: TextStyle(fontSize: 12, color: OT.muted))),
  ]);

  Future<void> _send(IncidentRecord inc, String text) async {
    final t = text.trim();
    if (t.isEmpty || _sendBusy) return;
    setState(() => _sendBusy = true);
    try {
      await widget.repo.sendMessage(inc.id, t);
      _message.clear();
    } catch (e) {
      _toast('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sendBusy = false);
    }
  }

  // ----------------------------------------------------------------- Caller check-in
  Widget _checkinTab(IncidentRecord inc) => StreamBuilder<List<OpsCheckin>>(
    stream: _checkins,
    builder: (context, s) {
      if (s.hasError) return ErrorState(message: 'Could not load check-ins.', onRetry: () => setState(() => _bind(widget.incidentId)));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final list = s.data ?? const <OpsCheckin>[];
      final latest = <String, OpsCheckin>{};
      for (final c in list) {
        latest.putIfAbsent(c.template, () => c);
      }
      return ListView(padding: const EdgeInsets.all(OT.pad), children: [
        if (!inc.isOpen)
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('The incident is closed: check-ins cannot be sent.', style: TextStyle(fontSize: 12, color: OT.muted))),
        for (final e in kCheckinTemplates.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: OT.raised, borderRadius: BorderRadius.circular(10), border: Border.all(color: OT.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value, style: const TextStyle(fontSize: 13, color: OT.text)),
              const SizedBox(height: 6),
              Row(children: [
                if (latest[e.key] != null)
                  OpsTag(
                    latest[e.key]!.reply == null
                        ? 'Sent ${_ago(latest[e.key]!.sentAt)} · waiting'
                        : 'Answered ${_replyWord(latest[e.key]!.reply!)} ${_ago(latest[e.key]!.repliedAt)}',
                    bg: latest[e.key]!.reply == null ? OT.panel : const Color(0xFF15352F),
                    fg: latest[e.key]!.reply == null ? OT.muted : const Color(0xFF8FE8D8),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: widget.readOnly || !inc.isOpen || _sendBusy ? null : () => _sendCheckin(inc, e.key),
                  child: Text(latest[e.key] == null ? 'Send' : 'Send again'),
                ),
              ]),
            ]),
          ),
      ]);
    },
  );

  Future<void> _sendCheckin(IncidentRecord inc, String template) async {
    setState(() => _sendBusy = true);
    try {
      await widget.repo.sendCheckin(inc.id, template);
      _toast('Check-in sent to the caller.');
    } catch (e) {
      _toast('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sendBusy = false);
    }
  }

  // ----------------------------------------------------------------- Actions
  Widget _actions(IncidentRecord inc) => ListView(padding: const EdgeInsets.all(OT.pad), children: [
    if (!inc.isOpen) ...[
      const EmptyState(icon: Icons.check_circle_outline, title: 'Closed', message: 'No action is possible on a closed incident.'),
      const SizedBox(height: 10),
    ],
    OpsPanel(
      title: 'Request more units',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Records the request on the timeline and flags the incident. The planning engine is not changed.', style: TextStyle(fontSize: 12, color: OT.muted)),
        const SizedBox(height: 10),
        _MoreUnitsButton(repo: widget.repo, incident: inc, enabled: inc.isOpen, toast: _toast),
      ]),
    ),
    const SizedBox(height: 10),
    OpsPanel(
      title: 'Close incident',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Closing asks for the outcome and is confirmed. The caller and the units are told.', style: TextStyle(fontSize: 12, color: OT.muted)),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: inc.isOpen ? () => _close(inc) : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Close incident'),
        ),
      ]),
    ),
  ]);

  Future<void> _close(IncidentRecord inc) async {
    final outcome = TextEditingController();
    var confirmed = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Close this incident?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: outcome, maxLength: 280, maxLines: 2, decoration: const InputDecoration(labelText: 'Outcome (what happened)', border: OutlineInputBorder())),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => set((() => confirmed = v == true)),
              title: const Text('I have checked this incident can be closed.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (outcome.text.trim().length < 3) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('Write the outcome (at least 3 characters).')));
                  return;
                }
                if (!confirmed) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('Confirm the check first.')));
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('Close incident'),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    try {
      await widget.repo.close(inc.id, outcome.text.trim());
      _toast('Incident closed.');
    } catch (e) {
      _toast('Could not close: $e');
    }
  }
}

class _MoreUnitsButton extends StatefulWidget {
  const _MoreUnitsButton({required this.repo, required this.incident, required this.enabled, required this.toast});
  final OpsRepository repo;
  final IncidentRecord incident;
  final bool enabled;
  final void Function(String) toast;

  @override
  State<_MoreUnitsButton> createState() => _MoreUnitsButtonState();
}

class _MoreUnitsButtonState extends State<_MoreUnitsButton> {
  String _role = 'medical_transport';
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: DropdownButtonFormField<String>(
        initialValue: _role,
        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        items: [
          for (final r in kRoleLabels.keys)
            if (r != 'any_responder') DropdownMenuItem(value: r, child: Text(roleLabel(r), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _role = v ?? _role),
      ),
    ),
    const SizedBox(width: 8),
    FilledButton(
      onPressed: !widget.enabled || _busy ? null : _request,
      child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Request'),
    ),
  ]);

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final candidates = await widget.repo.requestMoreUnits(widget.incident.id, _role, 'Dispatcher request');
      widget.toast(candidates.isEmpty ? 'Recorded. No available unit with that ability was found.' : 'Recorded. ${candidates.length} candidate unit(s) found.');
    } catch (e) {
      widget.toast('Could not request: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: OT.muted)),
  );
}

Widget _kv(String k, String v) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 118, child: Text(k, style: const TextStyle(fontSize: 12, color: OT.muted))),
    Expanded(child: Text(v, style: const TextStyle(fontSize: 13, color: OT.soft))),
  ]),
);

String _replyWord(String r) => switch (r) { 'yes' => 'Yes', 'no' => 'No', _ => 'Not sure' };

String _seconds(int s) => s < 60 ? '$s s' : '${s ~/ 60} m ${s % 60} s';

String _elapsed(DateTime? created) {
  if (created == null) return 'Unknown';
  return mmss(DateTime.now().difference(created));
}

String _stamp(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${_clock(t)}';

String _clock(DateTime? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}
