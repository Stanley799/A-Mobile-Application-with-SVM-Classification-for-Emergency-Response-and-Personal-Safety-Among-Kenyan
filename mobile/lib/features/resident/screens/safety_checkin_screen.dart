import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/models/safety_checkin.dart';

class SafetyCheckinScreen extends StatefulWidget {
  const SafetyCheckinScreen({super.key});

  @override
  State<SafetyCheckinScreen> createState() => _SafetyCheckinScreenState();
}

class _SafetyCheckinScreenState extends State<SafetyCheckinScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final activeCheckins = FirebaseFirestore.instance
        .collection('safetyCheckins')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'Active')
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: activeCheckins,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _panel(
            context,
            const Text('Unable to load your safety check-in.'),
          );
        }
        if (!snapshot.hasData) {
          return _panel(
            context,
            const SizedBox(
              height: 36,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.data!.docs.isEmpty) {
          return _panel(
            context,
            Row(
              children: [
                const Expanded(child: Text('Not Started')),
                FilledButton.tonal(
                  onPressed: _chooseDuration,
                  child: const Text('Start Check-In'),
                ),
              ],
            ),
          );
        }

        final checkin = SafetyCheckIn.fromDocument(snapshot.data!.docs.first);
        final remaining = checkin.expiryTime.difference(DateTime.now());
        final overdue = remaining.isNegative || remaining == Duration.zero;
        return _panel(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      overdue ? 'Overdue' : 'Active',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!overdue)
                    Text(
                      '${_twoDigits(remaining.inMinutes)}:${_twoDigits(remaining.inSeconds.remainder(60))} remaining',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _checkIn(checkin.id),
                      child: const Text('Check In Now'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Cancel check-in',
                    onPressed: () => _updateStatus(checkin.id, 'Cancelled'),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _panel(BuildContext context, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Safety Check-In', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDuration() async {
    final duration = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Choose check-in duration'),
            ),
            for (final minutes in [15, 30, 45, 60])
              ListTile(
                title: Text('$minutes minutes'),
                onTap: () => Navigator.pop(context, minutes),
              ),
          ],
        ),
      ),
    );
    if (duration == null || !mounted) {
      return;
    }

    final userId = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();
    try {
      await FirebaseFirestore.instance.collection('safetyCheckins').add({
        'userId': userId,
        'startTime': FieldValue.serverTimestamp(),
        'expiryTime': Timestamp.fromDate(now.add(Duration(minutes: duration))),
        'status': 'Active',
        'durationMinutes': duration,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start check-in. Please try again.')),
        );
      }
    }
  }

  Future<void> _checkIn(String checkinId) => _updateStatus(checkinId, 'CheckedIn');

  Future<void> _updateStatus(String checkinId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('safetyCheckins')
          .doc(checkinId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to update check-in. Please try again.')),
        );
      }
    }
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}