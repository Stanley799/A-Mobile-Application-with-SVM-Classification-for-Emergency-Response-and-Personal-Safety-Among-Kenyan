import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shows a time-ordered history merged from incidents and safety check-ins.
///
/// When [limit] is set, the widget omits its page heading and renders only that
/// many recent records for embedding in another screen.
class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({super.key, this.limit});

  final int? limit;

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final incidents = FirebaseFirestore.instance
        .collection('incidents')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit ?? 20)
        .snapshots();
    final checkins = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit ?? 20)
        .snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (limit == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text('Recent Activity', style: Theme.of(context).textTheme.headlineSmall),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: incidents,
            builder: (context, incidentSnapshot) {
              if (incidentSnapshot.hasError) {
                return const Center(child: Text('Unable to load recent activity.'));
              }
              if (!incidentSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: checkins,
                builder: (context, checkinSnapshot) {
                  if (checkinSnapshot.hasError) {
                    return const Center(child: Text('Unable to load recent activity.'));
                  }
                  if (!checkinSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Keep both collections in one chronological list for the resident.
                  final items = <_ActivityItem>[
                    ...incidentSnapshot.data!.docs.map(
                      (document) => _ActivityItem.fromDocument(
                        document,
                        type: 'SOS',
                        label: document.data()['category'] as String? ?? 'Emergency',
                      ),
                    ),
                    ...checkinSnapshot.data!.docs.map(
                      (document) => _ActivityItem.fromDocument(
                        document,
                        type: 'Check-In',
                        label: 'Safety check-in',
                      ),
                    ),
                  ]..sort((first, second) => second.createdAt.compareTo(first.createdAt));
                  final visibleItems = items.take(limit ?? items.length).toList();
                  if (visibleItems.isEmpty) {
                    return const Center(child: Text("No recent activity. You're all set."));
                  }

                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(12, limit == null ? 0 : 8, 12, 24),
                    itemCount: visibleItems.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.type == 'SOS'
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(context).colorScheme.tertiaryContainer,
                          child: Icon(item.type == 'SOS' ? Icons.sos : Icons.check_circle_outline),
                        ),
                        title: Text('${item.type} · ${item.label}'),
                        subtitle: Text(DateFormat('MMM d, h:mm a').format(item.createdAt)),
                        trailing: Text(item.status),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.type,
    required this.label,
    required this.status,
    required this.createdAt,
  });

  final String type;
  final String label;
  final String status;
  final DateTime createdAt;

  factory _ActivityItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    required String type,
    required String label,
  }) {
    final data = document.data();
    final createdAt = data['createdAt'];
    return _ActivityItem(
      type: type,
      label: label,
      status: data['status'] as String? ?? 'Unknown',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}