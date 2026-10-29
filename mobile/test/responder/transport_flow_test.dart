// 2.2 and 2.6: the transport leg only appears after Arrived on jobs that need transport,
// a destination is required before anything is written, and the completion summary uses stored times.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/responder/active_job_screen.dart';
import 'package:mobile/features/responder/responder_repository.dart';
import 'package:mobile/features/responder/transport_models.dart';

class _JobRepository extends ResponderRepository {
  _JobRepository()
    : super(
        db: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'responder-1'),
        ),
      );

  final StreamController<Offer?> offers = StreamController<Offer?>.broadcast();
  final StreamController<List<JobMessage>> messages =
      StreamController<List<JobMessage>>.broadcast();
  final List<(String, String)> transportStarts = [];
  final List<String> savedNotes = [];
  final List<String> responses = [];
  int hospitalArrivals = 0;
  int moreUnitRequests = 0;

  final List<TransportDestination> destinations = const [
    TransportDestination(
      id: 'hosp-a',
      name: 'Aga Khan Hospital',
      type: 'hospital',
      latitude: -1.26,
      longitude: 36.80,
      phone: '+254700000001',
      distanceKm: 2.1,
      verified: true,
    ),
    TransportDestination(
      id: 'clinic-b',
      name: 'Westlands Clinic',
      type: 'clinic',
      latitude: -1.27,
      longitude: 36.81,
      phone: '+254700000002',
      distanceKm: 3.4,
    ),
  ];

  @override
  Stream<Offer?> watchOffer(String id) => offers.stream;

  @override
  Stream<List<JobMessage>> watchMessages(String incidentId) => messages.stream;

  @override
  Future<void> respond(
    String offerId,
    String status, {
    String? withdrawReason,
  }) async {
    responses.add(status);
  }

  @override
  Future<List<TransportDestination>> hospitalsNear(double lat, double lng) async =>
      destinations;

  @override
  Future<TransportDestination?> facility(String id) async {
    for (final d in destinations) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Future<void> startTransport(
    String offerId, {
    required String destinationId,
    required String destinationName,
  }) async {
    transportStarts.add((destinationId, destinationName));
  }

  @override
  Future<void> arriveAtHospital(String offerId) async {
    hospitalArrivals++;
  }

  @override
  Future<void> requestMoreUnits(
    String offerId, {
    required String role,
    required int count,
    String note = '',
  }) async {
    moreUnitRequests++;
  }

  @override
  Future<void> saveNote(String offerId, String note) async {
    savedNotes.add(note);
  }
}

Offer _offer({
  String status = 'accepted',
  List<String> needs = const ['medical_transport'],
  String role = 'medical_transport',
  TransportLeg? transport,
  MoreUnitsRequest? moreUnits,
  Map<String, DateTime> offerTimes = const {},
  bool? callerFeedbackSafe,
  DateTime? respondedAt,
}) {
  final now = DateTime(2026, 10, 29, 12);
  return Offer(
    id: 'incident-1_responder-1',
    incidentId: 'incident-1',
    incidentCode: 'test-incident',
    responderId: 'responder-1',
    role: role,
    status: status,
    priority: 'High',
    category: 'Medical Emergency',
    subtype: null,
    distanceKm: 2.4,
    latitude: -1.2921,
    longitude: 36.8219,
    flags: const ['Heavy bleeding reported'],
    needs: needs,
    peopleCount: 1,
    wave: 1,
    summary: 'Medical emergency',
    confidential: false,
    freeText: '',
    expiresAt: now.add(const Duration(seconds: 45)),
    createdAt: now,
    respondedAt: respondedAt,
    residentFirstName: 'Test',
    residentPhone: '+254700000000',
    withdrawReason: null,
    transport: transport,
    moreUnits: moreUnits,
    offerTimes: offerTimes,
    callerFeedbackSafe: callerFeedbackSafe,
  );
}

Future<_JobRepository> _pump(WidgetTester tester, Offer offer) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _JobRepository();
  addTearDown(repo.offers.close);
  addTearDown(repo.messages.close);
  await tester.pumpWidget(
    MaterialApp(
      home: ActiveJobScreen(offerId: offer.id, repo: repo),
    ),
  );
  repo.offers.add(offer);
  await tester.pump();
  repo.messages.add(const []);
  await tester.pump();
  return repo;
}

