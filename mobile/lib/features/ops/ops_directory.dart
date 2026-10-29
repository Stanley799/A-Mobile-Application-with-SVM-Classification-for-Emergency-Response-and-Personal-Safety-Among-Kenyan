// Directory manager (administrators only): search facilities, edit their details, mark a phone verified,
// add one, and deactivate one after a confirmation. Type values stay the ones the resident map understands.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'ops_repository.dart';
import 'ops_tokens.dart';
import 'ops_widgets.dart';

const List<String> kFacilityTypes = ['hospital', 'clinic', 'police', 'fire', 'ambulance_operator', 'helpline'];
const Map<String, String> kFacilityTypeWords = {
  'hospital': 'Hospital',
  'clinic': 'Clinic',
  'police': 'Police',
  'fire': 'Fire & rescue',
  'ambulance_operator': 'Ambulance service',
  'helpline': 'Helpline',
};

/// Kenyan mobile numbers only: 07XX XXX XXX, 01XX XXX XXX, or the same with +254 / 254.
String? phoneError(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (!RegExp(r'^(?:\+?254|0)(7\d{8}|1\d{8})$').hasMatch(digits)) {
    return 'Use a Kenyan number, for example 0712 345 678 or +254 712 345 678.';
  }
  return null;
}

class OpsDirectory extends StatefulWidget {
  const OpsDirectory({super.key, required this.repo});
  final OpsRepository repo;

  @override
  State<OpsDirectory> createState() => _OpsDirectoryState();
}

class _OpsDirectoryState extends State<OpsDirectory> {
  late Future<List<OpsFacility>> _future = widget.repo.loadFacilities();
  String _q = '';
  String _show = 'All';

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OpsFacility>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const OpsSkeleton(rows: 8);
        if (s.hasError) return ErrorState(message: 'Could not load the directory: ${s.error}', onRetry: () => setState(() => _future = widget.repo.loadFacilities()));
        final all = s.data ?? const <OpsFacility>[];
        final q = _q.trim().toLowerCase();
        final list = [
          for (final f in all)
            if (_show == 'All' ||
                (_show == 'Active' && f.status == 'active') ||
                (_show == 'Hidden' && f.status != 'active') ||
                (_show == 'Unverified phone' && !f.verified))
              if (q.isEmpty ||
                  f.name.toLowerCase().contains(q) ||
                  f.address.toLowerCase().contains(q) ||
                  f.phone.contains(q) ||
                  (kFacilityTypeWords[f.type] ?? f.type).toLowerCase().contains(q))
                f,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OpsSectionHeader(
            'Directory',
            subtitle: '${all.length} facilities · the resident map hides anything that is not active',
            trailing: FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add, size: 18), label: const Text('Add facility')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(OT.pad, 0, OT.pad, 4),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 300,
                height: 36,
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  style: const TextStyle(fontSize: 13, color: OT.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: OT.raised,
                    hintText: 'Search name, phone, address or type',
                    hintStyle: const TextStyle(fontSize: 12.5, color: OT.muted),
                    prefixIcon: const Icon(Icons.search, size: 17, color: OT.muted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              for (final f in const ['All', 'Active', 'Hidden', 'Unverified phone'])
                ChoiceChip(label: Text(f), selected: _show == f, onSelected: (_) => setState(() => _show = f)),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(icon: Icons.location_city_outlined, title: 'No facility matches', message: 'Change the search or the filter.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(OT.pad, 6, OT.pad, 20),
                    itemCount: list.length,
                    itemBuilder: (_, k) => _card(list[k]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _card(OpsFacility f) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.all(11),
    decoration: OT.panelDecoration(),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(f.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: OT.text)),
            OpsTag(kFacilityTypeWords[f.type] ?? f.type),
            if (f.status != 'active') const OpsTag('Hidden', bg: Color(0xFF33280F), fg: Color(0xFFFFCF7A)),
            if (!f.verified) const OpsTag('Unverified phone', bg: Color(0xFF3A2020), fg: Color(0xFFFFB8B0), border: Color(0xFF7A3A3A)),
          ]),
          const SizedBox(height: 3),
          Text(
            '${f.phone.isEmpty ? 'No phone' : f.phone}'
            '${f.address.isEmpty ? '' : ' · ${f.address}'}'
            '${f.is24h == true ? ' · open 24 h' : ''}'
            '${f.verified && f.verifiedAt != null ? ' · verified ${_date(f.verifiedAt!)}' : ''}',
            style: const TextStyle(fontSize: 11.5, color: OT.muted),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      OutlinedButton(onPressed: () => _edit(f), child: const Text('Edit')),
    ]),
  );

