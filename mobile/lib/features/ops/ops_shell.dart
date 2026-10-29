// The dispatcher and administrator console. One shell, two roles: the navigation and every write is
// restricted by the role, and the same split is enforced by Firestore rules and the callables.
// Wide screens get three columns (queue, map, incident/units); narrow screens get Queue/Map/Units tabs.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/dispatch_models.dart';
import 'ops_analytics.dart';
import 'ops_approvals.dart';
import 'ops_audit.dart';
import 'ops_directory.dart';
import 'ops_incident_panel.dart';
import 'ops_incidents_page.dart';
import 'ops_logic.dart';
import 'ops_map.dart';
import 'ops_notes.dart';
import 'ops_notifications.dart';
import 'ops_queue.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_units_board.dart';
import 'ops_widgets.dart';

enum _Kpi { all, attention, today, sos }

class OpsShell extends StatefulWidget {
  const OpsShell({super.key, required this.isAdmin});
  final bool isAdmin;

  @override
  State<OpsShell> createState() => _OpsShellState();
}

class _OpsShellState extends State<OpsShell> {
  final _repo = OpsRepository();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  late final Stream<List<IncidentRecord>> _incidents = _repo.watchIncidents();
  late final Stream<List<Offer>> _offers = _repo.watchOffers();
  late final Stream<List<ResponderRecord>> _responders = _repo.watchResponders();
  late final Stream<List<SosAlert>> _sos = _repo.watchOpenSos();
  late final Stream<List<OpsNote>> _notes = _repo.watchNotes();

  OpsSection _section = OpsSection.controlRoom;
  String? _incidentId;
  OpsPanelTab _panelTab = OpsPanelTab.overview;
  int _messageToken = 0;
  int _cursor = 0;
  _Kpi _kpi = _Kpi.all;
  String? _unitsFilter;
  bool _trayOpen = false;
  bool _helpOpen = false;
  bool _muted = false;
  bool _bellPulse = false;
  Timer? _bellTimer;

