// The Incidents page: search, filters, 25 rows per page, and the same incident panel in read-only mode.
// Contact details never appear in this list or its CSV export.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/dispatch_models.dart';
import 'ops_incident_panel.dart';
import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

class OpsIncidentsPage extends StatefulWidget {
  const OpsIncidentsPage({
    super.key,
    required this.repo,
    required this.incidents,
    required this.responders,
    required this.offers,
    required this.search,
    required this.selectedId,
    required this.onOpen,
    required this.onClose,
  });

  final OpsRepository repo;
  final List<IncidentRecord> incidents;
  final List<ResponderRecord> responders;
  final List<Offer> offers;
  final String search;
  final String? selectedId;
  final void Function(String id) onOpen;
  final VoidCallback onClose;

  @override
  State<OpsIncidentsPage> createState() => _OpsIncidentsPageState();
}

class _OpsIncidentsPageState extends State<OpsIncidentsPage> {
  static const _pageSize = 25;
  String _status = 'All';
  String _range = '30 days';
  String _category = 'All';
  String _priority = 'All';
  String _outcome = 'Any';
  int _page = 0;

  List<IncidentRecord> get _filtered {
    final q = widget.search.trim().toLowerCase();
    final now = DateTime.now();
    return [
      for (final i in widget.incidents)
        if (_status == 'All' || (_status == 'Open' ? i.isOpen : !i.isOpen))
          if (_outcome == 'Any' || i.status == _outcome)
            if (_category == 'All' || i.category == _category)
              if (_priority == 'All' || i.priority == _priority)
                if (_inRange(i.createdAt, now))
                  if (q.isEmpty ||
                      i.id.toLowerCase().contains(q) ||
                      i.category.toLowerCase().contains(q) ||
                      (i.subtype ?? '').replaceAll('_', ' ').contains(q) ||
                      i.landmark.toLowerCase().contains(q))
                    i,
    ];
  }

  bool _inRange(DateTime? at, DateTime now) {
    if (_range == 'All') return true;
    if (at == null) return false;
    if (_range == 'Today') return at.year == now.year && at.month == now.month && at.day == now.day;
    final days = _range == '7 days' ? 7 : 30;
    return now.difference(at).inDays < days;
  }

  @override
  void didUpdateWidget(covariant OpsIncidentsPage old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    final all = _filtered;
    final pages = all.isEmpty ? 1 : (all.length + _pageSize - 1) ~/ _pageSize;
    if (_page >= pages) _page = pages - 1;
    final start = _page * _pageSize;
    final pageRows = all.skip(start).take(_pageSize).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final panel = widget.selectedId == null
        ? null
        : OpsIncidentPanel(
            key: ValueKey('ro-${widget.selectedId}'),
            repo: widget.repo,
            incidentId: widget.selectedId!,
            responders: widget.responders,
            offers: widget.offers,
            readOnly: true,
            onClose: widget.onClose,
          );

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _filters(),
      Padding(
        padding: const EdgeInsets.fromLTRB(OT.pad, 4, OT.pad, 6),
        child: Row(children: [
          Expanded(
            child: Text(
              '${all.length} incident${all.length == 1 ? '' : 's'} match · page ${_page + 1} of $pages · contact details are not shown here',
              style: const TextStyle(fontSize: 11.5, color: OT.muted),
            ),
          ),
          OutlinedButton.icon(
            onPressed: pageRows.isEmpty ? null : () => _copyCsv(pageRows, all.length),
            icon: const Icon(Icons.copy_all_outlined, size: 16),
            label: const Text('Copy as CSV'),
          ),
        ]),
      ),
      Expanded(
        child: pageRows.isEmpty
            ? const EmptyState(icon: Icons.search_off, title: 'No incidents match', message: 'Change the filters or clear the search box.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(OT.pad, 0, OT.pad, 10),
                itemCount: pageRows.length,
                itemBuilder: (_, k) => _row(pageRows[k]),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(OT.pad, 0, OT.pad, 12),
        child: Row(children: [
          OutlinedButton(onPressed: _page == 0 ? null : () => setState(() => _page--), child: const Text('Previous')),
          const SizedBox(width: 8),
          Text('Page ${_page + 1} of $pages', style: const TextStyle(fontSize: 12, color: OT.muted)),
          const Spacer(),
          OutlinedButton(onPressed: _page >= pages - 1 ? null : () => setState(() => _page++), child: const Text('Next')),
        ]),
      ),
    ]);

