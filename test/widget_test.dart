import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/app/services/app_services.dart';
import 'package:homewallet/app/theme/theme_controller.dart';
import 'package:homewallet/app/theme/app_theme.dart';
import 'package:homewallet/app/widgets/homewallet_logo.dart';
import 'package:homewallet/core/security/biometric_lock_service.dart';
import 'package:homewallet/core/security/secure_key_store.dart';
import 'package:homewallet/features/auth/data/auth_repository.dart';
import 'package:homewallet/features/households/data/household_repository.dart';
import 'package:homewallet/features/households/domain/household_models.dart';
import 'package:homewallet/features/households/domain/invitation_payload.dart';
import 'package:homewallet/features/households/presentation/household_setup_screen.dart';
import 'package:homewallet/features/home/presentation/home_shell.dart';
import 'package:homewallet/features/onboarding/presentation/category_setup_screen.dart';
import 'package:homewallet/features/transactions/data/finance_repository.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/presentation/finance_reports_tab.dart';
import 'package:homewallet/features/transactions/presentation/recurring_transactions_screen.dart';
import 'package:homewallet/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ThemeController themeController;
  late _FakeAuthRepository auth;
  late AppServices services;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'welcome.completed.v1': true,
      'tutorial.completed.v1.user-12345678': true,
      'tutorial.completed.v1.junior-12345678': true,
    });
    themeController = ThemeController.memory(mode: ThemeMode.light);
    auth = _FakeAuthRepository();
    final keyStore = MemorySecureKeyStore();
    services = AppServices(
      auth: auth,
      households: _FakeHouseholdRepository(),
      finance: _FakeFinanceRepository(),
      biometricLock: BiometricLockService(
        keyStore: keyStore,
        authenticator: _UnsupportedAuthenticator(),
      ),
    );
  });

  testWidgets('muestra la bienvenida en la primera instalación', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    expect(find.text('Toma el control en familia'), findsOneWidget);
    expect(find.text('Siguiente'), findsOneWidget);
    expect(find.text('Saltar'), findsOneWidget);
  });

  tearDown(() async {
    await auth.dispose();
  });

  testWidgets('muestra acceso real sin credenciales ni datos demostrativos', (
    tester,
  ) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeWalletLogo), findsOneWidget);
    expect(find.text('Bienvenida a tu hogar financiero'), findsOneWidget);
    final email = tester.widget<TextFormField>(
      find.byKey(const Key('login_email')),
    );
    expect(email.controller?.text, isEmpty);
    expect(find.textContaining('nayhely'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el usuario nuevo elige categorías antes de crear su hogar', (
    tester,
  ) async {
    const user = AuthUser(
      uid: 'new-user',
      email: 'nuevo@example.com',
      displayName: 'Persona nueva',
      emailVerified: true,
      needsOnboarding: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CategorySetupScreen(
          user: user,
          repository: auth,
          onSignOut: () async {},
        ),
      ),
    );

    expect(find.text('¿Qué quieres organizar?'), findsOneWidget);
    expect(find.text('Luz'), findsOneWidget);
    expect(find.text('Agua'), findsOneWidget);
    expect(find.text('Internet'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('finish_category_setup')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('finish_category_setup')));
    await tester.pumpAndSettle();

    expect(
      auth.lastPreferredCategories,
      containsAll(['Luz', 'Agua', 'Internet']),
    );
  });

  testWidgets('inicia sesión y muestra un hogar vacío por configurar', (
    tester,
  ) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login_email')),
      'persona@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      'ClaveSegura123',
    );
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(auth.lastLoginEmail, 'persona@example.com');
    expect(find.text('Configura tu hogar'), findsOneWidget);
    expect(find.textContaining('datos de demostración'), findsOneWidget);
  });

  testWidgets('permite acceder o crear la cuenta con Google', (tester) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_google')), findsOneWidget);
    await tester.tap(find.byKey(const Key('login_google')));
    await tester.pumpAndSettle();

    expect(auth.googleSignInCalled, isTrue);
    expect(find.text('Configura tu hogar'), findsOneWidget);
  });

  testWidgets('confirma el correo verificado y regresa al inicio de sesión', (
    tester,
  ) async {
    auth.seedUnverifiedUser();
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verifica tu correo'), findsOneWidget);
    auth.verificationResult = true;
    await tester.ensureVisible(find.byKey(const Key('verification_continue')));
    await tester.tap(find.byKey(const Key('verification_continue')));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenida a tu hogar financiero'), findsOneWidget);
    expect(
      find.text('Correo verificado correctamente. Ya puedes iniciar sesión.'),
      findsOneWidget,
    );
  });

  testWidgets('reenviar verificación conserva visibles todas las acciones', (
    tester,
  ) async {
    auth.seedUnverifiedUser();
    auth.verificationSendCompleter = Completer<void>();
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('verification_resend')));
    await tester.tap(find.byKey(const Key('verification_resend')));
    await tester.pump();

    expect(find.text('Enviando…'), findsOneWidget);
    expect(find.byKey(const Key('verification_continue')), findsOneWidget);
    expect(find.byKey(const Key('verification_other_account')), findsOneWidget);

    auth.verificationSendCompleter!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(auth.verificationEmailsSent, 1);
    expect(find.textContaining('Nuevo enlace enviado'), findsOneWidget);
    expect(find.textContaining('Podrás reenviar en'), findsOneWidget);
    expect(find.text('Usar otra cuenta'), findsOneWidget);
  });

  testWidgets('crear hogar abre el tutorial y termina en Inicio sin regresar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'welcome.completed.v1': true});
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login_email')),
      'hogar@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      'ClaveSegura123',
    );
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Configura tu hogar'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('household_name')),
      'Familia de prueba',
    );
    await tester.ensureVisible(find.byKey(const Key('create_household')));
    await tester.tap(find.byKey(const Key('create_household')));
    await tester.pumpAndSettle();

    expect(find.text('Conoce HomeWallet'), findsOneWidget);
    expect(find.text('Configura tu hogar'), findsNothing);
    await tester.tap(find.text('Saltar'));
    await tester.pumpAndSettle();

    expect(find.text('Disponible para usar'), findsOneWidget);
    expect(find.text('Configura tu hogar'), findsNothing);
  });

  testWidgets(
    'el formulario del hogar mantiene contraste en pantalla angosta',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: HouseholdSetupScreen(
            user: const AuthUser(
              uid: 'contrast-user',
              email: 'contraste@example.com',
              displayName: 'Persona',
              emailVerified: true,
            ),
            repository: _FakeHouseholdRepository(),
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('household_name')),
        'Familia González',
      );
      await tester.pump();

      final decorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const Key('household_name')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(decorator.decoration.labelText, isNull);
      expect(decorator.decoration.counterStyle?.color, isNot(Colors.white));
      expect(find.text('Nombre del hogar'), findsOneWidget);
      expect(find.text('Tipo de hogar'), findsOneWidget);
      expect(find.text('Familia González'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('solicita recuperación de contraseña mediante el repositorio', (
    tester,
  ) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recovery_email')),
      'persona@example.com',
    );
    await tester.tap(find.byKey(const Key('recovery_submit')));
    await tester.pumpAndSettle();

    expect(auth.lastRecoveryEmail, 'persona@example.com');
    expect(find.textContaining('Si existe una cuenta'), findsOneWidget);
  });

  testWidgets('calcula el avance del presupuesto sin edición manual', (
    tester,
  ) async {
    final user = const AuthUser(
      uid: 'user-12345678',
      email: 'persona@example.com',
      displayName: 'Persona de prueba',
      emailVerified: true,
    );
    final finance = _FakeFinanceRepository(
      plans: const [
        FinancePlan(
          id: 'plan-1',
          name: 'Vacaciones',
          kind: FinancePlanKind.budget,
          targetMinor: 100000,
          currentMinor: 25000,
          createdBy: 'user-12345678',
        ),
      ],
      transactions: [
        FinanceTransaction(
          id: 'transaction-1',
          description: 'Comida',
          category: 'Alimentación',
          amountMinor: 15000,
          occurredAt: DateTime.now(),
          type: TransactionType.expense,
          createdBy: 'user-12345678',
          shared: true,
        ),
      ],
    );
    final directServices = AppServices(
      auth: auth,
      households: _FakeHouseholdRepository(),
      finance: finance,
      biometricLock: services.biometricLock,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          user: user,
          householdId: 'household-1',
          services: directServices,
          themeController: themeController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disponible para usar'), findsOneWidget);
    expect(find.byKey(const Key('dashboard_add_expense')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_add_income')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_add_saving')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_tool_recurring')), findsOneWidget);
    expect(find.byKey(const Key('home_tool_shared')), findsOneWidget);
    expect(find.byKey(const Key('home_tool_import')), findsOneWidget);
    expect(find.byKey(const Key('home_tool_family')), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Más'), findsNothing);
    expect(find.text('Invitar'), findsOneWidget);

    await tester.tap(find.text('Planes'));
    await tester.pumpAndSettle();

    expect(find.text('Cómo se actualiza'), findsOneWidget);
    expect(
      find.text('Miden gastos, no ingresos. Se reinician cada mes.'),
      findsOneWidget,
    );
    expect(find.text('Guardar avance'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'muestra metas reales y bloquea categoría al asignar el ingreso',
    (tester) async {
      const user = AuthUser(
        uid: 'user-12345678',
        email: 'persona@example.com',
        displayName: 'Persona de prueba',
        emailVerified: true,
      );
      final finance = _FakeFinanceRepository(
        plans: [
          FinancePlan(
            id: 'goal-1',
            name: 'Vacaciones al Caribe',
            kind: FinancePlanKind.goal,
            targetMinor: 100000,
            currentMinor: 10000,
            createdBy: user.uid,
            deadline: DateTime.now().add(const Duration(days: 90)),
          ),
        ],
      );
      final directServices = AppServices(
        auth: auth,
        households: _FakeHouseholdRepository(),
        finance: finance,
        biometricLock: services.biometricLock,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomeShell(
            user: user,
            householdId: 'household-1',
            services: directServices,
            themeController: themeController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dashboard_add_income')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('transaction_goal')), findsOneWidget);
      await tester.tap(find.byKey(const Key('transaction_goal')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Vacaciones al Caribe ·').last);
      await tester.pumpAndSettle();

      final category = tester.widget<InkWell>(
        find.byKey(const Key('transaction_category')),
      );
      expect(category.onTap, isNull);
      expect(find.text('Definida por la meta seleccionada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('muestra una experiencia educativa al Integrante Jr', (
    tester,
  ) async {
    const user = AuthUser(
      uid: 'junior-12345678',
      email: 'joven@example.com',
      displayName: 'Integrante joven',
      emailVerified: true,
    );
    final finance = _FakeFinanceRepository(
      plans: [
        FinancePlan(
          id: 'goal-jr',
          name: 'Computadora familiar',
          kind: FinancePlanKind.goal,
          targetMinor: 100000,
          currentMinor: 50000,
          createdBy: 'adult',
          deadline: DateTime.now().add(const Duration(days: 120)),
        ),
      ],
    );
    final juniorServices = AppServices(
      auth: auth,
      households: _FakeHouseholdRepository(role: 'junior'),
      finance: finance,
      biometricLock: services.biometricLock,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          user: user,
          householdId: 'household-1',
          services: juniorServices,
          themeController: themeController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Mi familia'), findsOneWidget);
    expect(find.text('Invitar'), findsNothing);

    await tester.tap(find.text('Planes'));
    await tester.pumpAndSettle();

    expect(find.text('Objetivos de nuestro hogar'), findsOneWidget);
    expect(find.textContaining('Aprender a ahorrar'), findsOneWidget);
    expect(find.text('Computadora familiar'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.textContaining('Vista de Integrante Jr'), findsOneWidget);
    expect(find.text('Agregar dinero a la meta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explica y organiza una programación recurrente por pasos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecurringTransactionsScreen(
          householdId: 'household-1',
          uid: 'user-12345678',
          repository: services.finance,
          canContribute: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Automatiza lo que se repite'), findsOneWidget);
    expect(find.text('Aún no tienes programaciones'), findsOneWidget);
    expect(find.text('Arriendo'), findsOneWidget);
    expect(find.text('Sueldo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new_recurring')));
    await tester.pumpAndSettle();

    expect(find.text('Nueva programación'), findsOneWidget);
    expect(find.text('1. ¿Qué se repetirá?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recurring_type_income')));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué ingreso se repetirá?'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('2. ¿Cuándo se repite?'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('3. Al llegar la fecha'), findsOneWidget);
    expect(find.text('Avisarme antes de registrarlo'), findsOneWidget);
    expect(find.text('Registrar automáticamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exporta desde reportes y permite separar datos importados', (
    tester,
  ) async {
    final now = DateTime.now();
    final finance = _FakeFinanceRepository(
      transactions: [
        FinanceTransaction(
          id: 'manual-1',
          description: 'Mercado',
          category: 'Alimentación',
          amountMinor: 2500,
          occurredAt: now,
          type: TransactionType.expense,
          createdBy: 'user-12345678',
          shared: false,
        ),
        FinanceTransaction(
          id: 'imported-1',
          description: 'Pago bancario',
          category: 'Servicios',
          amountMinor: 1800,
          occurredAt: now,
          type: TransactionType.expense,
          createdBy: 'user-12345678',
          shared: false,
          origin: TransactionOrigin.imported,
          sourceName: 'Banco Pichincha · PDF',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceReportsTab(
            householdId: 'household-1',
            repository: finance,
            members: Stream.value(const [
              HouseholdMember(
                uid: 'user-12345678',
                displayName: 'Persona',
                role: 'owner',
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Descargar este reporte'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('open_report_export')));
    await tester.tap(find.byKey(const Key('open_report_export')));
    await tester.pumpAndSettle();

    expect(find.text('Registrados en HomeWallet'), findsOneWidget);
    expect(find.text('Solo importados'), findsOneWidget);
    expect(find.text('Todos los movimientos'), findsOneWidget);
    expect(find.text('Se exportará 1 movimiento.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export_scope_all')));
    await tester.pump();
    expect(find.text('Se exportarán 2 movimientos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reportes adapta filtros sin desbordarse en teléfonos angostos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final finance = _FakeFinanceRepository(
      transactions: [
        FinanceTransaction(
          id: 'narrow-1',
          description: 'Planilla de energía eléctrica',
          category: 'Servicios básicos del hogar con nombre largo',
          amountMinor: 1800,
          occurredAt: DateTime.now(),
          type: TransactionType.expense,
          createdBy: 'member-long',
          shared: false,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceReportsTab(
            householdId: 'household-1',
            repository: finance,
            members: Stream.value(const [
              HouseholdMember(
                uid: 'member-long',
                displayName: 'Integrante con un nombre especialmente largo',
                role: 'member',
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Categoría'), findsOneWidget);
    expect(find.text('Integrante'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separa las categorías de gastos, ingresos y ahorros', (
    tester,
  ) async {
    const user = AuthUser(
      uid: 'user-12345678',
      email: 'persona@example.com',
      displayName: 'Persona de prueba',
      emailVerified: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          user: user,
          householdId: 'household-1',
          services: services,
          themeController: themeController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Movimientos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();

    expect(find.text('¿Qué quieres registrar?'), findsOneWidget);
    expect(find.byKey(const Key('movement_type_expense')), findsOneWidget);
    expect(find.byKey(const Key('movement_type_income')), findsOneWidget);
    expect(find.byKey(const Key('movement_type_saving')), findsOneWidget);

    await tester.tap(find.byKey(const Key('movement_type_expense')));
    await tester.pumpAndSettle();

    Future<void> expectCategories({
      required String present,
      required String absent,
    }) async {
      await tester.ensureVisible(find.byKey(const Key('transaction_category')));
      await tester.tap(find.byKey(const Key('transaction_category')));
      await tester.pumpAndSettle();
      expect(find.text('Elige una categoría'), findsOneWidget);
      expect(find.text('Buscar categoría'), findsOneWidget);
      expect(find.text(present), findsWidgets);
      expect(find.text(absent), findsNothing);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
    }

    await expectCategories(present: 'Alimentación', absent: 'Sueldo');

    await tester.ensureVisible(find.byKey(const Key('transaction_date')));
    await tester.tap(find.byKey(const Key('transaction_date')));
    await tester.pumpAndSettle();
    expect(find.text('¿Cuándo ocurrió?'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('Elegir otra fecha'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('movement_type_income')));
    await tester.pumpAndSettle();
    await expectCategories(present: 'Sueldo', absent: 'Alimentación');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('movement_type_saving')));
    await tester.tap(find.byKey(const Key('movement_type_saving')));
    await tester.pumpAndSettle();
    await expectCategories(present: 'Fondo de emergencia', absent: 'Sueldo');
  });

  testWidgets('muestra resumen y trazabilidad antes de editar un movimiento', (
    tester,
  ) async {
    const user = AuthUser(
      uid: 'user-12345678',
      email: 'persona@example.com',
      displayName: 'Persona de prueba',
      emailVerified: true,
    );
    final finance = _FakeFinanceRepository(
      transactions: [
        FinanceTransaction(
          id: 'movement-1',
          description: 'Mercado del barrio',
          category: 'Alimentación',
          amountMinor: 2750,
          occurredAt: DateTime.now(),
          type: TransactionType.expense,
          createdBy: user.uid,
          shared: false,
        ),
      ],
    );
    final directServices = AppServices(
      auth: auth,
      households: _FakeHouseholdRepository(),
      finance: finance,
      biometricLock: services.biometricLock,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          user: user,
          householdId: 'household-1',
          services: directServices,
          themeController: themeController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Movimientos').last);
    await tester.pumpAndSettle();
    expect(find.text('Resultado del filtro'), findsOneWidget);
    expect(find.text('1 registro'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mercado del barrio'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del movimiento'), findsOneWidget);
    expect(find.text('Registrado en HomeWallet'), findsOneWidget);
    expect(
      find.textContaining('no sustituye un comprobante bancario'),
      findsOneWidget,
    );
    expect(find.text('Editar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  String? lastLoginEmail;
  String? lastRecoveryEmail;
  bool googleSignInCalled = false;
  bool verificationResult = false;
  int verificationEmailsSent = 0;
  Completer<void>? verificationSendCompleter;
  List<String>? lastPreferredCategories;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> watchUser() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastLoginEmail = email;
    _user = AuthUser(
      uid: 'user-12345678',
      email: email,
      displayName: 'Persona de prueba',
      emailVerified: true,
    );
    _controller.add(_user);
  }

  @override
  Future<void> signInWithGoogle() async {
    googleSignInCalled = true;
    _user = const AuthUser(
      uid: 'google-user-12345678',
      email: 'persona@gmail.com',
      displayName: 'Persona de Google',
      emailVerified: true,
    );
    _controller.add(_user);
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    _user = AuthUser(
      uid: 'user-12345678',
      email: email,
      displayName: displayName,
      emailVerified: false,
    );
    _controller.add(_user);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    lastRecoveryEmail = email;
  }

  @override
  Future<void> sendEmailVerification() async {
    verificationEmailsSent++;
    await verificationSendCompleter?.future;
  }

  @override
  Future<bool> reloadEmailVerification() async => verificationResult;

  void seedUnverifiedUser() {
    _user = const AuthUser(
      uid: 'unverified-user-12345678',
      email: 'pendiente@example.com',
      displayName: 'Persona pendiente',
      emailVerified: false,
    );
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    required String phoneNumber,
    Uint8List? photoBytes,
    String? photoExtension,
  }) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> acceptTerms() async {}

  @override
  Future<void> completeOnboarding(List<String> preferredCategories) async {
    lastPreferredCategories = preferredCategories;
  }

  @override
  Future<void> updatePreferredCategories(
    List<String> preferredCategories,
  ) async {
    lastPreferredCategories = preferredCategories;
  }

  @override
  Future<DateTime> requestAccountDeletion() async =>
      DateTime.now().add(const Duration(days: 3));

  @override
  Future<void> cancelAccountDeletion() async {}

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}

class _FakeHouseholdRepository implements HouseholdRepository {
  _FakeHouseholdRepository({this.role = 'owner'});

  final String role;

  @override
  Future<String> acceptInvitation(
    String rawPayload,
    AuthUser user, {
    HouseholdRole requestedRole = HouseholdRole.member,
  }) async => 'household-12345678';

  @override
  Future<String> createHousehold(
    String name,
    AuthUser user, {
    HouseholdKind kind = HouseholdKind.family,
  }) async => 'household-12345678';

  @override
  Future<void> updateMemberRole({
    required String householdId,
    required String memberId,
    required HouseholdRole role,
  }) async {}

  @override
  Future<void> removeMember({
    required String householdId,
    required String memberId,
  }) async {}

  @override
  Future<void> leaveHousehold(String householdId) async {}

  @override
  Future<InvitationPayload> createInvitation(String householdId) =>
      throw UnimplementedError();

  @override
  Future<bool> hasKey(String householdId) async => true;

  @override
  Future<void> setActiveHousehold(String uid, String householdId) async {}

  @override
  Future<void> updateMemberDisplayName({
    required String householdId,
    required String uid,
    required String displayName,
  }) async {}

  @override
  Stream<String?> watchActiveHouseholdId(String uid) => Stream.value(null);

  @override
  Stream<Household> watchHousehold(String householdId, String uid) =>
      Stream.value(
        Household(
          id: householdId,
          name: 'Hogar de prueba',
          memberCount: 1,
          role: role,
        ),
      );

  @override
  Stream<List<HouseholdMember>> watchMembers(String householdId) =>
      Stream.value(const []);
}

class _FakeFinanceRepository implements FinanceRepository {
  _FakeFinanceRepository({this.plans = const [], this.transactions = const []});

  final List<FinancePlan> plans;
  final List<FinanceTransaction> transactions;

  @override
  Stream<List<FinanceCategory>> watchCategories(String householdId) =>
      Stream.value(const []);

  @override
  Future<void> addCategory({
    required String householdId,
    required String uid,
    required String name,
    required TransactionType type,
  }) async {}

  @override
  Future<void> updateCategory({
    required String householdId,
    required FinanceCategory category,
    required String name,
  }) async {}

  @override
  Future<void> deleteCategory(
    String householdId,
    FinanceCategory category,
  ) async {}

  @override
  Future<void> addPlan({
    required String householdId,
    required String uid,
    required String name,
    required FinancePlanKind kind,
    required int targetMinor,
    String? category,
    DateTime? deadline,
    double alertThreshold = 0.8,
  }) async {}

  @override
  Future<void> addTransaction({
    required String householdId,
    required String uid,
    required String description,
    required String category,
    required int amountMinor,
    required TransactionType type,
    required bool shared,
    DateTime? occurredAt,
    FinancePlan? linkedPlan,
    ExpenseFundingSource fundingSource = ExpenseFundingSource.general,
    String? paidByUid,
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, int> participantSharesMinor = const {},
  }) async {}

  @override
  Future<void> updateTransaction({
    required String householdId,
    required FinanceTransaction original,
    required String description,
    required String category,
    required int amountMinor,
    required DateTime occurredAt,
    required TransactionType type,
    required bool shared,
    FinancePlan? linkedPlan,
    ExpenseFundingSource fundingSource = ExpenseFundingSource.general,
    String? paidByUid,
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, int> participantSharesMinor = const {},
  }) async {}

  @override
  Future<void> addTransactions({
    required String householdId,
    required String uid,
    required List<FinanceTransactionDraft> transactions,
  }) async {}

  @override
  Future<void> deleteTransaction(
    String householdId,
    FinanceTransaction transaction,
  ) async {}

  @override
  Stream<List<FinancePlan>> watchPlans(String householdId) =>
      Stream.value(plans);

  @override
  Stream<List<FinanceTransaction>> watchTransactions(String householdId) =>
      Stream.value(transactions);

  @override
  Stream<List<SharedExpense>> watchSharedExpenses(String householdId) =>
      Stream.value(const []);

  @override
  Future<void> addSharedExpense({
    required String householdId,
    required String uid,
    required SharedExpenseDraft expense,
  }) async {}

  @override
  Stream<List<RecurringTransaction>> watchRecurring(String householdId) =>
      Stream.value(const []);

  @override
  Future<void> addRecurring({
    required String householdId,
    required String uid,
    required FinanceTransactionDraft template,
    required RecurrenceFrequency frequency,
    required DateTime nextDueAt,
    bool confirmBeforePosting = true,
  }) async {}

  @override
  Future<void> updateRecurring({
    required String householdId,
    required RecurringTransaction recurring,
  }) async {}

  @override
  Future<void> deleteRecurring(
    String householdId,
    RecurringTransaction recurring,
  ) async {}

  @override
  Future<void> confirmRecurring({
    required String householdId,
    required String uid,
    required RecurringTransaction recurring,
  }) async {}

  @override
  Future<void> settleSharedParticipant({
    required String householdId,
    required SharedExpense expense,
    required String participantUid,
  }) async {}
}

class _UnsupportedAuthenticator implements DeviceAuthenticator {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isSupported() async => false;
}
