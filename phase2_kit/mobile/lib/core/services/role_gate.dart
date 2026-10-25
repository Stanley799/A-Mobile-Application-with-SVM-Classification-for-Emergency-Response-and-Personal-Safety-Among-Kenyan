// Decides which app a signed-in person sees: administrator dashboard, responder app, or the normal resident app.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/admin/admin_shell.dart';
import '../../features/responder/responder_shell.dart';

enum AppRole { admin, responder, resident }

Future<AppRole> resolveRole() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return AppRole.resident;
  try {
    final token = await user.getIdTokenResult(true);
    if (token.claims?['role'] == 'SystemAdmin') return AppRole.admin;
  } catch (_) {}
  try {
    final s = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (s.data()?['role'] == 'Responder') return AppRole.responder;
  } catch (_) {}
  return AppRole.resident;
}

/// Wrap the screen shown after sign-in:  RoleGate(residentBuilder: (_) => const HomeScreen())
class RoleGate extends StatefulWidget {
  const RoleGate({super.key, required this.residentBuilder});
  final WidgetBuilder residentBuilder;

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late final Future<AppRole> _role = resolveRole();

  @override
  Widget build(BuildContext context) => FutureBuilder<AppRole>(
    future: _role,
    builder: (context, snap) {
      if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return switch (snap.data!) {
        AppRole.admin => const AdminShell(),
        AppRole.responder => const ResponderGate(),
        AppRole.resident => widget.residentBuilder(context),
      };
    },
  );
}