Future<void> _emit(WidgetTester tester, _JobRepository repo, Offer offer) async {
  repo.offers.add(offer);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('transport is not offered before Arrived', (tester) async {
    await _pump(tester, _offer(status: 'accepted'));
    expect(find.text('Start transport'), findsNothing);
    expect(find.text("I'm on my way"), findsOneWidget);
  });

  testWidgets('Arrived on a transport job: choose a destination, then drive, then arrive', (
    tester,
  ) async {
    final repo = await _pump(tester, _offer(status: 'arrived'));
    expect(find.text('Start transport'), findsOneWidget);

    // Dismissing the picker writes nothing: a destination is required.
    await tester.ensureVisible(find.text('Start transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start transport'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you taking them?'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(repo.transportStarts, isEmpty);

    await tester.ensureVisible(find.text('Start transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start transport'));
    await tester.pumpAndSettle();
    expect(find.text('Aga Khan Hospital'), findsOneWidget);
    expect(find.text('Westlands Clinic'), findsOneWidget);
    await tester.tap(find.text('Aga Khan Hospital'));
    await tester.pumpAndSettle();
    expect(repo.transportStarts, [('hosp-a', 'Aga Khan Hospital')]);

    await _emit(
      tester,
      repo,
      _offer(
        status: 'arrived',
        transport: TransportLeg(
          destinationId: 'hosp-a',
          destinationName: 'Aga Khan Hospital',
          startedAt: DateTime(2026, 10, 29, 12, 6),
        ),
      ),
    );
    expect(find.text('TRANSPORTING TO'), findsOneWidget);
    expect(find.text('I have arrived at the hospital'), findsOneWidget);

    await tester.ensureVisible(find.text('I have arrived at the hospital'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I have arrived at the hospital'));
    await tester.pumpAndSettle();
    expect(repo.hospitalArrivals, 1);
  });

  testWidgets('an Arrived job without a transport need only offers Complete', (
    tester,
  ) async {
    await _pump(
      tester,
      _offer(status: 'arrived', needs: const ['fire_suppression'], role: 'fire_suppression'),
    );
    expect(find.text('Start transport'), findsNothing);
    expect(find.text('Complete job'), findsOneWidget);
  });

  testWidgets('the completion summary shows each leg and the caller answer', (
    tester,
  ) async {
    final t0 = DateTime(2026, 10, 29, 12);
    await _pump(
      tester,
      _offer(
        status: 'completed',
        respondedAt: DateTime(2026, 10, 29, 12, 10),
        offerTimes: {
          'accepted': t0.add(const Duration(minutes: 1)),
          'arrived': t0.add(const Duration(minutes: 5)),
          'completed': t0.add(const Duration(minutes: 10)),
        },
        callerFeedbackSafe: true,
      ),
    );
    expect(find.text('RESPONSE TIMES'), findsOneWidget);
    expect(find.text('1 min 0 s'), findsOneWidget);
    expect(find.text('4 min 0 s'), findsOneWidget);
    expect(find.text('5 min 0 s'), findsOneWidget);
    expect(find.text('Caller confirmed safe'), findsOneWidget);
  });

  testWidgets('old jobs without stored times say Not recorded', (tester) async {
    await _pump(tester, _offer(status: 'completed', respondedAt: null));
    expect(find.text('Not recorded'), findsNWidgets(3));
  });

  testWidgets('notes save when the field loses focus', (tester) async {
    final repo = await _pump(tester, _offer(status: 'accepted'));
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Gate 3, blue gate');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(repo.savedNotes, ['Gate 3, blue gate']);
  });

  testWidgets('more units can be requested once; afterwards the status is shown', (
    tester,
  ) async {
    final repo = await _pump(tester, _offer(status: 'accepted'));
    expect(find.text('Request more units'), findsOneWidget);
    await tester.ensureVisible(find.text('Request more units'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request more units'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(repo.moreUnitRequests, 1);

    final requested = MoreUnitsRequest(
      role: 'law_enforcement',
      count: 2,
      note: '',
      requestedAt: DateTime(2026, 10, 29, 12, 3),
    );
    await _emit(
      tester,
      repo,
      _offer(status: 'accepted', moreUnits: requested),
    );
    expect(find.text('Request more units'), findsNothing);
    expect(
      find.textContaining('You asked dispatch for 2 units'),
      findsWidgets,
    );
    // Let the confirmation snack bar expire so only the card's own line remains.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.text('Dispatch has been asked. Keep working. You will see an update here.'),
      findsOneWidget,
    );
  });
}