  Future<void> _edit(OpsFacility? f) async {
    final name = TextEditingController(text: f?.name ?? '');
    final phone = TextEditingController(text: f?.phone ?? '');
    final address = TextEditingController(text: f?.address ?? '');
    var type = kFacilityTypes.contains(f?.type) ? f!.type : 'hospital';
    var is24h = f?.is24h ?? false;
    var active = f == null || f.status == 'active';
    var verified = f?.verified ?? false;
    String? nameErr;
    String? phoneErr;

    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          backgroundColor: OT.panel,
          title: Text(f == null ? 'Add a facility' : 'Edit ${f.name}', style: const TextStyle(color: OT.text)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: name, maxLength: 80, decoration: InputDecoration(labelText: 'Name', errorText: nameErr, border: const OutlineInputBorder())),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                  items: [for (final t in kFacilityTypes) DropdownMenuItem(value: t, child: Text(kFacilityTypeWords[t]!))],
                  onChanged: (v) => set(() => type = v ?? type),
                ),
                const SizedBox(height: 6),
                TextField(controller: phone, maxLength: 20, decoration: InputDecoration(labelText: 'Phone', helperText: '0712 345 678 or +254 712 345 678', errorText: phoneErr, border: const OutlineInputBorder())),
                const SizedBox(height: 6),
                TextField(controller: address, maxLength: 120, decoration: const InputDecoration(labelText: 'Address (optional)', border: OutlineInputBorder())),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: is24h, onChanged: (v) => set(() => is24h = v), title: const Text('Open 24 hours', style: TextStyle(fontSize: 13.5, color: OT.soft))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: verified,
                  onChanged: (v) => set(() => verified = v),
                  title: const Text('Phone verified', style: TextStyle(fontSize: 13.5, color: OT.soft)),
                  subtitle: Text(f?.verified == true && f?.verifiedAt != null ? 'Last verified ${_date(f!.verifiedAt!)}' : 'Mark this after someone has called the number.', style: const TextStyle(fontSize: 11.5, color: OT.muted)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => set(() => active = v),
                  title: const Text('Active', style: TextStyle(fontSize: 13.5, color: OT.soft)),
                  subtitle: const Text('A hidden facility disappears from the resident map. The record is kept.', style: TextStyle(fontSize: 11.5, color: OT.muted)),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                var ok = true;
                set(() {
                  nameErr = name.text.trim().length < 2 ? 'Give the facility a name.' : null;
                  phoneErr = phoneError(phone.text);
                  ok = nameErr == null && phoneErr == null;
                });
                if (!ok) return;
                Navigator.pop(d, true);
              },
              child: Text(f == null ? 'Add facility' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    if (!mounted) return;

    if (!active && f != null && f.status == 'active') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: OT.panel,
          title: const Text('Deactivate this facility?', style: TextStyle(color: OT.text)),
          content: Text('${f.name} will no longer appear on the resident map. The record is kept and can be reactivated.', style: const TextStyle(color: OT.soft)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep active')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Deactivate')),
          ],
        ),
      );
      if (sure != true) return;
    }

    final fields = <String, dynamic>{
      'name': name.text.trim(),
      'type': type,
      'phones': [phone.text.trim()],
      'address': address.text.trim(),
      'is24h': is24h,
      'status': active ? 'active' : 'hidden',
      'verified': verified,
      if (verified)
        'verifiedAt': DateTime.now().toUtc()
      else
        'verifiedAt': null,
      'verifiedBy': verified ? (FirebaseAuth.instance.currentUser?.uid ?? '') : '',
    };
    try {
      if (f == null) {
        await widget.repo.addFacility(fields);
        _toast('Facility added.');
      } else {
        await widget.repo.updateFacility(f.id, fields);
        _toast('Facility updated.');
      }
      setState(() => _future = widget.repo.loadFacilities());
    } catch (e) {
      _toast('Could not save: $e');
    }
  }
}

String _date(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
