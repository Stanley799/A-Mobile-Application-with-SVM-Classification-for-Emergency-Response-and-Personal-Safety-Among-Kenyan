import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/services/auth_repository.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class ResidentHomeScreen extends StatelessWidget {
  const ResidentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _BasePlaceholderScreen(
      title: 'Resident Home',
      body: 'Resident account is active. Phase 1 authentication is complete.',
    );
  }
}

class ResponderHomeScreen extends StatelessWidget {
  const ResponderHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _BasePlaceholderScreen(
      title: 'Responder Home',
      body: 'Responder account is verified and active.',
    );
  }
}

class PendingVerificationScreen extends StatelessWidget {
  const PendingVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _BasePlaceholderScreen(
      title: 'Pending Verification',
      body: 'Your account is awaiting verification by a System Administrator.',
    );
  }
}

class RegistrationRejectedScreen extends StatelessWidget {
  const RegistrationRejectedScreen({super.key, this.verificationNotes});

  final String? verificationNotes;

  @override
  Widget build(BuildContext context) {
    final details = (verificationNotes != null && verificationNotes!.trim().isNotEmpty)
        ? 'Reason: ${verificationNotes!.trim()}'
        : 'Your registration was rejected by a System Administrator.';

    return _BasePlaceholderScreen(
      title: 'Registration Rejected',
      body: details,
    );
  }
}

class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _BasePlaceholderScreen(
      title: 'Account Suspended',
      body: 'Your responder account has been suspended. Contact support for assistance.',
    );
  }
}

class AdminDashboardPlaceholderScreen extends StatelessWidget {
  const AdminDashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _BasePlaceholderScreen(
      title: 'System Admin Dashboard',
      body: 'Phase 1 placeholder for SystemAdmin operations.',
    );
  }
}

class _BasePlaceholderScreen extends StatelessWidget {
  const _BasePlaceholderScreen({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                await context.read<AuthRepository>().signOut();
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}
