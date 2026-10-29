// The "Alert recorded" content, laid out the way a ride app shows a trip: what happened, where you are, who is coming and when, what to do now.
// Put it inside the existing alert sheet (it does not scroll by itself). Every sentence is human; nothing here shows an internal code.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/dispatch_models.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/glass.dart';
import '../../../core/ui/routes.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/tokens.dart';
import '../first_aid/first_aid_entry.dart';
import '../map/help_map_screen.dart';
import '../map/help_models.dart';
import '../map/help_repository.dart';
import '../map/location_gate.dart';
import '../map/resident_track_publisher.dart';
import '../quiet_mode.dart';
import '../widgets/closure_sheet.dart';
import '../widgets/dispatch_card.dart' show watchDispatch;
import 'location_confidence.dart';

class AlertStatusBody extends StatefulWidget {
  const AlertStatusBody({
    super.key,
    required this.incidentId,
    required this.categoryLabel,
    this.priorityLabel,
    this.reference,
    this.receivedAt,
    this.detailsPending = false,
    this.onAddDetails,
    this.repo,
    this.quiet,
    this.dispatch,
    this.sending = false,
    this.onRaiseAlert,
  });
  final String incidentId;
  final String categoryLabel; // e.g. "Road Accident"
  final String? priorityLabel; // "High" | "Medium" | "Low"
  final String? reference; // short ref shown to the resident
  final DateTime? receivedAt;
  final bool detailsPending; // show the optional "Add more details" row
  final VoidCallback? onAddDetails;
  final HelpRepository? repo;
  final QuietMode? quiet;
  final Stream<DispatchInfo>? dispatch; // injectable for tests; defaults to the incident's dispatch summary
  final bool sending; // the create write has not been confirmed by the server yet
  final VoidCallback? onRaiseAlert;

  @override
  State<AlertStatusBody> createState() => _AlertStatusBodyState();
}

class _AlertStatusBodyState extends State<AlertStatusBody> {
  late final HelpRepository repo = widget.repo ?? HelpRepository();
  late final QuietMode _quiet = widget.quiet ?? QuietMode();
  String? _street;
  String _streetFor = '';
  bool _answering = false;
  bool _closureOpen = false;

  /// "Show once" survives reopening the alert sheet in the same app session.
  static final Set<String> _closureShown = {};

  @override
  void dispose() {
    if (widget.quiet == null) _quiet.dispose();
    super.dispose();
  }

  Future<void> _loadStreet(IncidentInfo i) async {
    if (!i.hasLocation) return;
    final key = '${i.latitude!.toStringAsFixed(4)},${i.longitude!.toStringAsFixed(4)}';
    if (key == _streetFor) return;
    _streetFor = key;
    final s = await repo.geocode(i.latitude!, i.longitude!);
    if (mounted && key == _streetFor) setState(() => _street = s);
  }

