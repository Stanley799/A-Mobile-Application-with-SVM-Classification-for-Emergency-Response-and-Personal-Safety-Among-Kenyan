import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/models/dispatch_models.dart';
import 'package:mobile/core/triage/triage_schema.dart';
import 'package:mobile/features/resident/map/help_models.dart';
import 'package:mobile/features/resident/map/help_repository.dart';
import 'package:mobile/features/resident/screens/sos_confirmation_sheet.dart';
import 'package:mobile/features/resident/screens/sos_picker_sheet.dart';
import 'package:mobile/features/resident/widgets/alert_status_sheet.dart';
import 'package:mobile/features/resident/widgets/other_free_text_sheet.dart';

class _Repo extends HelpRepository {
  _Repo(String category)
    : _category = category,
      super(db: FakeFirebaseFirestore());

  final String _category;

  @override
  Stream<IncidentInfo> watchIncident(String incidentId) =>
      Stream<IncidentInfo>.value(IncidentInfo(category: _category, status: 'Active'));

  @override
  Stream<HelpState> watchOptions(String incidentId) =>
      Stream<HelpState>.value(const HelpState(loaded: true));
}

/// Opens [sheet] the way the app does and records what it pops.
Future<void> _open(
  WidgetTester tester,
  Widget sheet,
  void Function(Object?) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final r = await showModalBottomSheet<Object?>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => sheet,
              );
              onResult(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('SOS picker data', () {
    test('five categories, all real, no Other / General', () {
      expect(kSosPickerCategories.length, 5);
      expect(kSosPickerCategories, isNot(contains('Other / General')));
      for (final c in kSosPickerCategories) {
        expect(kCategories, contains(c));
      }
    });

    test('every picker category has exactly 3 quick questions that exist', () {
      for (final c in kSosPickerCategories) {
        final ids = kQuickQuestions[c]!;
        expect(ids.length, 3, reason: c);
        for (final id in ids) {
          expect(kQuestions[id], isNotNull, reason: '$c / $id');
          expect(kQuestions[id]!.askIf, isEmpty, reason: '$c / $id');
        }
      }
    });
  });

  group('Send alert confirmation', () {
    testWidgets('asks first and does not close by itself', (tester) async {
      Object? result = 'unset';
      await _open(
        tester,
        const SosConfirmationSheet(category: 'Road Accident'),
        (r) => result = r,
      );
      expect(find.text('Send alert for Road Accident?'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Send alert for Road Accident?'), findsOneWidget);
      expect(result, 'unset');
    });

    testWidgets('Send alert returns true', (tester) async {
      Object? result;
      await _open(
        tester,
        const SosConfirmationSheet(category: 'Fire & Rescue'),
        (r) => result = r,
      );
      await tester.tap(find.byKey(const ValueKey('sos-confirm-send')));
      await tester.pumpAndSettle();
      expect(result, true);
    });

    testWidgets('Cancel returns false', (tester) async {
      Object? result;
      await _open(
        tester,
        const SosConfirmationSheet(category: 'Fire & Rescue'),
        (r) => result = r,
      );
      await tester.tap(find.byKey(const ValueKey('sos-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(result, false);
    });
  });

  group('SOS picker', () {
    testWidgets('shows 5 category buttons and the description box, no Other', (
      tester,
    ) async {
      await _open(tester, const SosPickerSheet(), (_) {});
      for (final c in kSosPickerCategories) {
        expect(find.byKey(ValueKey('sos-cat-$c')), findsOneWidget, reason: c);
      }
      expect(find.byKey(const ValueKey('sos-cat-Other / General')), findsNothing);
      expect(find.byType(FreeTextStep), findsOneWidget);
    });

    testWidgets('tapping a category returns it, with no description', (
      tester,
    ) async {
      Object? result;
      await _open(tester, const SosPickerSheet(), (r) => result = r);
      await tester.tap(find.byKey(const ValueKey('sos-cat-Road Accident')));
      await tester.pumpAndSettle();
      expect(result, isA<SosChoice>());
      expect((result as SosChoice).category, 'Road Accident');
      expect((result as SosChoice).description, isNull);
    });
  });

  group('Typed description opens the right question', () {
    testWidgets('Security Threat chosen from text starts its quick questions', (tester) async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('incidents').doc('INC-2');
      await ref.set({'userId': 'u1', 'category': 'Security Threat', 'status': 'Active'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertStatusSheet(
              incidentRef: ref,
              repo: _Repo('Security Threat'),
              dispatch: Stream<DispatchInfo>.value(DispatchInfo.empty),
              createFuture: Future<void>.value(),
              retryCreate: () async {},
              category: 'Security Threat',
              locationShared: false,
              initialDescription: const FreeTextResult(
                text: 'men with a panga outside my gate',
                consent: false,
                chosenCategory: 'Security Threat',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final first = kQuestions[kQuickQuestions['Security Threat']!.first]!.prompt;
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text(first), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
