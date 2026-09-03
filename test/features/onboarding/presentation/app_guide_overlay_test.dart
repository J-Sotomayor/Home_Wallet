import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/onboarding/presentation/app_tutorial_screen.dart';

void main() {
  testWidgets('contextual guide identifies the step and exposes navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var advanced = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned(
                left: 30,
                top: 90,
                child: SizedBox(width: 160, height: 52),
              ),
              AppGuideOverlay(
                targetRect: const Rect.fromLTWH(30, 90, 160, 52),
                currentStep: 3,
                totalSteps: 9,
                icon: Icons.flag_outlined,
                title: 'Aquí están tus presupuestos y metas',
                description:
                    'Planes reúne los límites mensuales y las metas de ahorro.',
                onPrevious: () {},
                onNext: () => advanced = true,
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PASO 4 DE 9'), findsOneWidget);
    expect(find.text('Aquí están tus presupuestos y metas'), findsOneWidget);
    expect(find.byKey(const Key('guide_previous_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide_next_button')));
    expect(advanced, isTrue);
  });
}
