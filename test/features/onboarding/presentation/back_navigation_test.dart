import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/onboarding/presentation/app_tutorial_screen.dart';
import 'package:homewallet/features/onboarding/presentation/welcome_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('system back moves to the previous welcome page', (tester) async {
    await pumpScreen(tester, WelcomeScreen(onFinished: () async {}));
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Ahorren para lo que importa'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Toma el control de tu espacio'), findsOneWidget);
  });

  testWidgets('system back moves to the previous tutorial step', (
    tester,
  ) async {
    await pumpScreen(tester, AppTutorialScreen(onFinished: () async {}));
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 5'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('1 de 5'), findsOneWidget);
  });
}