  Future<void> _call(String number) async {
    if (kIsWeb) {
      try {
        await Clipboard.setData(ClipboardData(text: number));
      } catch (_) {/* number is still on the button */}
      if (mounted) AppToast.show(context, 'A computer cannot dial. $number was copied; call it from your phone.');
      return;
    }
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) AppToast.show(context, 'Could not open the dialer. Please dial $number.', kind: ToastKind.error);
  }

  Future<void> _movePin(IncidentInfo i) async {
    final start = i.hasLocation ? LatLng(i.latitude!, i.longitude!) : const LatLng(-1.2921, 36.8219);
    final p = await Navigator.of(context).push<LatLng>(appRoute((_) => ManualPinPage(start: start)));
    if (p == null || !mounted) return;
    final ok = await repo.saveLocation(widget.incidentId, p.latitude, p.longitude);
    if (ok) await repo.saveContext(widget.incidentId, source: 'manual_pin', accuracyM: 30);
    if (!mounted) return;
    AppToast.show(context, ok ? 'Location updated.' : 'Could not update the location. Try again.', kind: ok ? ToastKind.success : ToastKind.error);
  }

  Future<void> _editLandmark(IncidentInfo i) async {
    final controller = TextEditingController(text: i.landmark);
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Landmark or building'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. opposite Westgate gate B'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    final ok = await repo.saveContext(widget.incidentId, landmark: text);
    if (mounted) AppToast.show(context, ok ? 'Landmark saved.' : 'Could not save the landmark.', kind: ok ? ToastKind.success : ToastKind.error);
  }

  Future<void> _answerCheckin(CheckinQuestion q, String reply) async {
    if (_answering) return;
    if (!_quiet.on) HapticFeedback.selectionClick(); // a small tick, deliberately silent in quiet mode
    setState(() => _answering = true);
    final ok = await repo.replyCheckin(widget.incidentId, q.id, reply);
    if (!mounted) return;
    setState(() => _answering = false);
    if (!ok) AppToast.show(context, 'Your answer did not send. Try again.', kind: ToastKind.error);
  }

  /// Completed or closed: ask once whether the caller is safe. Never required, never repeated.
  void _maybePromptClosure(IncidentInfo inc) {
    if (inc.status != 'Resolved' || inc.feedbackSafe != null) return;
    if (_closureOpen || _closureShown.contains(widget.incidentId)) return;
    _closureShown.add(widget.incidentId);
    _closureOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showClosureSheet(
        context,
        onSave: (safe, rating) => repo.saveFeedback(widget.incidentId, safe: safe, rating: rating),
        onRaiseAlert: widget.onRaiseAlert,
      );
      _closureOpen = false;
    });
  }

  void _openMap() => Navigator.of(context).push(appRoute((_) => HelpMapScreen(incidentId: widget.incidentId)));

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${_two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IncidentInfo>(
      stream: repo.watchIncident(widget.incidentId),
      builder: (context, incSnap) {
        final inc = incSnap.data ?? const IncidentInfo();
        _loadStreet(inc);
        _maybePromptClosure(inc);
        return StreamBuilder<HelpState>(
          stream: repo.watchOptions(widget.incidentId),
          builder: (context, optSnap) {
            final help = optSnap.data ?? const HelpState();
            return StreamBuilder<DispatchInfo>(
              stream: widget.dispatch ?? watchDispatch(widget.incidentId),
              builder: (context, dSnap) {
                final info = dSnap.data ?? DispatchInfo.empty;
                return StreamBuilder<CheckinQuestion?>(
                  stream: repo.watchCheckin(widget.incidentId),
                  builder: (context, cSnap) {
                    final question = cSnap.data;
                    return ListenableBuilder(
                      listenable: _quiet,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (question != null) ...[_checkinCard(question), const SizedBox(height: 12)],
                          _quietRow(),
                          if (_sharing(inc)) ...[const SizedBox(height: 8), _sharingPill()],
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: _quiet.on ? 0.82 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _header(),
                                const SizedBox(height: 14),
                                _locationCard(inc),
                                const SizedBox(height: 12),
                                _statusCard(info, help, incSnap.hasData && optSnap.hasData, inc.status),
                                const SizedBox(height: 12),
                                _callRow(),
                                const SizedBox(height: 12),
                                _mapButton(help),
                                if (inc.category != null) ...[const SizedBox(height: 12), _firstAidButton(inc)],
                                if (widget.detailsPending && widget.onAddDetails != null) ...[const SizedBox(height: 12), _detailsRow()],
                                const SizedBox(height: 12),
                                _quickDetails(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------- pieces
  BoxDecoration get _card => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Tk.rCard), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 16, offset: Offset(0, 4))]);

  Widget _chip(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Tk.rPill)),
    child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
  );

  /// Discreet, always visible: one line and a switch. It does not open anything.
  Widget _quietRow() => Semantics(
    toggled: _quiet.on,
    label: "I can't speak or make noise",
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(_quiet.on ? Icons.volume_off_rounded : Icons.volume_off_outlined, size: 18, color: Tk.mute),
          const SizedBox(width: 8),
          const Expanded(
            child: Text("I can't speak or make noise", style: TextStyle(fontSize: 13, color: Tk.mute)),
          ),
          Switch.adaptive(
            value: _quiet.on,
            onChanged: _quiet.set,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    ),
  );

  bool _sharing(IncidentInfo inc) =>
      (inc.status == 'Active' || inc.status == 'SupportOnly') && ResidentTrackPublisher.instance.holds(widget.incidentId);

  Widget _sharingPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Tk.brandTint, borderRadius: BorderRadius.circular(Tk.rPill)),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, size: 15, color: Tk.brandDeep),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Sharing your location with responders until this alert ends',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Tk.brandDeep),
          ),
        ),
      ],
    ),
  );

  Widget _checkinCard(CheckinQuestion q) => Container(
    key: ValueKey('checkin-${q.id}'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Tk.brandTint, borderRadius: BorderRadius.circular(Tk.rCard)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('FROM DISPATCH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Tk.brandDeep, letterSpacing: .8)),
        const SizedBox(height: 6),
        Text(q.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Tk.ink, height: 1.3)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _answerButton('Yes', Tk.okInk, const Color(0xFFE7F5EA), 'yes', q)),
            const SizedBox(width: 8),
            Expanded(child: _answerButton('No', Tk.danger, Tk.dangerTint, 'no', q)),
            if (!_quiet.on) ...[
              const SizedBox(width: 8),
              Expanded(child: _answerButton('Not sure', Tk.mute, const Color(0xFFEDEBE6), 'unsure', q)),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _answerButton(String label, Color fg, Color bg, String value, CheckinQuestion q) => SizedBox(
    height: 52,
    child: Semantics(
      button: true,
      label: 'Answer $label',
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 6)),
        onPressed: _answering ? null : () => _answerCheckin(q, value),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    ),
  );

  Widget _header() {
    final p = widget.priorityLabel;
    final (pbg, pfg) = switch (p) {
      'High' => (Tk.dangerTint, Tk.danger),
      'Medium' => (Tk.warnTint, Tk.warnInk),
      _ => (Tk.okTint, Tk.okInk),
    };
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 600);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: motion,
          curve: Tk.spring,
          builder: (_, v, child) => Transform.scale(scale: widget.sending ? 1 : v, child: child),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: widget.sending ? Tk.brandTint : Tk.okTint, shape: BoxShape.circle),
            child: widget.sending
                ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.6, color: Tk.brandDeep))
                : const Icon(Icons.check_rounded, size: 30, color: Tk.okInk),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.sending ? 'Sending your alert…' : 'Alert recorded', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Tk.ink)),
            if (!widget.sending) ...[
              const SizedBox(height: 4),
              const Text("We have your alert. You don't need to do anything else.", style: TextStyle(fontSize: 14, height: 1.4, color: Tk.mute)),
            ],
            if (!widget.sending && widget.receivedAt != null) Text('Received at ${_clock(widget.receivedAt!)}', style: const TextStyle(fontSize: 13, color: Tk.mute)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (p != null) _chip('$p priority', pbg, pfg),
              _chip(widget.categoryLabel, Tk.brandTint, Tk.brandDeep),
              if (widget.reference != null) _chip('Ref ${widget.reference}', const Color(0xFFEDEBE6), Tk.mute),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _locationCard(IncidentInfo inc) {
    final has = inc.hasLocation;
    final where = !has ? 'Finding your location…' : (_street ?? '${inc.latitude!.toStringAsFixed(4)}, ${inc.longitude!.toStringAsFixed(4)}');
    final accuracy = has ? accuracyWords(inc.accuracyM) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFFE8F0FE), shape: BoxShape.circle), child: has ? const Icon(Icons.my_location, color: Tk.you) : const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.4, color: Tk.you))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LOCATION SHARED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Tk.mute, letterSpacing: .8)),
                const SizedBox(height: 2),
                Text(where, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Tk.ink)),
                if (accuracy != null) ...[
                  const SizedBox(height: 2),
                  Text(accuracy, style: const TextStyle(fontSize: 12.5, color: Tk.mute)),
                ],
                if (inc.landmark.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Landmark: ${inc.landmark}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Tk.mute)),
                ],
              ]),
            ),
            TextButton(onPressed: () => _movePin(inc), child: Text(has ? 'Wrong place?' : 'Set it', style: const TextStyle(fontWeight: FontWeight.w800, color: Tk.brandDeep))),
          ]),
          if (has)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _editLandmark(inc),
                  icon: const Icon(Icons.place_outlined, size: 16),
                  label: Text(inc.landmark.isEmpty ? 'Add a landmark' : 'Change landmark', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Tk.brandDeep)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 34)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One calm sentence about who is coming. Big number like a ride app. Never claims more than is true.
  Widget _statusCard(DispatchInfo info, HelpState help, bool loaded, String? incStatus) {
    if (widget.sending) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card,
        child: const Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Tk.brand)),
          SizedBox(width: 12),
          Expanded(child: Text('We are finding the nearest help.', style: TextStyle(fontSize: 15, color: Tk.mute))),
        ]),
      );
    }
    if (!loaded) return Container(padding: const EdgeInsets.all(16), decoration: _card, child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 140, height: 14), SizedBox(height: 12), Skeleton(width: 90, height: 30), SizedBox(height: 12), Skeleton(height: 8)]));
    final held = help.options.where((o) => o.holdsJob).toList();
    final first = help.options.isEmpty ? null : help.options.first;
    String title, sub;
    String? big;
    double? progress;
    var working = false, warn = false;
    if (info.state == 'cancelled' || incStatus == 'Cancelled') {
      title = 'Alert cancelled. No help is being sent. Stay safe.';
      sub = '';
    } else if (info.state == 'completed') {
      title = 'Help has been completed';
      sub = 'We hope you are safe. You can close this screen.';
    } else if (held.isNotEmpty) {
      final o = held.first;
      final m = o.etaMin?.round().clamp(1, 999);
      switch (o.status) {
        case 'arrived':
          title = '${o.name} has arrived.';
          sub = 'Stay where you are and keep your phone with you.';
          progress = 1;
        case 'enroute':
          title = '${o.name} is on the way.';
          sub = 'You can follow them on the map.';
          big = m == null ? null : '$m min';
          progress = 0.65;
        default:
          title = m == null ? '${o.name} is coming.' : '${o.name} is coming. About $m min away.';
          sub = 'Stay where you are. Keep your phone with you.';
          big = m == null ? null : '$m min';
          progress = 0.3;
      }
    } else if (info.state == 'unfilled') {
      title = 'Still looking. If you are in danger, call 999 or 922 now.';
      sub = 'Keep your phone with you.';
      warn = true;
      working = true;
    } else if (help.meta.asking.isNotEmpty) {
      title = 'We are finding the nearest help.';
      sub = 'We are asking the closest units now. This usually takes a few seconds.';
      working = true;
    } else if (first != null) {
      final m = first.etaMin?.round().clamp(1, 999);
      title = 'Nearest help: ${first.name}';
      sub = 'No responder is free to come right now. Call them, or open the map for directions.';
      big = m == null ? null : '$m min';
      warn = true;
    } else {
      title = 'We are finding the nearest help.';
      sub = 'This usually takes a few seconds.';
      working = true;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (working) const Padding(padding: EdgeInsets.only(right: 8), child: PulseDot(size: 9)),
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: warn ? Tk.warnInk : Tk.ink))),
        ]),
        if (big != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(big, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Tk.ink, height: 1)), const SizedBox(width: 8), Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(held.isEmpty ? 'estimated' : 'away', style: const TextStyle(fontSize: 13, color: Tk.mute)))])),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: const Color(0xFFEDEBE6), color: warn ? Tk.warnInk : Tk.brand),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(sub, style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.mute)),
        ],
      ]),
    );
  }

  Widget _callRow() => Row(children: [
    Expanded(child: _callBtn('999', 'Emergency services', Tk.danger)),
    const SizedBox(width: 10),
    Expanded(child: _callBtn('922', 'Dispatch centre', const Color(0xFF1F3A5F))),
  ]);

  Widget _callBtn(String number, String caption, Color c) => Semantics(
    button: true,
    label: 'Call $number, $caption',
    child: Material(
      color: c,
      borderRadius: BorderRadius.circular(Tk.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tk.rCard),
        onTap: () => _call(number),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            const Icon(Icons.call, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Call $number', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white)),
            ])),
          ]),
        ),
      ),
    ),
  );

  Widget _firstAidButton(IncidentInfo inc) => Semantics(
    button: true,
    label: 'First aid for this emergency',
    child: OutlinedButton.icon(
      onPressed: () => openFirstAid(context, category: inc.category, subtype: inc.subtype, quiet: _quiet.on),
      icon: const Icon(Icons.medical_services_outlined, size: 20),
      label: const Text('First aid for this emergency', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(foregroundColor: Tk.brandDeep, side: const BorderSide(color: Tk.brand), minimumSize: const Size(0, 52)),
    ),
  );

  Widget _mapButton(HelpState help) {
    final n = help.options.length;
    final first = help.options.isEmpty ? null : help.options.first;
    final m = first?.etaMin?.round().clamp(1, 999);
    final sub = n == 0 ? 'Hospitals, police and more near you' : '$n option${n == 1 ? '' : 's'}${m == null ? '' : ' · nearest about $m min'}';
    return Material(
      color: Tk.brand,
      borderRadius: BorderRadius.circular(Tk.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tk.rCard),
        onTap: _openMap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.map_outlined, color: Colors.white, size: 28),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('See help on the map', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(sub, style: const TextStyle(fontSize: 13, color: Colors.white)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }

  Widget _detailsRow() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: _card,
    child: Row(children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Add more details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Tk.ink)),
        SizedBox(height: 2),
        Text('Optional. Helps responders prepare. About 30 seconds.', style: TextStyle(fontSize: 12, color: Tk.mute)),
      ])),
      AppButton(label: 'Add', onPressed: widget.onAddDetails, expand: false, height: 44),
    ]),
  );

  Widget _quickDetails() {
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [Text(k, style: const TextStyle(fontSize: 14, color: Tk.mute)), const Spacer(), Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Tk.ink)))]),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: _card,
      child: Column(children: [
        row('Type', widget.categoryLabel),
        if (widget.priorityLabel != null) row('Priority', widget.priorityLabel!),
        if (widget.reference != null) row('Reference', widget.reference!),
        if (widget.receivedAt != null) row('Received', _clock(widget.receivedAt!)),
      ]),
    );
  }
}
