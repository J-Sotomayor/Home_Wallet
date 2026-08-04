import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/app/services/app_services.dart';
import 'package:homewallet/app/theme/theme_controller.dart';
import 'package:homewallet/app/widgets/homewallet_logo.dart';
import 'package:homewallet/core/security/biometric_lock_service.dart';
import 'package:homewallet/core/security/secure_key_store.dart';
import 'package:homewallet/features/auth/data/auth_repository.dart';
import 'package:homewallet/features/households/data/household_repository.dart';
import 'package:homewallet/features/households/domain/household_models.dart';
import 'package:homewallet/features/households/domain/invitation_payload.dart';
import 'package:homewallet/features/home/presentation/home_shell.dart';
import 'package:homewallet/features/transactions/data/finance_repository.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/main.dart';

void main() {
  late ThemeController themeController;
  late _FakeAuthRepository auth;
  late AppServices services;

  setUp(() {
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

  tearDown(() async {
    await auth.dispose();
  });

  testWidgets('muestra acceso real sin credenciales ni datos demostrativos', (
    tester,
  ) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pump();

    expect(find.byType(HomeWalletLogo), findsOneWidget);
    expect(find.text('Bienvenida a tu hogar financiero'), findsOneWidget);
    final email = tester.widget<TextFormField>(
      find.byKey(const Key('login_email')),
    );
    expect(email.controller?.text, isEmpty);
    expect(find.textContaining('nayhely'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inicia sesión y muestra un hogar vacío por configurar', (
    tester,
  ) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pump();

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
    await tester.pump();

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
    await tester.tap(find.byKey(const Key('verification_continue')));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenida a tu hogar financiero'), findsOneWidget);
    expect(
      find.text('Correo verificado correctamente. Ya puedes iniciar sesión.'),
      findsOneWidget,
    );
  });

  testWidgets('solicita recuperación de contraseña mediante el repositorio', (
    tester,
  ) async {
    await tester.pumpWidget(
      HomeWalletApp(themeController: themeController, services: services),
    );
    await tester.pump();

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

    await tester.tap(find.text('Planes'));
    await tester.pumpAndSettle();

    expect(
      find.text('El avance se calcula automáticamente con tus movimientos.'),
      findsOneWidget,
    );
    expect(find.text('Guardar avance'), findsNothing);
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

    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();

    List<String> visibleCategories() {
      final dropdown = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .firstWhere(
            (widget) =>
                widget.items?.any(
                  (item) =>
                      item.value == 'Alimentación' ||
                      item.value == 'Sueldo' ||
                      item.value == 'Fondo de emergencia',
                ) ??
                false,
          );
      return dropdown.items!.map((item) => item.value!).toList();
    }

    expect(visibleCategories(), contains('Alimentación'));
    expect(visibleCategories(), isNot(contains('Sueldo')));

    await tester.tap(find.text('Ingreso'));
    await tester.pumpAndSettle();
    expect(visibleCategories(), contains('Sueldo'));
    expect(visibleCategories(), isNot(contains('Alimentación')));

    await tester.tap(find.text('Ahorro'));
    await tester.pumpAndSettle();
    expect(visibleCategories(), contains('Fondo de emergencia'));
    expect(visibleCategories(), isNot(contains('Sueldo')));
  });
}

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  String? lastLoginEmail;
  String? lastRecoveryEmail;
  bool googleSignInCalled = false;
  bool verificationResult = false;

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
  Future<void> sendEmailVerification() async {}

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
          role: 'owner',
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
    required FinanceTransaction transaction,
    required String participantUid,
  }) async {}
}

class _UnsupportedAuthenticator implements DeviceAuthenticator {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isSupported() async => false;
}
