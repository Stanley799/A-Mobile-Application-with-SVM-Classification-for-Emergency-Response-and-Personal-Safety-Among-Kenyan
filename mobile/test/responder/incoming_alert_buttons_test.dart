import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/features/responder/incoming_alert_screen.dart';
import 'package:mobile/features/responder/responder_repository.dart';

class _ResponderRepository extends ResponderRepository {
  _ResponderRepository(this.offer)
    : super(db: FakeFirebaseFirestore(), auth: MockFirebaseAuth());

  final Offer offer;
  final StreamController<Offer?> controller =
      StreamController<Offer?>.broadcast();
  final List<String> responses = [];

  @override
  Stream<Offer?> watchOffer(String id) => controller.stream;

  @override
  Future<void> respond(String offerId, String status, {String? withdrawReason}) async {
    responses.add(status);
  }
}

Offer _offer({required DateTime expiresAt, String status = 'offered'}) => Offer(
  id: 'offer-1',
  incidentId: 'incident-1',
  incidentCode: 'test-incident',
  responderId: 'responder-1',
  role: 'medical_transport',
  status: status,
  priority: 'High',
  category: 'Medical Emergency',
  subtype: null,
  distanceKm: 2.4,
  latitude: -1.29,
  longitude: 36.82,
  flags: const ['Heavy bleeding reported'],
  needs: const ['medical_transport'],
  peopleCount: 2,
  wave: 1,
  summary: 'Medical emergency',
  confidential: false,
  freeText: '',
  expiresAt: expiresAt,
  createdAt: DateTime.now(),
  respondedAt: null,
  residentFirstName: null,
  residentPhone: null,
  withdrawReason: null,
);

Future<void> _pumpOffer(WidgetTester tester, Offer offer) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _ResponderRepository(offer);
  addTearDown(repository.controller.close);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(1.3)),
        child: child!,
      ),
      home: IncomingAlertScreen(offer: offer, repo: repository),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('accept and decline are enabled for a live offer', (
    tester,
  ) async {
    await _pumpOffer(
      tester,
      _offer(expiresAt: DateTime.now().add(const Duration(seconds: 45))),
    );

    final accept = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Accept and go'),
    );
    final decline = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Cannot respond'),
    );
    expect(accept.onPressed, isNotNull);
    expect(decline.onPressed, isNotNull);
    expect(find.text('2.4 km'), findsOneWidget);
    expect(find.text('Straight-line distance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accept and decline are disabled when expired', (tester) async {
    await _pumpOffer(
      tester,
      _offer(expiresAt: DateTime.now().subtract(const Duration(seconds: 1))),
    );

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Accept and go'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Cannot respond'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('accept and decline are disabled for a closed offer', (
    tester,
  ) async {
    await _pumpOffer(
      tester,
      _offer(
        status: 'withdrawn',
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Accept and go'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Cannot respond'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
