import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/ops/ops_logic.dart';

IncidentRecord incident({
  required String id,
  required String priority,
  required int minutesAgo,
  String state = 'dispatching',
  bool attention = false,
  String attentionReason = 'none',
  String category = 'Medical Emergency',
  String? subtype,
  Map<String, String> answers = const {},
  List<DispatchUnit> units = const [],
}) {
  final created = Timestamp.fromDate(DateTime(2026, 10, 29, 12, 0).subtract(Duration(minutes: minutesAgo)));
  return IncidentRecord.fromMap(id, {
    'userId': 'U1',
    'category': category,
    'subtype': subtype,
    'status': 'Active',
    'createdAt': created,
    'location': const GeoPoint(-1.2921, 36.8219),
    'needsAttention': attention,
    'attentionReason': attentionReason,
    'priority': priority,
    'dispatch': {
      'state': state,
      'priority': priority,
      'units': [
        for (final u in units) {'role': u.role, 'name': u.name, 'status': u.status, 'distanceKm': u.distanceKm},
      ],
    },
    'triage': {'answers': answers},
  });
}

DispatchUnit unit(String role, String status) => DispatchUnit(role: role, name: 'Unit', orgType: 'Ambulance', phone: '', status: status, distanceKm: 1.2);

void main() {
  test('priority first, then oldest within the same priority', () {
    final rows = buildQueue([
      incident(id: 'low-old', priority: 'Low', minutesAgo: 30),
      incident(id: 'medium', priority: 'Medium', minutesAgo: 20),
      incident(id: 'high-new', priority: 'High', minutesAgo: 2),
      incident(id: 'high-old', priority: 'High', minutesAgo: 10),
    ]);
    expect([for (final r in rows) r.incident.id], ['high-old', 'high-new', 'medium', 'low-old']);
  });

  test('an SLA breach is pinned above priority order', () {
    final rows = buildQueue([
      incident(id: 'high', priority: 'High', minutesAgo: 1),
      incident(id: 'low-breach', priority: 'Low', minutesAgo: 40, attention: true, attentionReason: 'no_accept_in_time'),
      incident(id: 'medium-breach', priority: 'Medium', minutesAgo: 20, attention: true, attentionReason: 'responder_sos'),
    ]);
    expect(rows.first.incident.id, 'medium-breach');
    expect(rows.first.attentionText, 'A responder raised an SOS');
    expect(rows[1].incident.id, 'low-breach');
    expect(rows[1].attentionText, 'No unit accepted within the target time');
    expect(rows.last.incident.id, 'high');
    expect(rows.last.pinned, isFalse);
  });

  test('fully staffed and settled incidents leave the queue', () {
    final rows = buildQueue([
      incident(id: 'assigned', priority: 'High', minutesAgo: 5, state: 'assigned'),
      incident(id: 'filled', priority: 'High', minutesAgo: 5, units: [unit('medical_transport', 'accepted')]),
      incident(id: 'partial', priority: 'High', minutesAgo: 5, state: 'partially_assigned', category: 'Fire & Rescue', answers: {'trapped': 'Yes'}, units: [unit('fire_suppression', 'accepted')]),
    ]);
    expect([for (final r in rows) r.incident.id], ['partial']);
  });

  test('roles needed come from the category and the answers', () {
    final fire = queueRow(incident(
      id: 'fire',
      priority: 'High',
      minutesAgo: 3,
      category: 'Fire & Rescue',
      answers: {'trapped': 'Yes'},
      units: [unit('fire_suppression', 'enroute')],
    ));
    expect(fire.requiredRoles, ['fire_suppression', 'extrication']);
    expect(fire.rolesLabel, '1 of 2');
    expect(fire.fullyStaffed, isFalse);

    final other = queueRow(incident(id: 'other', priority: 'Low', minutesAgo: 3, category: 'Other / General'));
    expect(other.requiredRoles, isEmpty);
    expect(other.rolesLabel, '0 of 1');
  });

  test('support-only subtypes need no responder', () {
    final support = queueRow(incident(id: 's', priority: 'High', minutesAgo: 3, subtype: 'emotional_distress'));
    expect(support.requiredRoles, isEmpty);
    expect(support.fullyStaffed, isTrue);
    expect(buildQueue([support.incident]), isEmpty);
  });
}
