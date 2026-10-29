import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/responder/responder_offer_queue.dart';

Offer _offer({
  required String id,
  required String status,
  required String priority,
  required DateTime createdAt,
  DateTime? expiresAt,
}) => Offer(
  id: id,
  incidentId: 'incident-$id',
  incidentCode: 'test-$id',
  responderId: 'responder-1',
  role: 'medical_transport',
  status: status,
  priority: priority,
  category: 'Medical Emergency',
  subtype: null,
  distanceKm: 2.4,
  latitude: -1.29,
  longitude: 36.82,
  flags: const [],
  needs: const ['medical_transport'],
  peopleCount: 1,
  wave: 1,
  summary: 'Medical emergency',
  confidential: false,
  freeText: '',
  expiresAt: expiresAt,
  createdAt: createdAt,
  respondedAt: null,
  residentFirstName: null,
  residentPhone: null,
  withdrawReason: null,
);

void main() {
  test('open offers sort by urgency then soonest expiry', () {
    final now = DateTime(2026, 10, 28, 12);
    final offers = [
      _offer(
        id: 'low',
        status: 'offered',
        priority: 'Low',
        createdAt: now,
        expiresAt: now.add(const Duration(seconds: 40)),
      ),
      _offer(
        id: 'high-later',
        status: 'offered',
        priority: 'High',
        createdAt: now,
        expiresAt: now.add(const Duration(seconds: 35)),
      ),
      _offer(
        id: 'medium',
        status: 'offered',
        priority: 'Medium',
        createdAt: now,
        expiresAt: now.add(const Duration(seconds: 20)),
      ),
      _offer(
        id: 'high-sooner',
        status: 'offered',
        priority: 'High',
        createdAt: now,
        expiresAt: now.add(const Duration(seconds: 10)),
      ),
      _offer(
        id: 'expired',
        status: 'offered',
        priority: 'High',
        createdAt: now,
        expiresAt: now.subtract(const Duration(seconds: 1)),
      ),
    ];

    expect(
      ResponderOfferQueue.openOffers(offers, now: now).map((offer) => offer.id),
      ['high-sooner', 'high-later', 'medium', 'low'],
    );
  });

  test('closed offers are grouped newest-first for earlier today', () {
    final now = DateTime(2026, 10, 28, 12);
    final offers = [
      _offer(
        id: 'old',
        status: 'declined',
        priority: 'Low',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      _offer(
        id: 'new',
        status: 'completed',
        priority: 'High',
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      _offer(
        id: 'yesterday',
        status: 'expired',
        priority: 'High',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ];

    expect(
      ResponderOfferQueue.earlierToday(
        offers,
        now: now,
      ).map((offer) => offer.id),
      ['new', 'old'],
    );
  });
}
