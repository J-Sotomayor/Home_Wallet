import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/app/theme/app_theme.dart';
import 'package:homewallet/features/auth/data/auth_repository.dart';
import 'package:homewallet/features/auth/presentation/auth_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRegistration(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RegisterScreen(repository: _FakeAuthRepository(), onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAuthFlow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthFlow(repository: _FakeAuthRepository()),
      ),
    );
    await tester.pumpAndSettle();
  }

  EditableText editableText(WidgetTester tester, Finder field) {
    return tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
  }

  testWidgets('registration passwords can be shown and hidden', (tester) async {
    await pumpRegistration(tester);
    final password = find.byKey(const Key('register_password'));
    final confirmation = find.byKey(
      const Key('register_password_confirmation'),
    );

    expect(editableText(tester, password).obscureText, isTrue);
    await tester.ensureVisible(password);
    await tester.tap(find.byKey(const Key('register_password_visibility')));
    await tester.pump();
    expect(editableText(tester, password).obscureText, isFalse);

    expect(editableText(tester, confirmation).obscureText, isTrue);
    await tester.ensureVisible(confirmation);
    await tester.tap(find.byKey(const Key('register_confirmation_visibility')));
    await tester.pump();
    expect(editableText(tester, confirmation).obscureText, isFalse);
  });

  testWidgets('password strength reacts to the entered password', (
    tester,
  ) async {
    await pumpRegistration(tester);
    final password = find.byKey(const Key('register_password'));
    await tester.ensureVisible(password);

    expect(
      find.byKey(const Key('register_password_strength_label')),
      findsOneWidget,
    );
    expect(find.text('Sin evaluar'), findsOneWidget);

    await tester.enterText(password, 'abc');
    await tester.pump();
    expect(find.text('Débil'), findsOneWidget);

    await tester.enterText(password, 'Abcdefghij');
    await tester.pump();
    expect(find.text('Media'), findsOneWidget);

    await tester.enterText(password, 'Abcdefghij1');
    await tester.pump();
    expect(find.text('Buena'), findsOneWidget);

    await tester.enterText(password, 'Abcdefghij1!xy');
    await tester.pump();
    expect(find.text('Fuerte'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const Key('register_password_strength')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(progress.value, 1);
  });

  testWidgets('system back returns from registration to login', (tester) async {
    await pumpAuthFlow(tester);
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Crea tu cuenta'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Bienvenida a tu espacio financiero'), findsOneWidget);
  });

  testWidgets('system back returns from recovery to login', (tester) async {
    await pumpAuthFlow(tester);
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Bienvenida a tu espacio financiero'), findsOneWidget);
  });
}

class _FakeAuthRepository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
