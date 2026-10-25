// Administrator dashboard: Overview, Incidents, Responders. Works on a phone, tablet and the web (Chrome).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart';
import 'admin_admins.dart';
import 'admin_incidents.dart';
import 'admin_overview.dart';
import 'admin_repository.dart';
import 'admin_responders.dart';
import 'admin_widgets.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final AdminRepository repo = AdminRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  int _tab = 0;
  List<IncidentRecord> incidents = const [];
  List<Offer> offers = const [];
  List<ResponderRecord> responders = const [];
  final Map<String, String> _errors = {};
  bool _loaded = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _listen<List<IncidentRecord>>('incidents', repo.watchIncidents(), (v) => incidents = v);
    _listen<List<Offer>>('offers', repo.watchOffers(), (v) => offers = v);
    _listen<List<ResponderRecord>>('responders', repo.watchResponders(), (v) => responders = v);
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {}); // keeps "x min ago" fresh
    });
  }

  void _listen<T>(String name, Stream<T> s, void Function(T) set) {
    _subs.add(s.listen((v) {
      if (!mounted) return;
      setState(() {
        set(v);
        _errors.remove(name);
        _loaded = true;
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _errors[name] = e.toString();
        _loaded = true;
      });
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _clock?.cancel();
    super.dispose();
  }

  static const _titles = ['Overview', 'Incidents', 'Responders', 'Administrators'];
  static const _icons = [Icons.space_dashboard_outlined, Icons.crisis_alert_outlined, Icons.local_shipping_outlined, Icons.admin_panel_settings_outlined];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final page = !_loaded
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            if (_errors.isNotEmpty)
              Container(
                width: double.infinity,
                color: const Color(0xFFFDE8E8),
                padding: const EdgeInsets.all(12),
                child: Text('Some data could not be loaded: ${_errors.entries.map((e) => '${e.key} (${e.value})').join('; ')}', style: const TextStyle(color: Color(0xFF9B1C1C), fontSize: 13)),
              ),
            Expanded(
              child: switch (_tab) {
                0 => AdminOverview(incidents: incidents, offers: offers, responders: responders, onOpen: _openIncident, goTo: (i) => setState(() => _tab = i)),
                1 => AdminIncidents(incidents: incidents, onOpen: _openIncident),
                2 => AdminResponders(repo: repo, responders: responders),
                _ => AdminAdmins(repo: repo),
              },
            ),
          ]);
    return Scaffold(
      backgroundColor: AC.bg,
      appBar: AppBar(
        backgroundColor: AC.card,
        foregroundColor: AC.ink,
        elevation: 0,
        title: Text(wide ? 'Emergency Response · Administration' : _titles[_tab], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: AC.card,
                selectedIndex: _tab,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [for (var i = 0; i < _titles.length; i++) NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_titles[i]))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: page),
            ])
          : page,
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: _tab, onDestinationSelected: (i) => setState(() => _tab = i), destinations: [for (var i = 0; i < _titles.length; i++) NavigationDestination(icon: Icon(_icons[i]), label: _titles[i])]),
    );
  }

  void _openIncident(IncidentRecord i) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IncidentDetailPage(repo: repo, incidentId: i.id, responders: responders)));
  }
}
