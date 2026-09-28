import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/resident/screens/sos_confirmation_sheet.dart';
import 'package:mobile/features/resident/widgets/category_chip.dart';
import 'package:mobile/features/resident/widgets/sos_button.dart';

void main() {
  testWidgets('SOS button reports a tap', (tester) async {
    var wasPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SosButton(onPressed: () => wasPressed = true),
          ),
        ),
      ),
    );

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Report Emergency'), findsOneWidget);
    await tester.tap(find.text('SOS'));
    await tester.pump();

    expect(wasPressed, isTrue);
  });

  testWidgets('category chips fit narrow and standard grid cells', (tester) async {
    const categories = [
      ('Medical\nEmergency', Icons.medical_services, AppColors.medicalBg, AppColors.medicalFg),
      ('Road\nAccident', Icons.directions_car, AppColors.roadBg, AppColors.roadFg),
      ('Fire &\nRescue', Icons.local_fire_department, AppColors.fireBg, AppColors.fireFg),
      ('Security\nThreat', Icons.shield, AppColors.securityBg, AppColors.securityFg),
      ('Abduction', Icons.person_search, AppColors.abductionBg, AppColors.abductionFg),
      ('Other /\nGeneral', Icons.more_horiz, AppColors.otherBg, AppColors.otherFg),
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
                  builder: (context) => const SosConfirmationSheet(
                    category: 'Medical Emergency',
                  ),
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