  final Set<String> _announced = {};
  bool _primed = false;
  List<IncidentRecord> _incidentsCache = const [];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bellTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ shortcuts
  static String? _keyName(KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) return 'Enter';
    if (e.logicalKey == LogicalKeyboardKey.escape) return 'Escape';
    if (e.logicalKey == LogicalKeyboardKey.slash) return '/';
    final c = e.character;
    if (c == null || c.isEmpty) return null;
    return c;
  }

  bool get _typing {
    final c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    return c.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final name = _keyName(e);
    if (name == null) return false;
    // While the help sheet is open the dialog owns the keyboard (Escape closes it).
    if (_helpOpen) return false;
    final typed = _typing;
    final s = shortcutFor(name, typing: typed);
    if (s == null) return false;
    if (!mounted) return false;
    switch (s) {
      case OpsShortcut.help:
        _showHelp();
        return true;
      case OpsShortcut.closePanel:
        if (_trayOpen) {
          setState(() => _trayOpen = false);
          return true;
        }
        if (_incidentId != null) {
          setState(() {
            _incidentId = null;
            _panelTab = OpsPanelTab.overview;
          });
          return true;
        }
        return false;
      case OpsShortcut.search:
        _searchFocus.requestFocus();
        return true;
      case OpsShortcut.nextIncident:
      case OpsShortcut.previousIncident:
      case OpsShortcut.openIncident:
      case OpsShortcut.candidates:
      case OpsShortcut.message:
        // These act on the queue, which only the control room shows.
        if (_section != OpsSection.controlRoom) return false;
        return _queueShortcut(s);
    }
  }

  bool _queueShortcut(OpsShortcut s) {
    final rows = _queue(_incidentsCache);
    if (s == OpsShortcut.nextIncident || s == OpsShortcut.previousIncident) {
      _moveCursor(rows, s == OpsShortcut.nextIncident ? 1 : -1);
      return true;
    }
    if (rows.isEmpty && _incidentId == null) return false;
    setState(() {
      if (_incidentId == null) {
        _cursor = _cursor.clamp(0, rows.length - 1);
        _incidentId = rows[_cursor].incident.id;
        _panelTab = OpsPanelTab.overview;
      }
      switch (s) {
        case OpsShortcut.openIncident:
          _panelTab = OpsPanelTab.overview;
          break;
        case OpsShortcut.candidates:
          _panelTab = OpsPanelTab.candidates;
          break;
        case OpsShortcut.message:
          _panelTab = OpsPanelTab.messages;
          _messageToken++;
          break;
        default:
          break;
      }
    });
    return true;
  }

  /// J/K move the cursor through the visible queue and select that row (row and pin stay in step).
  void _moveCursor(List<QueueRow> rows, int delta) {
    if (rows.isEmpty) return;
    setState(() {
      if (_incidentId == null) {
        _cursor = delta > 0 ? 0 : rows.length - 1;
      } else {
        final current = rows.indexWhere((r) => r.incident.id == _incidentId);
        _cursor = (current < 0 ? 0 : current + delta).clamp(0, rows.length - 1);
      }
      _incidentId = rows[_cursor].incident.id;
      _panelTab = OpsPanelTab.overview;
    });
  }

  Future<void> _showHelp() async {
    setState(() => _helpOpen = true);
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OT.panel,
        title: const Text('Keyboard shortcuts', style: TextStyle(color: OT.text, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final line in kShortcutHelp.values) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(line, style: const TextStyle(color: OT.soft))),
          const SizedBox(height: 10),
          const Text('Shortcuts do not fire while a text field has focus.', style: TextStyle(fontSize: 12, color: OT.muted)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ),
    );
    if (mounted) setState(() => _helpOpen = false);
  }

  // ------------------------------------------------------------------ sound
  /// A new SOS or High priority alert rings once: never on the first snapshot, never while muted.
  void _maybeSound(List<OpsNotice> notices) {
    final ids = {for (final n in notices) if (n.isUrgent) n.id};
    if (!_primed) {
      _announced.addAll(ids);
      _primed = true;
      return;
    }
    var fresh = false;
    for (final id in ids) {
      if (_announced.add(id)) fresh = true;
    }
    if (!fresh) return;
    if (!_muted) SystemSound.play(SystemSoundType.alert);
    _bellPulse = true;
    _bellTimer?.cancel();
    _bellTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _bellPulse = false);
    });
  }

  // ------------------------------------------------------------------ data
  List<QueueRow> _queue(List<IncidentRecord> incidents) {
    var list = incidents;
    if (_kpi == _Kpi.attention) list = [for (final i in list) if (i.needsAttention) i];
    if (_kpi == _Kpi.today) list = [for (final i in list) if (_today(i.createdAt)) i];
    if (_kpi == _Kpi.sos) list = [for (final i in list) if (i.attentionReason == 'responder_sos') i];
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = [
        for (final i in list)
          if (i.category.toLowerCase().contains(q) ||
              (i.subtype ?? '').replaceAll('_', ' ').contains(q) ||
              i.landmark.toLowerCase().contains(q) ||
              i.id.toLowerCase().contains(q))
            i,
      ];
    }
    final rows = buildQueue(list);
    if (_cursor >= rows.length) _cursor = rows.isEmpty ? 0 : rows.length - 1;
    return rows;
  }

  String? get _filterLabel => switch (_kpi) {
    _Kpi.all => null,
    _Kpi.attention => 'Needs attention',
    _Kpi.today => 'Created today',
    _Kpi.sos => 'Responder SOS',
  };

  IncidentRecord? _find(List<IncidentRecord> incidents) {
    for (final i in incidents) {
      if (i.id == _incidentId) return i;
    }
    return null;
  }

  static bool _today(DateTime? t) {
    if (t == null) return false;
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OT.bg,
      body: StreamBuilder<List<IncidentRecord>>(
        stream: _incidents,
        builder: (context, iSnap) {
          if (iSnap.hasError) return _page(ErrorState(message: 'Could not load incidents: ${iSnap.error}', onRetry: () => setState(() {})));
          if (!iSnap.hasData) return _page(const OpsSkeleton());
          final incidents = iSnap.data!;
          return StreamBuilder<List<ResponderRecord>>(
            stream: _responders,
            builder: (context, rSnap) => StreamBuilder<List<Offer>>(
              stream: _offers,
              builder: (context, oSnap) => StreamBuilder<List<SosAlert>>(
                stream: _sos,
                builder: (context, sSnap) => StreamBuilder<List<OpsNote>>(
                  stream: _notes,
                  builder: (context, nSnap) {
                    final responders = rSnap.data ?? const <ResponderRecord>[];
                    final offers = oSnap.data ?? const <Offer>[];
                    final sos = sSnap.data ?? const <SosAlert>[];
                    final notes = nSnap.data ?? const <OpsNote>[];
                    _incidentsCache = incidents;
                    final notices = buildNotices(incidents: incidents, sos: sos);
                    _maybeSound(notices);
                    return Stack(children: [
                      Column(children: [
                        _topBar(notices.length),
                        if (rSnap.hasError || oSnap.hasError)
                          _banner('Some unit data could not be loaded. Showing what is available.'),
                        Expanded(child: _shellBody(incidents, responders, offers, sos, notes)),
                      ]),
                      if (_trayOpen) ...[
                        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _trayOpen = false), child: const SizedBox())),
                        Positioned(
                          top: 62,
                          right: 18,
                          child: Material(
                            color: Colors.transparent,
                            child: NoticeTray(
                              notices: notices,
                              muted: _muted,
                              onToggleMute: () => setState(() => _muted = !_muted),
                              onOpenIncident: (id) {
                                setState(() {
                                  _trayOpen = false;
                                  _section = OpsSection.controlRoom;
                                  _incidentId = id;
                                  _panelTab = OpsPanelTab.overview;
                                });
                              },
                              onResolveSos: _resolveSos,
                              onClose: () => setState(() => _trayOpen = false),
                            ),
                          ),
                        ),
                      ],
                    ]);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _page(Widget child) => SafeArea(child: child);

  Widget _banner(String text) => Container(
    width: double.infinity,
    color: const Color(0xFF33280F),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFFFCF7A))),
  );

  // ------------------------------------------------------------------ top bar
  Widget _topBar(int noticeCount) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(color: OT.panel, border: Border(bottom: BorderSide(color: OT.line))),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: OT.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(7), border: Border.all(color: OT.accent.withValues(alpha: 0.5))),
          child: const Icon(Icons.emergency_outlined, size: 16, color: OT.accent),
        ),
        const SizedBox(width: 10),
        Text(sectionTitle(_section), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: OT.text)),
        const SizedBox(width: 10),
        OpsTag(widget.isAdmin ? 'ADMINISTRATOR' : 'DISPATCHER', bg: OT.raised, fg: OT.soft),
        const SizedBox(width: 18),
        Expanded(
          child: SizedBox(
            height: 34,
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: const TextStyle(fontSize: 13, color: OT.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: OT.raised,
                hintText: 'Search category, place or incident id  ( / )',
                hintStyle: const TextStyle(fontSize: 12.5, color: OT.muted),
                prefixIcon: const Icon(Icons.search, size: 17, color: OT.muted),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close, size: 15), onPressed: () => _search.clear()),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: _muted ? 'Sound muted' : 'Sound on',
          onPressed: () => setState(() => _muted = !_muted),
          icon: Icon(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 19, color: _muted ? OT.muted : OT.soft),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: _bellPulse ? OT.alert.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Badge.count(
            count: noticeCount,
            isLabelVisible: noticeCount > 0,
            backgroundColor: OT.alert,
            child: IconButton(
              tooltip: 'Notifications',
              onPressed: () => setState(() => _trayOpen = !_trayOpen),
              icon: Icon(noticeCount == 0 ? Icons.notifications_none : Icons.notifications_active_outlined, size: 20, color: _bellPulse ? OT.text : OT.soft),
            ),
          ),
        ),
        IconButton(tooltip: 'Keyboard shortcuts', onPressed: _showHelp, icon: const Icon(Icons.keyboard_outlined, size: 19, color: OT.soft)),
        const SizedBox(width: 4),
        _profileMenu(),
      ]),
    );
  }

  Widget _profileMenu() {
    final user = FirebaseAuth.instance.currentUser;
    return PopupMenuButton<String>(
      tooltip: 'Profile',
      onSelected: (v) {
        if (v == 'signOut') _confirmSignOut();
      },
      itemBuilder: (c) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.email ?? 'Signed in', style: const TextStyle(fontSize: 12, color: OT.soft)),
            Text(widget.isAdmin ? 'System administrator' : 'Dispatcher', style: const TextStyle(fontSize: 11, color: OT.muted)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'signOut', child: Text('Sign out')),
      ],
      child: const CircleAvatar(radius: 14, backgroundColor: OT.raised, child: Icon(Icons.person_outline, size: 16, color: OT.soft)),
    );
  }

  Future<void> _confirmSignOut() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OT.panel,
        title: const Text('Sign out?', style: TextStyle(color: OT.text)),
        content: const Text('You will stop receiving dispatch information on this device.', style: TextStyle(color: OT.soft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Stay signed in')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (go == true) await FirebaseAuth.instance.signOut();
  }

  Future<void> _resolveSos(SosAlert sos) async {
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OT.panel,
        title: Text('Resolve the SOS from ${sos.orgName}?', style: const TextStyle(color: OT.text)),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Say what happened. The note is kept on the SOS record.', style: TextStyle(fontSize: 12.5, color: OT.muted)),
            const SizedBox(height: 10),
            TextField(controller: note, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (note.text.trim().length < 3) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('Write what happened (at least 3 characters).')));
                return;
              }
              Navigator.pop(d, true);
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      await _repo.resolveSos(sos.id, note.text.trim());
      if (mounted) {
        setState(() => _trayOpen = false);
        _toast('SOS resolved.');
      }
    } catch (e) {
      _toast('Could not resolve the SOS: $e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ------------------------------------------------------------------ rail + sections
  Widget _shellBody(List<IncidentRecord> incidents, List<ResponderRecord> responders, List<Offer> offers, List<SosAlert> sos, List<OpsNote> notes) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    return Row(children: [
      _rail(),
      Expanded(child: _sectionBody(incidents, responders, offers, sos, notes, wide)),
    ]);
  }

  Widget _rail() {
    final sections = sectionsFor(isAdmin: widget.isAdmin);
    return Container(
      width: 76,
      decoration: const BoxDecoration(color: OT.panel, border: Border(right: BorderSide(color: OT.line))),
      child: Column(children: [
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final s in sections)
                _railItem(s, _section == s, () {
                  setState(() {
                    _section = s;
                    if (s != OpsSection.controlRoom && s != OpsSection.incidents) _incidentId = null;
                    if (s == OpsSection.units) _unitsFilter = null;
                  });
                }),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Icon(Icons.wifi_tethering, size: 16, color: OT.muted),
        ),
      ]),
    );
  }

  Widget _railItem(OpsSection s, bool selected, VoidCallback onTap) {
    final icon = switch (s) {
      OpsSection.controlRoom => Icons.space_dashboard_outlined,
      OpsSection.incidents => Icons.crisis_alert_outlined,
      OpsSection.units => Icons.local_shipping_outlined,
      OpsSection.passOnNotes => Icons.sticky_note_2_outlined,
      OpsSection.approvals => Icons.verified_user_outlined,
      OpsSection.directory => Icons.location_city_outlined,
      OpsSection.analytics => Icons.insights_outlined,
      OpsSection.audit => Icons.receipt_long_outlined,
    };
    return Tooltip(
      message: sectionTitle(s),
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? OT.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: selected ? OT.line : Colors.transparent),
          ),
          child: Column(children: [
            Icon(icon, size: 21, color: selected ? OT.accent : OT.muted),
            const SizedBox(height: 3),
            Text(
              sectionTitle(s),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 8.8, height: 1.15, fontWeight: FontWeight.w700, color: selected ? OT.soft : OT.muted),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionBody(List<IncidentRecord> incidents, List<ResponderRecord> responders, List<Offer> offers, List<SosAlert> sos, List<OpsNote> notes, bool wide) {
    switch (_section) {
      case OpsSection.controlRoom:
        return _controlRoom(incidents, responders, offers, sos, notes, wide);
      case OpsSection.incidents:
        return OpsIncidentsPage(
          repo: _repo,
          incidents: incidents,
          responders: responders,
          offers: offers,
          search: _search.text,
          selectedId: _incidentId,
          onOpen: (id) => setState(() {
            _incidentId = id;
            _panelTab = OpsPanelTab.overview;
          }),
          onClose: () => setState(() => _incidentId = null),
        );
      case OpsSection.units:
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(OT.pad, 12, OT.pad, 0),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('All'), selected: _unitsFilter == null, onSelected: (_) => setState(() => _unitsFilter = null)),
              for (final g in kUnitGroups)
                ChoiceChip(label: Text(g), selected: _unitsFilter == g, onSelected: (_) => setState(() => _unitsFilter = g)),
            ]),
          ),
          Expanded(child: OpsUnitsBoard(responders: responders, offers: offers, groupFilter: _unitsFilter)),
        ]);
      case OpsSection.passOnNotes:
        return OpsNotesPage(repo: _repo, notes: notes, isAdmin: widget.isAdmin);
      case OpsSection.approvals:
        return OpsApprovals(repo: _repo, responders: responders);
      case OpsSection.directory:
        return OpsDirectory(repo: _repo);
      case OpsSection.analytics:
        return OpsAnalytics(repo: _repo, incidents: incidents, offers: offers);
      case OpsSection.audit:
        return OpsAudit(
          repo: _repo,
          incidents: incidents,
          onOpen: (id) => setState(() {
            _section = OpsSection.incidents;
            _incidentId = id;
          }),
        );
    }
  }

  // ------------------------------------------------------------------ control room
  Widget _controlRoom(List<IncidentRecord> incidents, List<ResponderRecord> responders, List<Offer> offers, List<SosAlert> sos, List<OpsNote> notes, bool wide) {
    final rows = _queue(incidents);
    final sel = _find(incidents);
    final pinned = [for (final n in notes) if (n.pinned) n];
    final strip = _kpiStrip(incidents, responders, offers, sos, rows.length);
    final banner = pinned.isEmpty ? null : _passOnBanner(pinned, wide);
    if (!wide) {
      return Column(children: [
        strip,
        if (banner != null) banner,
        Expanded(
          child: sel != null
              ? Padding(padding: const EdgeInsets.all(10), child: _panel(sel, responders, offers))
              : DefaultTabController(
                  length: 3,
                  child: Column(children: [
                    Container(
                      color: OT.panel,
                      child: TabBar(
                        labelColor: OT.text,
                        unselectedLabelColor: OT.muted,
                        indicatorColor: OT.accent,
                        dividerColor: OT.line,
                        tabs: const [Tab(text: 'Queue'), Tab(text: 'Map'), Tab(text: 'Units')],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(children: [
                        OpsQueue(repo: _repo, rows: rows, selectedId: _incidentId, onSelect: _selectRow, filterLabel: _filterLabel, onClearFilter: () => setState(() => _kpi = _Kpi.all)),
                        Padding(padding: const EdgeInsets.all(10), child: _map(incidents, responders, sel)),
                        OpsUnitsBoard(responders: responders, offers: offers),
                      ]),
                    ),
                  ]),
                ),
        ),
      ]);
    }
    return Column(children: [
      strip,
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 318,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (banner != null) banner,
                Expanded(
                  child: Container(
                    decoration: OT.panelDecoration(),
                    child: OpsQueue(repo: _repo, rows: rows, selectedId: _incidentId, onSelect: _selectRow, filterLabel: _filterLabel, onClearFilter: () => setState(() => _kpi = _Kpi.all)),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: _map(incidents, responders, sel)),
            const SizedBox(width: 12),
            SizedBox(
              width: 392,
              child: sel != null
                  ? _panel(sel, responders, offers)
                  : Container(
                      decoration: OT.panelDecoration(),
                      child: OpsUnitsBoard(
                        responders: responders,
                        offers: offers,
                        compact: true,
                        onShowAll: () => setState(() => _section = OpsSection.units),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _selectRow(QueueRow row) {
    setState(() {
      _incidentId = row.incident.id;
      _panelTab = OpsPanelTab.overview;
    });
  }

  Widget _map(List<IncidentRecord> incidents, List<ResponderRecord> responders, IncidentRecord? sel) {
    return StreamBuilder<Map<String, TrackPoint>>(
      stream: sel == null ? const Stream<Map<String, TrackPoint>>.empty() : _repo.watchTracks(sel.id),
      builder: (context, tSnap) {
        final tracks = tSnap.data ?? const <String, TrackPoint>{};
        return ClipRRect(
          borderRadius: BorderRadius.circular(OT.radius),
          child: OpsMap(
            incidents: incidents,
            responders: responders,
            selectedId: _incidentId,
            onSelect: (id) => setState(() {
              _incidentId = id;
              _panelTab = OpsPanelTab.overview;
            }),
            tracks: tracks,
            residentUid: sel?.userId,
          ),
        );
      },
    );
  }

  Widget _panel(IncidentRecord inc, List<ResponderRecord> responders, List<Offer> offers) => OpsIncidentPanel(
    key: ValueKey('${inc.id}-${_panelTab.name}'),
    repo: _repo,
    incidentId: inc.id,
    responders: responders,
    offers: offers,
    readOnly: false,
    initialTab: _panelTab,
    messageFocusToken: _messageToken,
    onClose: () => setState(() {
      _incidentId = null;
      _panelTab = OpsPanelTab.overview;
    }),
  );

  Widget _kpiStrip(List<IncidentRecord> incidents, List<ResponderRecord> responders, List<Offer> offers, List<SosAlert> sos, int waiting) {
    final open = [for (final i in incidents) if (i.isOpen) i];
    final attention = [for (final i in open) if (i.needsAttention) i];
    final onDuty = [for (final r in responders) if (r.availabilityStatus != 'Offline' && r.verificationStatus == 'Verified') r];
    final onJob = [for (final r in responders) if (r.availabilityStatus == 'Busy') r];
    final gaps = <int>[];
    for (final o in offers) {
      if (!_today(o.respondedAt) || !kHeldStatuses.contains(o.status)) continue;
      if (o.createdAt == null || o.respondedAt == null) continue;
      final s = o.respondedAt!.difference(o.createdAt!).inSeconds;
      if (s >= 0) gaps.add(s);
    }
    final median = sampleStats(gaps).median;
    Widget tile(OpsKpi k) => SizedBox(width: 171, child: k);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        tile(OpsKpi(
          label: 'Open incidents',
          value: '${open.length}',
          hint: '$waiting not fully staffed',
          selected: _kpi == _Kpi.all,
          onTap: () => setState(() => _kpi = _Kpi.all),
        )),
        tile(OpsKpi(
          label: 'Need attention',
          value: '${attention.length}',
          hint: 'SLA, SOS, extra units, GPS',
          alert: attention.isNotEmpty,
          selected: _kpi == _Kpi.attention,
          onTap: () => setState(() => _kpi = _kpi == _Kpi.attention ? _Kpi.all : _Kpi.attention),
        )),
        tile(OpsKpi(
          label: 'Units on duty',
          value: '${onDuty.length}',
          hint: '${onDuty.where((r) => r.availabilityStatus == 'Available').length} available',
          selected: _section == OpsSection.units && _unitsFilter == null,
          onTap: () => setState(() {
            _section = OpsSection.units;
            _unitsFilter = null;
          }),
        )),
        tile(OpsKpi(
          label: 'Units on a job',
          value: '${onJob.length}',
          hint: 'working now',
          selected: _section == OpsSection.units && _unitsFilter == 'On a job',
          onTap: () => setState(() {
            _section = OpsSection.units;
            _unitsFilter = 'On a job';
          }),
        )),
        tile(OpsKpi(
          label: 'Median time to accept',
          value: median == null ? '-' : _shortDuration(median),
          hint: median == null ? 'nothing accepted today yet' : 'today · ${gaps.length} accepted',
          selected: _kpi == _Kpi.today,
          onTap: () => setState(() => _kpi = _kpi == _Kpi.today ? _Kpi.all : _Kpi.today),
        )),
        tile(OpsKpi(
          label: 'Open SOS',
          value: '${sos.length}',
          hint: sos.isEmpty ? 'none' : 'responder needs help',
          alert: sos.isNotEmpty,
          selected: _kpi == _Kpi.sos,
          onTap: () => setState(() => _kpi = _kpi == _Kpi.sos ? _Kpi.all : _Kpi.sos),
        )),
      ]),
    );
  }

  Widget _passOnBanner(List<OpsNote> pinned, bool wide) {
    return Container(
      margin: EdgeInsets.fromLTRB(wide ? 0 : 12, wide ? 6 : 8, wide ? 0 : 12, wide ? 8 : 4),
      padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2620),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3C4A3E)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.push_pin_outlined, size: 13, color: Color(0xFFB8D8BD)),
          const SizedBox(width: 5),
          const Text('PASS-ON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: Color(0xFFB8D8BD))),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 26), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => setState(() => _section = OpsSection.passOnNotes),
            child: const Text('All notes', style: TextStyle(fontSize: 11.5)),
          ),
        ]),
        for (final n in pinned.take(wide ? 2 : 1))
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFFDDE9DE), height: 1.3)),
          ),
      ]),
    );
  }
}

String _shortDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}
