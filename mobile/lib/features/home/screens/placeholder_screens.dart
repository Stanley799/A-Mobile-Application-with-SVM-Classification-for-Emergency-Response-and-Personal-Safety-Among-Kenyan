import 'package:cloud_firestore/cloud_firestore.dart';
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
    final pendingResponders = FirebaseFirestore.instance
        .collection('responders')
        .where('verificationStatus', isEqualTo: 'Pending')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthRepository>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: pendingResponders,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load pending responders.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final responders = snapshot.data!.docs;
          if (responders.isEmpty) {
            return const Center(child: Text('No responders are awaiting verification.'));
          }

          return ListView.separated(
            itemCount: responders.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final responder = responders[index].data();
              final registrationNumber = responder['registrationNumber'] as String? ?? '';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                title: Text(responder['organizationName'] as String? ?? 'Unnamed organization'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Type: ${responder['organizationType'] ?? 'Unknown'}'),
                    const SizedBox(height: 4),
                    Text(
                      'Organization Registration Number',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    SelectableText(
                      registrationNumber.isEmpty ? 'Not provided' : registrationNumber,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Service Area: ${responder['serviceArea'] ?? 'Unspecified'}'),
                  ],
                ),
              );
            },
          );
        },
      ),
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