    if (wide && panel != null) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 5, child: list),
        const SizedBox(width: 10),
        Expanded(flex: 5, child: panel),
      ]);
    }
    if (panel != null) return panel;
    return list;
  }

  Widget _filters() {
    final categories = ['All', ...{for (final i in widget.incidents) i.category}];
    return Padding(
      padding: const EdgeInsets.fromLTRB(OT.pad, 10, OT.pad, 0),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in const ['Open', 'Closed', 'All'])
          ChoiceChip(label: Text(s), selected: _status == s, onSelected: (_) => setState(() {
            _status = s;
            _page = 0;
          })),
        const SizedBox(width: 8),
        _drop<String>(
          value: _range,
          items: const ['Today', '7 days', '30 days', 'All'],
          label: 'Date',
          labelOf: (v) => v,
          onChanged: (v) => setState(() {
            _range = v;
            _page = 0;
          }),
        ),
        _drop<String>(
          value: _category,
          items: categories,
          label: 'Category',
          labelOf: (v) => v,
          onChanged: (v) => setState(() {
            _category = v;
            _page = 0;
          }),
        ),
        _drop<String>(
          value: _priority,
          items: const ['All', 'High', 'Medium', 'Low'],
          label: 'Priority',
          labelOf: (v) => v,
          onChanged: (v) => setState(() {
            _priority = v;
            _page = 0;
          }),
        ),
        _drop<String>(
          value: _outcome,
          items: const ['Any', 'Resolved', 'Cancelled'],
          label: 'Outcome',
          labelOf: (v) => v == 'Any' ? 'Any outcome' : v,
          onChanged: (v) => setState(() {
            _outcome = v;
            _page = 0;
            if (v != 'Any' && _status == 'Open') _status = 'Closed';
          }),
        ),
      ]),
    );
  }

  Widget _drop<T>({required T value, required List<T> items, required String label, required String Function(T) labelOf, required void Function(T) onChanged}) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: OT.raised, borderRadius: BorderRadius.circular(8), border: Border.all(color: OT.line)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: OT.raised,
          style: const TextStyle(fontSize: 12.5, color: OT.soft),
          hint: Text(label),
          items: [for (final v in items) DropdownMenuItem<T>(value: v, child: Text(labelOf(v)))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _row(IncidentRecord i) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Material(
      color: widget.selectedId == i.id ? OT.raised : OT.panel,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => widget.onOpen(i.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: widget.selectedId == i.id ? OT.accent : OT.line),
          ),
          child: Row(children: [
            SizedBox(
              width: 92,
              child: Text(_stamp(i.createdAt), style: const TextStyle(fontSize: 11, color: OT.muted)),
            ),
            PriorityTag(i.priority),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${i.category}${i.subtype == null ? '' : ' · ${i.subtype!.replaceAll('_', ' ')}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: OT.text),
                ),
                Text(
                  '${i.id}${i.landmark.isEmpty ? '' : ' · ${i.landmark}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: OT.muted),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            OpsTag(i.status, bg: OT.raised, fg: i.isOpen ? OT.accent : OT.soft),
            const SizedBox(width: 6),
            SizedBox(width: 104, child: Text(i.dispatchState.replaceAll('_', ' '), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: OT.muted))),
          ]),
        ),
      ),
    ),
  );

  Future<void> _copyCsv(List<IncidentRecord> rows, int total) async {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final out = StringBuffer('id,createdAt,category,subtype,priority,status,dispatchState,landmark\n');
    for (final i in rows) {
      out.writeln([q(i.id), q(i.createdAt?.toIso8601String() ?? ''), q(i.category), q(i.subtype ?? ''), q(i.priority), q(i.status), q(i.dispatchState), q(i.landmark)].join(','));
    }
    await Clipboard.setData(ClipboardData(text: out.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${rows.length} rows from this page only ($total match the filters; other pages are not included).')),
    );
  }
}

String _stamp(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
