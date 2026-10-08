import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/services/priority_classifier.dart';
import 'package:mobile/core/models/emergency_enums.dart';
import 'package:mobile/features/resident/screens/sos_confirmation_sheet.dart';
import 'package:mobile/features/resident/screens/emergency_active_screen.dart';
import 'package:mobile/features/resident/widgets/category_chip.dart';
import 'package:mobile/features/resident/widgets/other_free_text_sheet.dart';
import 'package:mobile/features/resident/widgets/sos_button.dart';
import 'package:mobile/features/resident/widgets/triage_question_sheet.dart';

void main() {
  testWidgets('triage classifier failure can be retried with answers intact', (
    tester,
  ) async {
    final classifier = _RetryPriorityClassifier();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TriageQuestionSheet(
            category: EmergencyCategory.other,
            classifier: classifier,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Not sure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not sure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('Get Priority Suggestion'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to suggest a priority. Please try again.'),
      findsOneWidget,
    );
    classifier.shouldFail = false;
    await tester.tap(find.text('Get Priority Suggestion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review Answers'));
    await tester.pumpAndSettle();
    expect(find.text('Not sure'), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final category in [
    EmergencyCategory.medical,
    EmergencyCategory.roadAccident,
    EmergencyCategory.fire,
    EmergencyCategory.security,
    EmergencyCategory.abduction,
  ]) {
    testWidgets(
      '${category.label} keeps all answers in the confirmation result',
      (tester) async {
        Map<String, dynamic>? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<Map<String, dynamic>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => TriageQuestionSheet(
                        category: category,
                        classifier: RuleBasedPriorityClassifier(),
                      ),
                    );
                  },
                  child: const Text('Report incident'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Report incident'));
        await tester.pumpAndSettle();
        while (find.text('Confirm & Send').evaluate().isEmpty) {
          if (find.text('Not sure').evaluate().isNotEmpty) {
            await tester.tap(find.text('Not sure'));
          } else {
            await tester.tap(find.text('1'));
            await tester.pump();
            final action = find.text('Next').evaluate().isNotEmpty
                ? find.text('Next')
                : find.text('Get Priority Suggestion');
            await tester.ensureVisible(action);
            await tester.tap(action);
          }
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Confirm & Send'));
        await tester.pumpAndSettle();
        final answers = result!['triageAnswers'] as Map<String, dynamic>;
        expect(answers['conscious'], ConsciousnessStatus.unknown);
        expect(answers['breathing'], BreathingStatus.unknown);
        expect(answers['peopleCount'], 1);
        final expectedCount = category == EmergencyCategory.abduction ? 4 : 5;
        expect(answers.length, expectedCount);
        expect(result!['suggestion'], isA<PrioritySuggestion>());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'description classifier failure allows retry without losing text',
    (tester) async {
      final classifier = _RetryPriorityClassifier();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OtherFreeTextSheet(classifier: classifier)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Smoke in the house');
      await tester.pump();
      await tester.tap(find.text('Get Help'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to process your description. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Smoke in the house'), findsOneWidget);
      classifier.shouldFail = false;
      await tester.tap(find.text('Get Help'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'description help remains reachable above a keyboard on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => OtherFreeTextSheet(
                    classifier: RuleBasedPriorityClassifier(),
                  ),
                ),
                child: const Text('Describe incident'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Describe incident'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Smoke in the house');
      await tester.pump();
      await tester.ensureVisible(find.text('Get Help'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Get Help')).dy,
        lessThan(568 - 280),
      );
      await tester.tap(find.text('Get Help'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'alert cancellation ${fails ? 'failure stays active' : 'returns to previous screen'}',
      (tester) async {
        var cancellations = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EmergencyActiveScreen(
                        incidentId: 'test-incident',
                        category: EmergencyCategory.medical,
                        priority: PriorityLevel.high,
                        createdAt: DateTime(2026, 10, 8),
                        cancelIncident: () async {
                          cancellations += 1;
                          if (fails) throw StateError('Update failed');
                        },
                      ),
                    ),
                  ),
                  child: const Text('Dashboard'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel Alert'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep Active'));
        await tester.pumpAndSettle();
        expect(cancellations, 0);
        expect(find.text('Emergency alert sent'), findsOneWidget);
        await tester.tap(find.text('Cancel Alert'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Cancel Alert'));
        await tester.pumpAndSettle();
        expect(cancellations, 1);
        if (fails) {
          expect(find.text('Emergency alert sent'), findsOneWidget);
          expect(
            find.text('Unable to cancel the alert. Please try again.'),
            findsOneWidget,
          );
        } else {
          expect(find.text('Dashboard'), findsOneWidget);
          expect(find.text('Emergency alert sent'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Not sure advances and review retains and edits each answer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TriageQuestionSheet(
            category: EmergencyCategory.medical,
            classifier: RuleBasedPriorityClassifier(),
          ),
        ),
      ),
    );

    expect(find.text('Unknown'), findsNothing);
    for (var question = 0; question < 4; question++) {
      expect(find.text('Question ${question + 1} of 5'), findsOneWidget);
      await tester.tap(find.text('Not sure'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('Get Priority Suggestion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review Answers'));
    await tester.pumpAndSettle();
    expect(find.text('Not sure'), findsNWidgets(4));
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit answer').first);
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((widget) => widget.properties.selected == true);
    expect(selected.length, 1);
    await tester.tap(find.text('No'));
    await tester.pump();
    await tester.tap(find.text('Save Answer'));
    await tester.pumpAndSettle();
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Not sure'), findsNWidgets(3));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('High priority'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'incident description enables help and preserves text for review',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtherFreeTextSheet(classifier: RuleBasedPriorityClassifier()),
          ),
        ),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(
        find.byType(TextField),
        'There is smoke in the house',
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Get Help'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & Send'), findsOneWidget);
      await tester.tap(find.text('Edit Description'));
      await tester.pumpAndSettle();
      expect(find.text('There is smoke in the house'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SOS button reports a tap', (tester) async {
    var wasPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SosButton(onPressed: () => wasPressed = true)),
        ),
      ),
    );

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Report Emergency'), findsOneWidget);
    await tester.tap(find.text('SOS'));
    await tester.pump();

    expect(wasPressed, isTrue);
  });

  testWidgets('category chips fit narrow and standard grid cells', (
    tester,
  ) async {
    const categories = [
      (
        'Medical\nEmergency',
        Icons.medical_services,
        AppColors.medicalBg,
        AppColors.medicalFg,
      ),
      (
        'Road\nAccident',
        Icons.directions_car,
        AppColors.roadBg,
        AppColors.roadFg,
      ),
      (
        'Fire &\nRescue',
        Icons.local_fire_department,
        AppColors.fireBg,
        AppColors.fireFg,
      ),
      (
        'Security\nThreat',
        Icons.shield,
        AppColors.securityBg,
        AppColors.securityFg,
      ),
      (
        'Abduction',
        Icons.person_search,
        AppColors.abductionBg,
        AppColors.abductionFg,
      ),
      (
        'Other /\nGeneral',
        Icons.more_horiz,
        AppColors.otherBg,
        AppColors.otherFg,
      ),
    ];

    for (final width in [240.0, 400.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 520,
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: width < 360 ? 2 : 3,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 120,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return CategoryChip(
                    label: category.$1,
                    icon: category.$2,
                    background: category.$3,
                    foreground: category.$4,
                    onTap: () {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('SOS confirmation shows category and can be cancelled', (
    tester,
  ) async {
    bool? confirmationResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmationResult = await showModalBottomSheet<bool>(
                  context: context,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (context) =>
                      const SosConfirmationSheet(category: 'Medical Emergency'),
                );
              },
              child: const Text('Open SOS confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open SOS confirmation'));
    await tester.pumpAndSettle();

    expect(find.text('Sending Medical Emergency alert in...'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(confirmationResult, isFalse);
  });
}

class _RetryPriorityClassifier extends RuleBasedPriorityClassifier {
  bool shouldFail = true;

  @override
  Future<PrioritySuggestion> suggestPriority({
    required EmergencyCategory category,
    required ConsciousnessStatus conscious,
    required BreathingStatus breathing,
    required MobilityStatus mobile,
    required bool weaponInvolved,
    required int peopleCount,
    String? freeTextDescription,
  }) async {
    if (shouldFail) throw StateError('Classifier unavailable');
    return super.suggestPriority(
      category: category,
      conscious: conscious,
      breathing: breathing,
      mobile: mobile,
      weaponInvolved: weaponInvolved,
      peopleCount: peopleCount,
      freeTextDescription: freeTextDescription,
    );
  }
}
