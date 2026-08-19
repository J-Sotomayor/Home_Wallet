import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../app/theme/theme_controller.dart';
import '../../../app/widgets/app_page_header.dart';
import '../../../core/errors/app_exception.dart';
import '../../about/presentation/about_homewallet_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../households/data/household_repository.dart';
import '../../households/domain/household_models.dart';
import '../../households/presentation/family_invite_screen.dart';
import '../../households/presentation/household_members_screen.dart';
import '../../households/presentation/household_spaces_screen.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../onboarding/presentation/app_tutorial_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../transactions/domain/transaction_categories.dart';
import '../../transactions/domain/financial_guidance.dart';
import '../../transactions/domain/finance_balances.dart';
import '../../transactions/domain/finance_models.dart';
import '../../transactions/presentation/data_tools_screen.dart';
import '../../transactions/presentation/categories_screen.dart';
import '../../transactions/presentation/finance_insights.dart';
import '../../transactions/presentation/finance_reports_tab.dart';
import '../../transactions/presentation/recurring_transactions_screen.dart';
import '../../transactions/presentation/shared_debts_screen.dart';
import '../../transactions/presentation/savings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.user,
    required this.householdId,
    required this.services,
    required this.themeController,
    required this.onSignOut,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final ThemeController themeController;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  _MovementView _movementView = _MovementView.app;
  bool _tutorialQueued = false;
  bool _hasOpenContentRoute = false;
  final _transactionsKey = GlobalKey<_TransactionsTabState>();
  final _contentNavigatorKey = GlobalKey<NavigatorState>();
  late final NavigatorObserver _contentNavigatorObserver;

  @override
  void initState() {
    super.initState();
    _contentNavigatorObserver = _HomeContentNavigatorObserver(
      _setContentRouteOpen,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startExperience());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Household>(
      stream: widget.services.households.watchHousehold(
        widget.householdId,
        widget.user.uid,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: _StreamError(message: _errorText(snapshot.error)),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final household = snapshot.data!;
        final canContribute = household.canContribute;
        final pages = [
          _DashboardTab(
            user: widget.user,
            householdId: widget.householdId,
            services: widget.services,
            onImportCompleted: _showImportedTransactions,
            onImportCommitted: () => unawaited(_evaluateSmartAlerts()),
            onOpenTransactions: () => _selectDestination(1),
            onOpenPlans: () => _selectDestination(4),
            onOpenSavings: () => _selectDestination(3),
            onOpenProfile: () => _openSettings(household),
            canContribute: canContribute,
            isCollaborative: household.isCollaborative,
          ),
          _TransactionsTab(
            key: _transactionsKey,
            user: widget.user,
            householdId: widget.householdId,
            services: widget.services,
            canContribute: canContribute,
            canManage: household.canManage,
            isCollaborative: household.isCollaborative,
            onViewChanged: (view) {
              if (_movementView != view) {
                setState(() => _movementView = view);
              }
            },
            onEdit:
                (transaction) => _showTransactionForm(
                  context,
                  existing: transaction,
                  isCollaborative: household.isCollaborative,
                ),
          ),
          FinanceReportsTab(
            householdId: widget.householdId,
            repository: widget.services.finance,
            members: widget.services.households.watchMembers(
              widget.householdId,
            ),
            currentUid: widget.user.uid,
            currentUserName: widget.user.displayName,
            householdKind: household.kind,
          ),
          SavingsScreen(
            householdId: widget.householdId,
            repository: widget.services.finance,
            canContribute: canContribute,
            onAddSaving:
                () => _showTransactionForm(
                  context,
                  initialType: TransactionType.saving,
                  isCollaborative: household.isCollaborative,
                ),
            onOpenPlans: () => _selectDestination(4),
          ),
          _PlansTab(
            user: widget.user,
            householdId: widget.householdId,
            services: widget.services,
            canContribute: canContribute,
            role: household.roleType,
            onAddToGoal:
                (plan, type) => _showTransactionForm(
                  context,
                  initialType: type,
                  initialLinkedPlan: plan,
                  isCollaborative: household.isCollaborative,
                ),
            onRecordBudgetExpense:
                (plan) => _showTransactionForm(
                  context,
                  initialType: TransactionType.expense,
                  initialCategory: plan.category,
                  isCollaborative: household.isCollaborative,
                ),
          ),
        ];

        return Scaffold(
          body: Navigator(
            key: _contentNavigatorKey,
            observers: [_contentNavigatorObserver],
            pages: [
              MaterialPage<void>(
                key: const ValueKey('home_content_root'),
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
            onDidRemovePage: (_) {},
          ),
          floatingActionButton:
              canContribute && _index == 1 && !_hasOpenContentRoute
                  ? FloatingActionButton.extended(
                    onPressed:
                        _movementView == _MovementView.bank
                            ? _openBankImport
                            : () => _showTransactionForm(
                              context,
                              isCollaborative: household.isCollaborative,
                            ),
                    icon: Icon(
                      _movementView == _MovementView.bank
                          ? Icons.upload_file_outlined
                          : Icons.add_circle_outline,
                    ),
                    label: Text(
                      _movementView == _MovementView.bank
                          ? 'Importar estado'
                          : 'Registrar',
                    ),
                  )
                  : null,
          bottomNavigationBar: NavigationBar(
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            selectedIndex: _index,
            onDestinationSelected: _selectDestination,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Movs.',
              ),
              NavigationDestination(
                icon: Icon(Icons.query_stats_outlined),
                selectedIcon: Icon(Icons.query_stats),
                label: 'Reportes',
              ),
              NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: 'Ahorros',
              ),
              NavigationDestination(
                icon: Icon(Icons.flag_outlined),
                selectedIcon: Icon(Icons.flag),
                label: 'Planes',
              ),
            ],
          ),
        );
      },
    );
  }

  void _selectDestination(int value) {
    _contentNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (_index != value) setState(() => _index = value);
  }

  void _setContentRouteOpen(bool value) {
    if (!mounted || _hasOpenContentRoute == value) return;
    setState(() => _hasOpenContentRoute = value);
  }

  Future<void> _showTransactionForm(
    BuildContext context, {
    FinanceTransaction? existing,
    TransactionType? initialType,
    FinancePlan? initialLinkedPlan,
    String? initialCategory,
    required bool isCollaborative,
  }) async {
    final selectedType =
        existing?.type ??
        initialType ??
        await showModalBottomSheet<TransactionType>(
          context: context,
          showDragHandle: true,
          builder: (_) => _MovementTypePicker(isCollaborative: isCollaborative),
        );
    if (selectedType == null || !context.mounted) return;
    final input = await showModalBottomSheet<_TransactionInput>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => _TransactionForm(
            plans: widget.services.finance.watchPlans(widget.householdId),
            transactions: widget.services.finance.watchTransactions(
              widget.householdId,
            ),
            customCategories: widget.services.finance.watchCategories(
              widget.householdId,
            ),
            preferredCategories: widget.user.preferredCategories.toSet(),
            initialType: selectedType,
            initialLinkedPlanId: initialLinkedPlan?.id,
            initialCategory: initialCategory,
            existing: existing,
          ),
    );
    if (input == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.services.finance.addTransaction(
          householdId: widget.householdId,
          uid: widget.user.uid,
          description: input.description,
          category: input.category,
          amountMinor: input.amountMinor,
          type: input.type,
          shared: input.shared,
          occurredAt: input.occurredAt,
          linkedPlan: input.linkedPlan,
          fundingSource: input.fundingSource,
          paidByUid: input.paidByUid,
          splitMode: input.splitMode,
          participantSharesMinor: input.participantSharesMinor,
        );
        _showMessage(
          input.linkedPlan == null
              ? 'Movimiento cifrado y guardado. ${input.guidance.title}'
              : '${input.linkedPlan!.name}: avance actualizado con ${_money(input.amountMinor)}.',
        );
      } else {
        await widget.services.finance.updateTransaction(
          householdId: widget.householdId,
          original: existing,
          description: input.description,
          category: input.category,
          amountMinor: input.amountMinor,
          occurredAt: input.occurredAt,
          type: input.type,
          shared: input.shared,
          linkedPlan: input.linkedPlan,
          fundingSource: input.fundingSource,
          paidByUid: input.paidByUid,
          splitMode: input.splitMode,
          participantSharesMinor: input.participantSharesMinor,
        );
        _showMessage('Movimiento actualizado correctamente.');
      }
      unawaited(_evaluateSmartAlerts());
    } on AppException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _showTutorialOnce() async {
    if (_tutorialQueued || !mounted) return;
    _tutorialQueued = true;
    final preferences = await SharedPreferences.getInstance();
    final key = 'tutorial.completed.v1.${widget.user.uid}';
    if (!mounted || preferences.getBool(key) == true) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder:
            (_) => AppTutorialScreen(
              onFinished: () async => preferences.setBool(key, true),
            ),
      ),
    );
  }

  Future<void> _startExperience() async {
    await _showTutorialOnce();
  }

  Future<void> _evaluateSmartAlerts() async {
    final notifications = widget.services.notifications;
    if (notifications == null) return;
    try {
      final values = await Future.wait<Object>([
        widget.services.finance.watchTransactions(widget.householdId).first,
        widget.services.finance.watchPlans(widget.householdId).first,
      ]).timeout(const Duration(seconds: 8));
      await notifications.evaluateSmartAlerts(
        uid: widget.user.uid,
        householdId: widget.householdId,
        transactions:
            (values[0] as List<FinanceTransaction>)
                .where((transaction) => transaction.countsInHouseholdFinances)
                .toList(),
        plans: values[1] as List<FinancePlan>,
      );
    } catch (_) {
      // Las alertas no deben bloquear el guardado del movimiento.
    }
  }

  void _openSettings(Household household) {
    _contentNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder:
            (_) => Scaffold(
              appBar: AppBar(title: const Text('Configuración')),
              body: _ProfileTab(
                user: widget.user,
                householdId: widget.householdId,
                services: widget.services,
                themeController: widget.themeController,
                household: household,
                onSignOut: widget.onSignOut,
              ),
            ),
      ),
    );
  }

  void _showImportedTransactions() {
    _selectDestination(1);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _transactionsKey.currentState?.showImportedOnly(),
    );
  }

  Future<void> _openBankImport() async {
    final imported = await _contentNavigatorKey.currentState?.push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => DataToolsScreen(
              user: widget.user,
              householdId: widget.householdId,
              services: widget.services,
              onImportCommitted: () => unawaited(_evaluateSmartAlerts()),
            ),
      ),
    );
    if (imported == true) _showImportedTransactions();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HomeContentNavigatorObserver extends NavigatorObserver {
  _HomeContentNavigatorObserver(this.onRouteStateChanged);

  final ValueChanged<bool> onRouteStateChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onRouteStateChanged(previousRoute != null);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onRouteStateChanged(previousRoute != null && !previousRoute.isFirst);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onRouteStateChanged(previousRoute != null && !previousRoute.isFirst);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onRouteStateChanged(newRoute != null && !newRoute.isFirst);
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.onImportCompleted,
    required this.onImportCommitted,
    required this.onOpenTransactions,
    required this.onOpenPlans,
    required this.onOpenSavings,
    required this.onOpenProfile,
    required this.canContribute,
    required this.isCollaborative,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final VoidCallback onImportCompleted;
  final VoidCallback onImportCommitted;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenPlans;
  final VoidCallback onOpenSavings;
  final VoidCallback onOpenProfile;
  final bool canContribute;
  final bool isCollaborative;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<Household>(
        stream: services.households.watchHousehold(householdId, user.uid),
        builder: (context, householdSnapshot) {
          return StreamBuilder<List<FinanceTransaction>>(
            stream: services.finance.watchTransactions(householdId),
            builder: (context, transactionSnapshot) {
              if (householdSnapshot.hasError || transactionSnapshot.hasError) {
                return _StreamError(
                  message: _errorText(
                    householdSnapshot.error ?? transactionSnapshot.error,
                  ),
                );
              }
              if (!householdSnapshot.hasData || !transactionSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final household = householdSnapshot.data!;
              final transactions =
                  transactionSnapshot.data!
                      .where(
                        (transaction) => transaction.countsInHouseholdFinances,
                      )
                      .toList();
              return StreamBuilder<List<FinancePlan>>(
                stream: services.finance.watchPlans(householdId),
                builder: (context, planSnapshot) {
                  if (planSnapshot.hasError) {
                    return _StreamError(
                      message: _errorText(planSnapshot.error),
                    );
                  }
                  if (!planSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final plans = planSnapshot.data!;
                  final now = DateTime.now();
                  final balances = FinanceBalances.calculate(
                    transactions,
                    plans,
                    currentPeriod: now,
                  );
                  final monthlyTransactions =
                      transactions
                          .where(
                            (item) =>
                                item.occurredAt.year == now.year &&
                                item.occurredAt.month == now.month,
                          )
                          .toList();
                  return StreamBuilder<List<RecurringTransaction>>(
                    stream: services.finance.watchRecurring(householdId),
                    builder: (context, recurringSnapshot) {
                      return StreamBuilder<List<SharedExpense>>(
                        stream: services.finance.watchSharedExpenses(
                          householdId,
                        ),
                        builder: (context, sharedSnapshot) {
                          final activities = _dashboardActivities(
                            transactions: transactions,
                            recurring:
                                recurringSnapshot.data ??
                                const <RecurringTransaction>[],
                            shared:
                                sharedSnapshot.data ?? const <SharedExpense>[],
                          );
                          return RefreshIndicator(
                            onRefresh: () async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 350),
                              );
                            },
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                110,
                              ),
                              children: [
                                _DashboardHeader(
                                  user: user,
                                  household: household,
                                  onOpenProfile: onOpenProfile,
                                ),
                                const SizedBox(height: 18),
                                _AvailableBalanceWithMembers(
                                  balances: balances,
                                  monthlyTransactions: monthlyTransactions,
                                  householdId: householdId,
                                  user: user,
                                  repository: services.households,
                                  canEditIncome: household.canContribute,
                                ),
                                if (balances.uncoveredExpenses > 0) ...[
                                  const SizedBox(height: 12),
                                  Card(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.errorContainer,
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.warning_amber_rounded,
                                        color:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                      title: const Text(
                                        'Tus gastos agotaron el disponible',
                                      ),
                                      subtitle: Text(
                                        'Faltan ${_money(balances.uncoveredExpenses)} por cubrir. Registra el origen real o reduce gastos.',
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _DashboardPlansSnapshot(
                                  plans: plans,
                                  transactions: transactions,
                                  onOpenPlans: onOpenPlans,
                                ),
                                const SizedBox(height: 14),
                                _HomeEssentialActions(
                                  canContribute: household.canContribute,
                                  canInvite: household.canInvite,
                                  isCollaborative: household.isCollaborative,
                                  onOpenRecurring:
                                      () => _openRecurring(context),
                                  onOpenSharedExpenses:
                                      () => _openSharedExpenses(
                                        context,
                                        household.canManage,
                                      ),
                                  onOpenImport: () => _openImport(context),
                                  onOpenTransactions: onOpenTransactions,
                                  onOpenSavings: onOpenSavings,
                                  onOpenFamily:
                                      household.canInvite
                                          ? () =>
                                              _openInvite(context, household)
                                          : () =>
                                              _openMembers(context, household),
                                ),
                                const SizedBox(height: 14),
                                FinanceInsights(transactions: transactions),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Actividad reciente',
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                      ),
                                    ),
                                    if (activities.length > 3)
                                      TextButton(
                                        onPressed:
                                            () => _showAllActivities(
                                              context,
                                              activities,
                                            ),
                                        child: const Text('Mostrar más'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (activities.isEmpty)
                                  _EmptyState(
                                    icon: Icons.history_toggle_off_outlined,
                                    title: 'Aún no hay actividad',
                                    description:
                                        household.isCollaborative
                                            ? 'Aquí verás acciones importantes, como programaciones, divisiones e importaciones.'
                                            : 'Aquí verás acciones importantes, como programaciones e importaciones.',
                                  )
                                else
                                  ...activities
                                      .take(3)
                                      .map(_RecentActivityTile.new),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showAllActivities(
    BuildContext context,
    List<_DashboardActivity> activities,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: FractionallySizedBox(
              heightFactor: .78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      'Actividad del espacio',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: activities.length,
                      itemBuilder:
                          (context, index) =>
                              _RecentActivityTile(activities[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _openRecurring(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => RecurringTransactionsScreen(
              householdId: householdId,
              uid: user.uid,
              repository: services.finance,
              canContribute: canContribute,
            ),
      ),
    );
  }

  void _openSharedExpenses(BuildContext context, bool canManage) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => SharedDebtsScreen(
              householdId: householdId,
              currentUid: user.uid,
              repository: services.finance,
              households: services.households,
              canContribute: canContribute,
              canManage: canManage,
            ),
      ),
    );
  }

  Future<void> _openImport(BuildContext context) async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => DataToolsScreen(
              user: user,
              householdId: householdId,
              services: services,
              canImport: canContribute,
              onImportCommitted: onImportCommitted,
            ),
      ),
    );
    if (imported == true) onImportCompleted();
  }

  void _openInvite(BuildContext context, Household household) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => FamilyInviteScreen(
              householdId: householdId,
              householdKind: household.kind,
              repository: services.households,
            ),
      ),
    );
  }

  void _openMembers(BuildContext context, Household household) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => HouseholdMembersScreen(
              user: user,
              household: household,
              repository: services.households,
            ),
      ),
    );
  }
}

class _DashboardActivity {
  const _DashboardActivity({
    required this.title,
    required this.detail,
    required this.date,
    required this.icon,
  });

  final String title;
  final String detail;
  final DateTime date;
  final IconData icon;
}

List<_DashboardActivity> _dashboardActivities({
  required List<FinanceTransaction> transactions,
  required List<RecurringTransaction> recurring,
  required List<SharedExpense> shared,
}) {
  final activities = <_DashboardActivity>[];
  for (final item in recurring) {
    final typeLabel = switch (item.template.type) {
      TransactionType.income => 'un ingreso',
      TransactionType.expense => 'un pago',
      TransactionType.saving => 'un ahorro',
    };
    activities.add(
      _DashboardActivity(
        title: 'Se programó $typeLabel',
        detail:
            '${item.template.description} · Próximo ${DateFormat('dd/MM/yyyy').format(item.nextDueAt)}',
        date: item.nextDueAt,
        icon: Icons.event_repeat_outlined,
      ),
    );
  }
  for (final item in shared) {
    activities.add(
      _DashboardActivity(
        title: 'Se dividió un gasto',
        detail: '${item.description} · ${_money(item.totalMinor)}',
        date: item.occurredAt,
        icon: Icons.call_split_outlined,
      ),
    );
  }
  final importsBySource = <String, List<FinanceTransaction>>{};
  for (final item in transactions.where(
    (transaction) => transaction.origin == TransactionOrigin.imported,
  )) {
    importsBySource
        .putIfAbsent(item.sourceName ?? 'Archivo bancario', () => [])
        .add(item);
  }
  for (final entry in importsBySource.entries) {
    final latest = entry.value
        .map((item) => item.occurredAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    activities.add(
      _DashboardActivity(
        title: 'Se importó un estado de cuenta',
        detail:
            '${entry.key} · ${entry.value.length} ${entry.value.length == 1 ? 'movimiento' : 'movimientos'}',
        date: latest,
        icon: Icons.account_balance_outlined,
      ),
    );
  }
  activities.sort((left, right) => right.date.compareTo(left.date));
  return activities;
}

class _RecentActivityTile extends StatelessWidget {
  const _RecentActivityTile(this.activity);

  final _DashboardActivity activity;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(child: Icon(activity.icon, size: 20)),
      title: Text(
        activity.title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(activity.detail),
    ),
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.user,
    required this.household,
    required this.onOpenProfile,
  });

  final AuthUser user;
  final Household household;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting =
        hour < 12
            ? 'Buenos días'
            : hour < 19
            ? 'Buenas tardes'
            : 'Buenas noches';
    final firstName = user.displayName.trim().split(RegExp(r'\s+')).first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.home_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting${firstName.isEmpty ? '' : ', $firstName'}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${household.name} · ${household.kind.label} · ${household.roleType.label}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${household.memberCount} ${household.memberCount == 1 ? 'integrante' : 'integrantes'} · datos cifrados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Abrir mi perfil',
          child: InkWell(
            key: const Key('open_profile_avatar'),
            customBorder: const CircleBorder(),
            onTap: onOpenProfile,
            child: _ProfileAvatar(user: user),
          ),
        ),
      ],
    );
  }
}

class _AvailableBalanceWithMembers extends StatelessWidget {
  const _AvailableBalanceWithMembers({
    required this.balances,
    required this.monthlyTransactions,
    required this.householdId,
    required this.user,
    required this.repository,
    required this.canEditIncome,
  });

  final FinanceBalances balances;
  final List<FinanceTransaction> monthlyTransactions;
  final String householdId;
  final AuthUser user;
  final HouseholdRepository repository;
  final bool canEditIncome;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<HouseholdMember>>(
    stream: repository.watchMembers(householdId),
    builder:
        (context, snapshot) => _AvailableBalanceCard(
          balances: balances,
          monthlyTransactions: monthlyTransactions,
          members: snapshot.data ?? const <HouseholdMember>[],
          currentUid: user.uid,
          onEditIncome:
              snapshot.hasData && canEditIncome
                  ? () => _editMonthlyIncome(context, snapshot.data!)
                  : null,
        ),
  );

  Future<void> _editMonthlyIncome(
    BuildContext context,
    List<HouseholdMember> members,
  ) async {
    HouseholdMember? ownMember;
    for (final member in members) {
      if (member.uid == user.uid) {
        ownMember = member;
        break;
      }
    }
    if (ownMember == null) return;
    final controller = TextEditingController(
      text:
          ownMember.hasMonthlyIncome
              ? (ownMember.monthlyIncomeMinor / 100).toStringAsFixed(2)
              : '',
    );
    final value = await showDialog<int>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Ingresa tu sueldo o ingreso mensual'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escribe el valor neto que realmente recibes al mes. Se usa como referencia para dividir gastos proporcionalmente; no crea un movimiento de ingreso ni aumenta tu disponible.',
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('monthly_income_input'),
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Ingreso neto mensual',
                    prefixText: r'$ ',
                    helperText:
                        'Se cifra y lo verán los integrantes del espacio.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = _parseMoneyMinor(controller.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Ingresa un valor mensual mayor que cero.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, amount);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    try {
      await repository.updateMemberMonthlyIncome(
        householdId: householdId,
        uid: user.uid,
        monthlyIncomeMinor: value,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingreso mensual actualizado.')),
        );
      }
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _AvailableBalanceCard extends StatelessWidget {
  const _AvailableBalanceCard({
    required this.balances,
    required this.monthlyTransactions,
    required this.members,
    required this.currentUid,
    required this.onEditIncome,
  });

  final FinanceBalances balances;
  final List<FinanceTransaction> monthlyTransactions;
  final List<HouseholdMember> members;
  final String currentUid;
  final VoidCallback? onEditIncome;

  int _monthly(TransactionType type) => monthlyTransactions
      .where((item) => item.type == type)
      .fold(0, (sum, item) => sum + item.amountMinor);

  @override
  Widget build(BuildContext context) {
    final monthlyIncome = _monthly(TransactionType.income);
    final monthlyExpenses = _monthly(TransactionType.expense);
    final reserved = balances.savings + balances.goals;
    return Semantics(
      button: true,
      label: 'Ver cómo se calcula el dinero disponible',
      child: GestureDetector(
        key: const Key('available_balance_card'),
        onTap: () => _showBreakdown(context, reserved),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryBlue, AppColors.primaryBlueDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppShapes.extraLargeRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.white70,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Disponible para usar',
                    style: TextStyle(color: Colors.white70),
                  ),
                  Spacer(),
                  Text(
                    'Ver detalle',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right, color: Colors.white70, size: 18),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                _money(balances.available),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                reserved == 0
                    ? 'Todavía no has separado dinero para ahorros o metas.'
                    : '${_money(reserved)} están protegidos en ahorros y metas.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              _MonthlyIncomePanel(
                members: members,
                currentUid: currentUid,
                onEdit: onEditIncome,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .11),
                  borderRadius: AppShapes.largeRadius,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _BalanceCardMetric(
                            label: 'Total ingresado',
                            value: balances.income,
                            icon: Icons.arrow_downward,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BalanceCardMetric(
                            label: 'Dinero separado',
                            value: reserved,
                            icon: Icons.shield_outlined,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Este mes entró ${_money(monthlyIncome)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        Text(
                          'Salió ${_money(monthlyExpenses)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBreakdown(BuildContext context, int reserved) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu dinero disponible',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Es el dinero que queda después de restar pagos, ahorros y aportes a metas de los ingresos registrados.',
                  ),
                  const SizedBox(height: 18),
                  _BalanceBreakdownRow(
                    label: 'Ingresos registrados',
                    value: balances.income,
                    icon: Icons.add_circle_outline,
                  ),
                  _BalanceBreakdownRow(
                    label: 'Pagos y compras',
                    value: -balances.expenses,
                    icon: Icons.remove_circle_outline,
                  ),
                  _BalanceBreakdownRow(
                    label: 'Dinero separado',
                    value: -reserved,
                    icon: Icons.savings_outlined,
                  ),
                  const Divider(height: 24),
                  _BalanceBreakdownRow(
                    label: 'Disponible para usar',
                    value: balances.available,
                    icon: Icons.account_balance_wallet_outlined,
                    emphasized: true,
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _MonthlyIncomePanel extends StatelessWidget {
  const _MonthlyIncomePanel({
    required this.members,
    required this.currentUid,
    required this.onEdit,
  });

  final List<HouseholdMember> members;
  final String currentUid;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .11),
      borderRadius: AppShapes.largeRadius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.payments_outlined,
              color: Colors.white70,
              size: 19,
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Ingresos netos mensuales',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Mi ingreso'),
            ),
          ],
        ),
        if (members.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(),
          )
        else
          ...members.map(
            (member) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      member.uid == currentUid
                          ? 'Tú · ${member.displayName}'
                          : member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    member.hasMonthlyIncome
                        ? _money(member.monthlyIncomeMinor)
                        : 'Pendiente',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Referencia para repartir gastos; se suma al disponible solo cuando registras un ingreso.',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    ),
  );
}

class _BalanceBreakdownRow extends StatelessWidget {
  const _BalanceBreakdownRow({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasized = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: emphasized ? FontWeight.w900 : null),
          ),
        ),
        Text(
          _money(value),
          style: TextStyle(fontWeight: emphasized ? FontWeight.w900 : null),
        ),
      ],
    ),
  );
}

class _BalanceCardMetric extends StatelessWidget {
  const _BalanceCardMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Colors.white70, size: 18),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              _money(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _HomeEssentialActions extends StatefulWidget {
  const _HomeEssentialActions({
    required this.canContribute,
    required this.canInvite,
    required this.isCollaborative,
    required this.onOpenRecurring,
    required this.onOpenSharedExpenses,
    required this.onOpenImport,
    required this.onOpenTransactions,
    required this.onOpenSavings,
    required this.onOpenFamily,
  });

  final bool canContribute;
  final bool canInvite;
  final bool isCollaborative;
  final VoidCallback onOpenRecurring;
  final VoidCallback onOpenSharedExpenses;
  final VoidCallback onOpenImport;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenSavings;
  final VoidCallback onOpenFamily;

  @override
  State<_HomeEssentialActions> createState() => _HomeEssentialActionsState();
}

class _HomeEssentialActionsState extends State<_HomeEssentialActions> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _HomeToolButton(
        key: const Key('dashboard_open_records'),
        icon: Icons.add_card_outlined,
        title: 'Registrar dinero',
        description: 'Ingreso, pago o ahorro',
        enabled: widget.canContribute,
        onTap: widget.onOpenTransactions,
      ),
      _HomeToolButton(
        key: const Key('dashboard_add_saving'),
        icon: Icons.savings_outlined,
        title: 'Ahorros',
        description: 'Consulta y administra lo separado',
        onTap: widget.onOpenSavings,
      ),
      _HomeToolButton(
        key: const Key('home_tool_recurring'),
        icon: Icons.event_repeat_outlined,
        title: 'Programar',
        description: 'Pagos e ingresos repetitivos',
        onTap: widget.onOpenRecurring,
      ),
      if (widget.isCollaborative)
        _HomeToolButton(
          key: const Key('home_tool_shared'),
          icon: Icons.call_split_outlined,
          title: 'Dividir gasto',
          description: 'Calcula cuánto paga cada persona',
          onTap: widget.onOpenSharedExpenses,
        ),
      _HomeToolButton(
        key: const Key('home_tool_import'),
        icon: Icons.upload_file_outlined,
        title: 'Importar',
        description:
            widget.canContribute
                ? 'Carga un estado de cuenta'
                : 'Disponible para adultos',
        onTap: widget.onOpenImport,
      ),
      if (widget.isCollaborative)
        _HomeToolButton(
          key: const Key('home_tool_family'),
          icon: widget.canInvite ? Icons.qr_code_2 : Icons.groups_outlined,
          title: widget.canInvite ? 'Invitar' : 'Integrantes',
          description:
              widget.canInvite
                  ? 'Agrega un integrante con código o QR'
                  : 'Consulta quién integra el espacio',
          onTap: widget.onOpenFamily,
        ),
    ];
    final pageCount = (actions.length / 4).ceil();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Qué necesitas hacer?',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              widget.canContribute
                  ? widget.isCollaborative
                      ? 'Herramientas frecuentes de tu espacio compartido.'
                      : 'Herramientas de tu espacio personal.'
                  : 'Consulta las herramientas disponibles para tu rol.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 13),
            SizedBox(
              height: 276,
              child: PageView.builder(
                key: const Key('home_actions_carousel'),
                controller: _controller,
                itemCount: pageCount,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, pageIndex) {
                  final start = pageIndex * 4;
                  final end = math.min(start + 4, actions.length);
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 128,
                        ),
                    itemCount: end - start,
                    itemBuilder: (context, index) => actions[start + index],
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: _page == 0 ? null : () => _goToPage(_page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < pageCount; index++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: index == _page ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color:
                                index == _page
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Página siguiente',
                  onPressed:
                      _page == pageCount - 1
                          ? null
                          : () => _goToPage(_page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _goToPage(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

class _HomeToolButton extends StatelessWidget {
  const _HomeToolButton({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: AppShapes.largeRadius,
          border: Border.all(color: colors.outlineVariant, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: .08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppShapes.largeRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: AppShapes.largeRadius,
            splashColor: colors.primary.withValues(alpha: .12),
            highlightColor: colors.primary.withValues(alpha: .06),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, size: 21, color: colors.primary),
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Positioned(
                    top: 2,
                    right: 0,
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardPlansSnapshot extends StatelessWidget {
  const _DashboardPlansSnapshot({
    required this.plans,
    required this.transactions,
    required this.onOpenPlans,
  });

  final List<FinancePlan> plans;
  final List<FinanceTransaction> transactions;
  final VoidCallback onOpenPlans;

  @override
  Widget build(BuildContext context) {
    final active = plans.where((plan) => plan.isActive).take(2).toList();
    return Card(
      child: InkWell(
        onTap: onOpenPlans,
        borderRadius: AppShapes.largeRadius,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.track_changes_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Presupuestos y metas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Text('Ver detalle'),
                  const SizedBox(width: 3),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              if (active.isEmpty)
                const Text(
                  'Aún no hay planes activos. Crea un presupuesto o una meta para seguir su avance aquí.',
                )
              else ...[
                ...active.map(
                  (plan) => _DashboardPlanProgress(
                    plan: plan,
                    progress: calculatePlanProgress(
                      plan,
                      transactions,
                      DateTime.now(),
                    ),
                  ),
                ),
                Text(
                  'Los presupuestos no agregan saldo; las metas avanzan cuando les asignas aportes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardPlanProgress extends StatelessWidget {
  const _DashboardPlanProgress({required this.plan, required this.progress});

  final FinancePlan plan;
  final FinancePlanProgress progress;

  @override
  Widget build(BuildContext context) {
    final isGoal = plan.kind == FinancePlanKind.goal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${(progress.ratio * 100).clamp(0, 999).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: progress.ratio.clamp(0, 1),
            minHeight: 7,
            color: isGoal ? AppColors.accessibleGreen : null,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 4),
          Text(
            isGoal
                ? '${_money(progress.currentMinor)} ahorrados · faltan ${_money(progress.remainingMinor)}'
                : '${_money(progress.currentMinor)} gastados · quedan ${_money(progress.remainingMinor)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

enum _MovementView { app, bank }

class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab({
    super.key,
    required this.user,
    required this.householdId,
    required this.services,
    required this.canContribute,
    required this.canManage,
    required this.isCollaborative,
    required this.onViewChanged,
    required this.onEdit,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final bool canContribute;
  final bool canManage;
  final bool isCollaborative;
  final ValueChanged<_MovementView> onViewChanged;
  final ValueChanged<FinanceTransaction> onEdit;

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  static const _firstLaunchKey = 'homewallet.first_launch_at.v1';
  static const _pageSize = 30;
  final _searchController = TextEditingController();
  _MovementView _view = _MovementView.app;
  TransactionType? _filter;
  DateTimeRange? _dateRange;
  String? _category;
  String? _createdBy;
  DateTime _appHistoryStart = DateTime.now();
  bool _showAdvanced = false;
  int _visibleLimit = _pageSize;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
    unawaited(_loadAppHistoryStart());
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() => _visibleLimit = _pageSize);
    }
  }

  void showImportedOnly() {
    if (!mounted) return;
    _searchController.clear();
    setState(() {
      _filter = null;
      _dateRange = null;
      _category = null;
      _createdBy = null;
      _view = _MovementView.bank;
      _showAdvanced = true;
      _visibleLimit = _pageSize;
    });
    widget.onViewChanged(_MovementView.bank);
  }

  Future<void> _loadAppHistoryStart() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = DateTime.tryParse(
      preferences.getString(_firstLaunchKey) ?? '',
    );
    if (saved != null && mounted) {
      setState(() => _appHistoryStart = saved);
    }
  }

  void _changeView(_MovementView view) {
    if (view == _view) return;
    setState(() {
      _view = view;
      _dateRange = null;
      _category = null;
      _filter = null;
      _visibleLimit = _pageSize;
    });
    widget.onViewChanged(view);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<FinanceTransaction>>(
        stream: widget.services.finance.watchTransactions(widget.householdId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StreamError(message: _errorText(snapshot.error));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all =
              snapshot.data!
                  .where((transaction) => transaction.countsInHouseholdFinances)
                  .toList();
          return StreamBuilder<List<HouseholdMember>>(
            stream: widget.services.households.watchMembers(widget.householdId),
            builder: (context, memberSnapshot) {
              final members = memberSnapshot.data ?? const <HouseholdMember>[];
              return StreamBuilder<List<FinanceCategory>>(
                stream: widget.services.finance.watchCategories(
                  widget.householdId,
                ),
                builder: (context, categorySnapshot) {
                  final sectionTransactions =
                      all.where((item) {
                        final imported =
                            item.origin == TransactionOrigin.imported;
                        return _view == _MovementView.bank
                            ? imported
                            : !imported;
                      }).toList();
                  final availableCategories =
                      {
                          ...widget.user.preferredCategories,
                          ...(categorySnapshot.data ??
                                  const <FinanceCategory>[])
                              .map((item) => item.name),
                        }.toList()
                        ..sort();
                  final query = _searchController.text.trim().toLowerCase();
                  final visible =
                      sectionTransactions.where((item) {
                        if (_filter != null && item.type != _filter) {
                          return false;
                        }
                        if (_category != null && item.category != _category) {
                          return false;
                        }
                        if (widget.isCollaborative &&
                            _createdBy != null &&
                            item.createdBy != _createdBy) {
                          return false;
                        }
                        if (_dateRange != null) {
                          final day = DateTime(
                            item.occurredAt.year,
                            item.occurredAt.month,
                            item.occurredAt.day,
                          );
                          final start = DateTime(
                            _dateRange!.start.year,
                            _dateRange!.start.month,
                            _dateRange!.start.day,
                          );
                          final end = DateTime(
                            _dateRange!.end.year,
                            _dateRange!.end.month,
                            _dateRange!.end.day,
                            23,
                            59,
                            59,
                          );
                          if (day.isBefore(start) || day.isAfter(end)) {
                            return false;
                          }
                        }
                        return query.isEmpty ||
                            item.description.toLowerCase().contains(query) ||
                            item.category.toLowerCase().contains(query);
                      }).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
                    children: [
                      AppPageHeader(
                        icon: Icons.receipt_long_outlined,
                        title: 'Movimientos',
                        subtitle:
                            'Tu historial de ingresos, gastos y ahorros. Los datos financieros se cifran antes de sincronizarse.',
                        trailing: IconButton(
                          tooltip: 'Cómo funcionan tus registros',
                          onPressed: _showRecordsInformation,
                          icon: const Icon(Icons.info_outline),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<_MovementView>(
                          segments: const [
                            ButtonSegment(
                              value: _MovementView.app,
                              icon: Icon(Icons.phone_android_outlined),
                              label: Text('HomeWallet'),
                            ),
                            ButtonSegment(
                              value: _MovementView.bank,
                              icon: Icon(Icons.account_balance_outlined),
                              label: Text('Bancos importados'),
                            ),
                          ],
                          selected: {_view},
                          onSelectionChanged:
                              (values) => _changeView(values.first),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: 'Buscar por descripción o categoría',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon:
                              query.isEmpty
                                  ? null
                                  : IconButton(
                                    tooltip: 'Limpiar búsqueda',
                                    onPressed: _searchController.clear,
                                    icon: const Icon(Icons.close),
                                  ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: _filter == null,
                            onSelected:
                                (_) => setState(() {
                                  _filter = null;
                                  _visibleLimit = _pageSize;
                                }),
                          ),
                          ChoiceChip(
                            label: const Text('Ingresos'),
                            selected: _filter == TransactionType.income,
                            onSelected:
                                (_) => setState(() {
                                  _filter = TransactionType.income;
                                  _visibleLimit = _pageSize;
                                }),
                          ),
                          ChoiceChip(
                            label: const Text('Gastos'),
                            selected: _filter == TransactionType.expense,
                            onSelected:
                                (_) => setState(() {
                                  _filter = TransactionType.expense;
                                  _visibleLimit = _pageSize;
                                }),
                          ),
                          if (_view == _MovementView.app)
                            ChoiceChip(
                              label: const Text('Ahorros'),
                              selected: _filter == TransactionType.saving,
                              onSelected:
                                  (_) => setState(() {
                                    _filter = TransactionType.saving;
                                    _visibleLimit = _pageSize;
                                  }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed:
                              () => setState(
                                () => _showAdvanced = !_showAdvanced,
                              ),
                          icon: Icon(
                            _showAdvanced ? Icons.expand_less : Icons.tune,
                          ),
                          label: Text(
                            _hasAdvancedFilters
                                ? 'Filtros activos'
                                : 'Más filtros',
                          ),
                        ),
                      ),
                      if (_showAdvanced) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                DropdownButtonFormField<String?>(
                                  value: _category,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Categoría',
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Todas las categorías'),
                                    ),
                                    ...availableCategories.map(
                                      (value) => DropdownMenuItem<String?>(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    ),
                                  ],
                                  onChanged:
                                      (value) => setState(() {
                                        _category = value;
                                        _visibleLimit = _pageSize;
                                      }),
                                ),
                                const SizedBox(height: 10),
                                if (widget.isCollaborative) ...[
                                  DropdownButtonFormField<String?>(
                                    value: _createdBy,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Integrante',
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Todos los integrantes'),
                                      ),
                                      ...members.map(
                                        (member) => DropdownMenuItem<String?>(
                                          value: member.uid,
                                          child: Text(
                                            member.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged:
                                        (value) => setState(() {
                                          _createdBy = value;
                                          _visibleLimit = _pageSize;
                                        }),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed:
                                            _view == _MovementView.bank &&
                                                    sectionTransactions.isEmpty
                                                ? null
                                                : () => _pickDateRange(
                                                  sectionTransactions,
                                                ),
                                        icon: const Icon(
                                          Icons.date_range_outlined,
                                        ),
                                        label: Text(
                                          _dateRange == null
                                              ? _view == _MovementView.bank &&
                                                      sectionTransactions
                                                          .isEmpty
                                                  ? 'Sin período bancario'
                                                  : 'Elegir período'
                                              : '${DateFormat('dd/MM/yy').format(_dateRange!.start)} – ${DateFormat('dd/MM/yy').format(_dateRange!.end)}',
                                        ),
                                      ),
                                    ),
                                    if (_hasAdvancedFilters) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Limpiar filtros',
                                        onPressed: _clearAdvancedFilters,
                                        icon: const Icon(
                                          Icons.filter_alt_off_outlined,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _MovementResultSummary(
                        transactions: visible,
                        showSavings: _view == _MovementView.app,
                      ),
                      const SizedBox(height: 14),
                      if (visible.isEmpty)
                        const _EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'No hay resultados',
                          description:
                              'No existen movimientos para este filtro.',
                        )
                      else
                        ..._buildMovementGroups(
                          visible.take(_visibleLimit).toList(),
                          members,
                        ),
                      if (visible.length > _visibleLimit) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          key: const Key('load_more_transactions'),
                          onPressed:
                              () => setState(() => _visibleLimit += _pageSize),
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            'Ver ${math.min(_pageSize, visible.length - _visibleLimit)} movimientos más',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mostrando $_visibleLimit de ${visible.length}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  bool get _hasAdvancedFilters =>
      _dateRange != null ||
      _category != null ||
      (widget.isCollaborative && _createdBy != null);

  List<Widget> _buildMovementGroups(
    List<FinanceTransaction> transactions,
    List<HouseholdMember> members,
  ) {
    final sorted = [...transactions]
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final widgets = <Widget>[];
    String? previousMonth;
    final now = DateTime.now();
    for (final transaction in sorted) {
      final monthKey =
          '${transaction.occurredAt.year}-${transaction.occurredAt.month}';
      if (monthKey != previousMonth) {
        final current = transaction.occursInMonth(now);
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: previousMonth == null ? 0 : 14,
              bottom: 8,
            ),
            child: Row(
              children: [
                Icon(
                  current ? Icons.today_outlined : Icons.history,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_monthYearLabel(transaction.occurredAt)}${current ? ' · Este mes' : ''}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        );
        previousMonth = monthKey;
      }
      final creator =
          members
              .where((member) => member.uid == transaction.createdBy)
              .map((member) => member.displayName)
              .firstOrNull;
      final canModify =
          widget.canContribute &&
          (transaction.createdBy == widget.user.uid || widget.canManage);
      widgets.add(
        _TransactionTile(
          transaction: transaction,
          onTap:
              () => _showTransactionDetails(
                transaction,
                creatorName: creator,
                canModify: canModify,
              ),
        ),
      );
    }
    return widgets;
  }

  Future<void> _pickDateRange(List<FinanceTransaction> source) async {
    final now = DateTime.now();
    final dates = source.map((item) => item.occurredAt).toList()..sort();
    final firstDate =
        _view == _MovementView.bank && dates.isNotEmpty
            ? DateTime(dates.first.year, dates.first.month, dates.first.day)
            : DateTime(
              _appHistoryStart.year,
              _appHistoryStart.month,
              _appHistoryStart.day,
            );
    final lastSourceDate =
        _view == _MovementView.bank && dates.isNotEmpty ? dates.last : now;
    final lastDate = DateTime(
      lastSourceDate.year,
      lastSourceDate.month,
      lastSourceDate.day,
    );
    final range = await showDateRangePicker(
      context: context,
      firstDate: firstDate.isAfter(lastDate) ? lastDate : firstDate,
      lastDate: lastDate,
      initialDateRange: _dateRange,
      helpText:
          _view == _MovementView.bank
              ? 'Período disponible en el archivo bancario'
              : 'Movimientos desde que instalaste HomeWallet',
    );
    if (range != null && mounted) {
      setState(() {
        _dateRange = range;
        _visibleLimit = _pageSize;
      });
    }
  }

  void _clearAdvancedFilters() {
    setState(() {
      _dateRange = null;
      _category = null;
      _createdBy = null;
      _visibleLimit = _pageSize;
    });
  }

  void _showRecordsInformation() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: const Icon(Icons.receipt_long_outlined),
            title: const Text('Sobre tus registros'),
            content: const Text(
              'HomeWallet organiza información que tú registras o importas. No reemplaza un estado de cuenta bancario, una factura, un comprobante autorizado por el SRI ni asesoría financiera o tributaria. Revisa los datos antes de usarlos para tomar decisiones.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  Future<void> _showTransactionDetails(
    FinanceTransaction transaction, {
    required String? creatorName,
    required bool canModify,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheetContext) => _TransactionDetailsSheet(
            transaction: transaction,
            creatorName: creatorName,
            canModify: canModify,
            onEdit: () {
              Navigator.pop(sheetContext);
              _editTransaction(transaction);
            },
            onDelete: () {
              Navigator.pop(sheetContext);
              _deleteTransaction(transaction);
            },
          ),
    );
  }

  Future<void> _editTransaction(FinanceTransaction transaction) async {
    if (transaction.origin == TransactionOrigin.imported &&
        transaction.sourceVerified) {
      final accepted = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              icon: const Icon(Icons.edit_document),
              title: const Text('Corregir registro importado'),
              content: const Text(
                'Al guardar cambios dejará de considerarse una coincidencia exacta con el archivo bancario original. El origen importado se conservará para mantener la trazabilidad.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continuar'),
                ),
              ],
            ),
      );
      if (accepted != true || !mounted) return;
    }
    widget.onEdit(transaction);
  }

  Future<void> _deleteTransaction(FinanceTransaction transaction) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                icon: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Eliminar movimiento'),
                content: Text(
                  'Se eliminará “${transaction.description}” para todo el espacio. Esta acción no se puede deshacer y recalculará saldos${transaction.linkedPlanName == null ? '' : ', además del avance de ${transaction.linkedPlanName}'}.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await widget.services.finance.deleteTransaction(
        widget.householdId,
        transaction,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Movimiento eliminado correctamente.')),
        );
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _MovementResultSummary extends StatelessWidget {
  const _MovementResultSummary({
    required this.transactions,
    required this.showSavings,
  });

  final List<FinanceTransaction> transactions;
  final bool showSavings;

  @override
  Widget build(BuildContext context) {
    final income = _total(TransactionType.income);
    final expenses = _total(TransactionType.expense);
    final savings = _total(TransactionType.saving);
    final flow = income - expenses;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assessment_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resultado del filtro',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${transactions.length} ${transactions.length == 1 ? 'registro' : 'registros'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _MovementResultValue(
                    label: 'Ingresos',
                    value: income,
                    color: AppColors.accessibleGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MovementResultValue(
                    label: 'Gastos',
                    value: expenses,
                    color: scheme.error,
                  ),
                ),
                if (showSavings) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MovementResultValue(
                      label: 'Ahorros',
                      value: savings,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    showSavings
                        ? 'Flujo (ingresos − gastos)'
                        : 'Balance del estado de cuenta',
                  ),
                ),
                Text(
                  _money(flow),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: flow < 0 ? scheme.error : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _total(TransactionType type) => transactions
      .where((transaction) => transaction.type == type)
      .fold(0, (total, transaction) => total + transaction.amountMinor);
}

class _MovementResultValue extends StatelessWidget {
  const _MovementResultValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      Text(
        _money(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _TransactionDetailsSheet extends StatelessWidget {
  const _TransactionDetailsSheet({
    required this.transaction,
    required this.creatorName,
    required this.canModify,
    required this.onEdit,
    required this.onDelete,
  });

  final FinanceTransaction transaction;
  final String? creatorName;
  final bool canModify;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isImported = transaction.origin == TransactionOrigin.imported;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Detalle del movimiento',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(_movementTypeIcon(transaction.type)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      transaction.description,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _money(transaction.amountMinor),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  _TransactionDetailRow(
                    label: 'Tipo',
                    value: _movementTypeLabel(transaction.type),
                  ),
                  const Divider(height: 1),
                  _TransactionDetailRow(
                    label: 'Categoría',
                    value: transaction.category,
                  ),
                  const Divider(height: 1),
                  _TransactionDetailRow(
                    label: 'Fecha',
                    value: _longSpanishDate(transaction.occurredAt),
                  ),
                  const Divider(height: 1),
                  _TransactionDetailRow(
                    label: 'Registrado por',
                    value: creatorName ?? 'Integrante del espacio',
                  ),
                  const Divider(height: 1),
                  _TransactionDetailRow(
                    label: 'Origen',
                    value:
                        isImported
                            ? transaction.sourceName ?? 'Archivo importado'
                            : 'Registrado en HomeWallet',
                  ),
                  if (transaction.linkedPlanName != null) ...[
                    const Divider(height: 1),
                    _TransactionDetailRow(
                      label: 'Meta relacionada',
                      value: transaction.linkedPlanName!,
                    ),
                  ],
                ],
              ),
            ),
            if (isImported) ...[
              const SizedBox(height: 12),
              Card(
                color:
                    transaction.sourceVerified
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                child: ListTile(
                  leading: Icon(
                    transaction.sourceVerified
                        ? Icons.verified_outlined
                        : Icons.edit_document,
                  ),
                  title: Text(
                    transaction.sourceVerified
                        ? 'Coincide con el archivo importado'
                        : 'Sin coincidencia exacta verificada',
                  ),
                  subtitle: Text(
                    transaction.sourceVerified
                        ? 'Si lo corriges manualmente, esta verificación se retirará.'
                        : 'El origen se conserva, pero revisa el registro con el documento original.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Este registro es informativo y no sustituye un comprobante bancario, tributario o de venta.',
              textAlign: TextAlign.center,
            ),
            if (canModify) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(isImported ? 'Corregir registro' : 'Editar'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransactionDetailRow extends StatelessWidget {
  const _TransactionDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _PlansTab extends StatelessWidget {
  const _PlansTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.canContribute,
    required this.role,
    required this.onAddToGoal,
    required this.onRecordBudgetExpense,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final bool canContribute;
  final HouseholdRole role;
  final Future<void> Function(FinancePlan, TransactionType) onAddToGoal;
  final Future<void> Function(FinancePlan) onRecordBudgetExpense;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<FinancePlan>>(
        stream: services.finance.watchPlans(householdId),
        builder: (context, planSnapshot) {
          if (planSnapshot.hasError) {
            return _StreamError(message: _errorText(planSnapshot.error));
          }
          if (!planSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final plans = planSnapshot.data!;
          return StreamBuilder<List<FinanceTransaction>>(
            stream: services.finance.watchTransactions(householdId),
            builder: (context, transactionSnapshot) {
              if (transactionSnapshot.hasError) {
                return _StreamError(
                  message: _errorText(transactionSnapshot.error),
                );
              }
              if (!transactionSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final transactions = transactionSnapshot.data!;
              final budgets =
                  plans
                      .where((plan) => plan.kind == FinancePlanKind.budget)
                      .toList();
              final goals =
                  plans
                      .where((plan) => plan.kind == FinancePlanKind.goal)
                      .toList();
              final isJunior = role == HouseholdRole.junior;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
                children: [
                  AppPageHeader(
                    icon: Icons.flag_outlined,
                    title:
                        isJunior
                            ? 'Objetivos de nuestro espacio'
                            : 'Presupuestos y metas',
                    subtitle:
                        isJunior
                            ? 'Mira cómo avanzan las metas y cómo cuidamos el presupuesto compartido.'
                            : 'Controla límites mensuales y separa dinero para tus objetivos. Todo se actualiza con los movimientos.',
                    trailing:
                        isJunior
                            ? null
                            : FilledButton.tonalIcon(
                              key: const Key('create_plan_button'),
                              onPressed:
                                  canContribute
                                      ? () => _addPlan(context)
                                      : null,
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 19),
                              label: const Text('Crear plan'),
                            ),
                  ),
                  const SizedBox(height: 14),
                  if (isJunior)
                    const _JuniorPlansIntro()
                  else
                    const _PlanLogicGuide(),
                  const SizedBox(height: 20),
                  if (plans.isEmpty)
                    _EmptyState(
                      icon: Icons.savings_outlined,
                      title:
                          isJunior
                              ? 'Todavía no hay objetivos'
                              : 'Aún no tienes planes',
                      description:
                          isJunior
                              ? 'Cuando un adulto cree una meta o presupuesto podrás seguirlo aquí.'
                              : 'Crea un presupuesto mensual o una meta de ahorro.',
                      actionLabel:
                          !isJunior && canContribute ? 'Crear plan' : null,
                      onAction:
                          !isJunior && canContribute
                              ? () => _addPlan(context)
                              : null,
                    )
                  else ...[
                    if (budgets.isNotEmpty) ...[
                      _PlanSectionTitle(
                        icon: Icons.account_balance_wallet_outlined,
                        title:
                            isJunior
                                ? 'Cuidemos el mes'
                                : 'Presupuestos del mes',
                        subtitle:
                            isJunior
                                ? 'La barra crece cuando el espacio registra gastos.'
                                : 'Miden gastos, no ingresos. Se reinician cada mes.',
                      ),
                      ...budgets.map(
                        (plan) =>
                            isJunior
                                ? _juniorPlanCard(context, plan, transactions)
                                : _adultPlanCard(context, plan, transactions),
                      ),
                    ],
                    if (goals.isNotEmpty) ...[
                      if (budgets.isNotEmpty) const SizedBox(height: 12),
                      _PlanSectionTitle(
                        icon: Icons.flag_outlined,
                        title:
                            isJunior
                                ? 'Metas que queremos lograr'
                                : 'Metas de ahorro',
                        subtitle:
                            isJunior
                                ? 'Cada aporte nos acerca al objetivo.'
                                : 'Aumentan con ingresos o ahorros asignados a la meta.',
                      ),
                      ...goals.map(
                        (plan) =>
                            isJunior
                                ? _juniorPlanCard(context, plan, transactions)
                                : _adultPlanCard(context, plan, transactions),
                      ),
                    ],
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _adultPlanCard(
    BuildContext context,
    FinancePlan plan,
    List<FinanceTransaction> transactions,
  ) {
    final details = calculatePlanProgress(plan, transactions, DateTime.now());
    final progress = details.ratio;
    final warning =
        plan.kind == FinancePlanKind.budget && progress >= plan.alertThreshold;
    final scheme = Theme.of(context).colorScheme;
    final isGoal = plan.kind == FinancePlanKind.goal;
    final status =
        !plan.isActive
            ? isGoal
                ? 'Completada'
                : 'Inactivo'
            : isGoal
            ? details.complete
                ? 'Cumplida'
                : progress >= .75
                ? 'Falta poco'
                : progress > 0
                ? 'En progreso'
                : 'Sin aportes'
            : progress >= 1
            ? 'Agotado'
            : warning
            ? 'Atención'
            : 'Vas bien';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: warning ? scheme.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        isGoal
                            ? AppColors.accessibleGreen.withValues(alpha: .16)
                            : scheme.primaryContainer,
                    child: Icon(
                      isGoal
                          ? Icons.flag_outlined
                          : Icons.account_balance_wallet_outlined,
                      color:
                          warning
                              ? scheme.error
                              : isGoal
                              ? AppColors.accessibleGreen
                              : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(isGoal ? 'Meta de ahorro' : 'Presupuesto mensual'),
                      ],
                    ),
                  ),
                  Chip(label: Text(status)),
                  if (_canManagePlan(plan))
                    PopupMenuButton<_PlanAction>(
                      tooltip: 'Administrar plan',
                      onSelected:
                          (action) => _handlePlanAction(context, plan, action),
                      itemBuilder:
                          (context) => [
                            const PopupMenuItem(
                              value: _PlanAction.edit,
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Editar'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _PlanAction.toggleActive,
                              child: ListTile(
                                leading: Icon(
                                  plan.isActive
                                      ? Icons.check_circle_outline
                                      : Icons.restart_alt,
                                ),
                                title: Text(
                                  plan.isActive
                                      ? plan.kind == FinancePlanKind.goal
                                          ? 'Marcar completada'
                                          : 'Desactivar'
                                      : 'Reactivar',
                                ),
                              ),
                            ),
                            const PopupMenuItem(
                              value: _PlanAction.delete,
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Eliminar'),
                              ),
                            ),
                          ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isGoal ? 'AHORRADO' : 'GASTADO ESTE MES',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _money(details.currentMinor),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text('de ${_money(plan.targetMinor)}'),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10,
                color:
                    warning
                        ? scheme.error
                        : isGoal
                        ? AppColors.accessibleGreen
                        : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isGoal
                          ? 'Faltan ${_money(details.remainingMinor)}'
                          : 'Disponible ${_money(details.remainingMinor)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${(progress * 100).clamp(0, 999).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PlanMilestones(progress: progress, isGoal: isGoal),
              const SizedBox(height: 12),
              _PlanDetailBox(plan: plan, progress: details),
              if (canContribute && plan.isActive) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed:
                        isGoal
                            ? () => _chooseGoalContribution(context, plan)
                            : () => onRecordBudgetExpense(plan),
                    icon: Icon(
                      isGoal ? Icons.add_card_outlined : Icons.add_outlined,
                    ),
                    label: Text(
                      isGoal ? 'Agregar dinero a la meta' : 'Agregar gasto',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _juniorPlanCard(
    BuildContext context,
    FinancePlan plan,
    List<FinanceTransaction> transactions,
  ) {
    final details = calculatePlanProgress(plan, transactions, DateTime.now());
    final isGoal = plan.kind == FinancePlanKind.goal;
    final scheme = Theme.of(context).colorScheme;
    final percent = (details.ratio * 100).clamp(0, 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isGoal
                        ? Icons.emoji_events_outlined
                        : Icons.shield_outlined,
                    color: isGoal ? AppColors.accessibleGreen : scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      plan.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color:
                          isGoal ? AppColors.accessibleGreen : scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isGoal
                    ? details.complete
                        ? '¡Objetivo alcanzado! El esfuerzo de todos dio resultado.'
                        : 'Ya reunimos ${_money(details.currentMinor)}. Faltan ${_money(details.remainingMinor)} para lograrlo.'
                    : details.ratio >= 1
                    ? 'Llegamos al límite del mes. Es momento de evitar más gastos.'
                    : 'Todavía quedan ${_money(details.remainingMinor)} para usar este mes.',
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: details.ratio.clamp(0, 1),
                minHeight: 12,
                color: isGoal ? AppColors.accessibleGreen : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(height: 12),
              _PlanMilestones(progress: details.ratio, isGoal: isGoal),
              const SizedBox(height: 10),
              Text(
                'Vista de Integrante Jr · los adultos administran este plan.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseGoalContribution(
    BuildContext context,
    FinancePlan plan,
  ) async {
    final type = await showModalBottomSheet<TransactionType>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Agregar dinero a ${plan.name}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text('Elige de dónde viene el aporte.'),
                    const SizedBox(height: 14),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.savings_outlined),
                        title: const Text('Del saldo disponible'),
                        subtitle: const Text(
                          'Mover dinero que ya está en HomeWallet hacia esta meta.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap:
                            () =>
                                Navigator.pop(context, TransactionType.saving),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: const Text('Es un nuevo ingreso'),
                        subtitle: const Text(
                          'Registrar dinero que acaba de entrar y enviarlo directamente a la meta.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap:
                            () =>
                                Navigator.pop(context, TransactionType.income),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    if (type != null && context.mounted) await onAddToGoal(plan, type);
  }

  Future<void> _addPlan(BuildContext context) async {
    final input = await showModalBottomSheet<_PlanInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PlanForm(),
    );
    if (input == null || !context.mounted) return;
    try {
      await services.finance.addPlan(
        householdId: householdId,
        uid: user.uid,
        name: input.name,
        kind: input.kind,
        targetMinor: input.targetMinor,
        category: input.category,
        deadline: input.deadline,
        alertThreshold: input.alertThreshold,
      );
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  bool _canManagePlan(FinancePlan plan) =>
      canContribute && (plan.createdBy == user.uid || role.canManage);

  Future<void> _handlePlanAction(
    BuildContext context,
    FinancePlan plan,
    _PlanAction action,
  ) async {
    switch (action) {
      case _PlanAction.edit:
        await _editPlan(context, plan);
      case _PlanAction.toggleActive:
        await _setPlanActive(context, plan, !plan.isActive);
      case _PlanAction.delete:
        await _deletePlan(context, plan);
    }
  }

  Future<void> _editPlan(BuildContext context, FinancePlan plan) async {
    final input = await showModalBottomSheet<_PlanInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlanForm(existing: plan),
    );
    if (input == null || !context.mounted) return;
    try {
      await services.finance.updatePlan(
        householdId: householdId,
        plan: plan,
        name: input.name,
        targetMinor: input.targetMinor,
        isActive: plan.isActive,
        category: input.category,
        deadline: input.deadline,
        alertThreshold: input.alertThreshold,
      );
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _setPlanActive(
    BuildContext context,
    FinancePlan plan,
    bool isActive,
  ) async {
    try {
      await services.finance.updatePlan(
        householdId: householdId,
        plan: plan,
        name: plan.name,
        targetMinor: plan.targetMinor,
        isActive: isActive,
        category: plan.category,
        deadline: plan.deadline,
        alertThreshold: plan.alertThreshold,
      );
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _deletePlan(BuildContext context, FinancePlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar plan'),
            content: Text(
              plan.kind == FinancePlanKind.goal && plan.currentMinor > 0
                  ? 'Esta meta tiene aportes y debe conservarse para mantener la trazabilidad de los movimientos.'
                  : 'Se eliminará “${plan.name}”. Los movimientos registrados no se eliminarán.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed:
                    plan.kind == FinancePlanKind.goal && plan.currentMinor > 0
                        ? null
                        : () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await services.finance.deletePlan(householdId, plan);
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

enum _PlanAction { edit, toggleActive, delete }

class _PlanLogicGuide extends StatelessWidget {
  const _PlanLogicGuide();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cómo se actualiza',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const _PlanLogicRow(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Presupuesto',
            description: 'La barra sube con los gastos de su categoría.',
          ),
          const SizedBox(height: 9),
          const _PlanLogicRow(
            icon: Icons.flag_outlined,
            title: 'Meta de ahorro',
            description: 'La barra sube al asignarle un ingreso o un ahorro.',
          ),
        ],
      ),
    ),
  );
}

class _JuniorPlansIntro extends StatelessWidget {
  const _JuniorPlansIntro();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: const Padding(
      padding: EdgeInsets.all(15),
      child: Row(
        children: [
          Icon(Icons.school_outlined),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Aprender a ahorrar también es ver el progreso. Tu acceso es de consulta y no modifica el dinero del espacio.',
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlanLogicRow extends StatelessWidget {
  const _PlanLogicRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
      const SizedBox(width: 9),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: description),
            ],
          ),
        ),
      ),
    ],
  );
}

class _PlanSectionTitle extends StatelessWidget {
  const _PlanSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(icon, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PlanMilestones extends StatelessWidget {
  const _PlanMilestones({required this.progress, required this.isGoal});

  final double progress;
  final bool isGoal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = <(double, String)>[
      (0, 'Inicio'),
      (.25, '25%'),
      (.50, '50%'),
      (.75, '75%'),
      (1, isGoal ? 'Meta' : 'Límite'),
    ];
    return Row(
      children:
          values
              .map(
                (entry) => Expanded(
                  child: Column(
                    children: [
                      Icon(
                        progress >= entry.$1
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 17,
                        color:
                            progress >= entry.$1
                                ? isGoal
                                    ? AppColors.accessibleGreen
                                    : scheme.primary
                                : scheme.outline,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.$2,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _PlanDetailBox extends StatelessWidget {
  const _PlanDetailBox({required this.plan, required this.progress});

  final FinancePlan plan;
  final FinancePlanProgress progress;

  @override
  Widget build(BuildContext context) {
    final isGoal = plan.kind == FinancePlanKind.goal;
    final latest =
        progress.latestActivityAt == null
            ? 'Sin movimientos todavía'
            : 'Último movimiento: ${DateFormat('dd/MM/yyyy').format(progress.latestActivityAt!)}';
    final recommendation =
        progress.recommendedMonthlyMinor == null || progress.complete
            ? null
            : 'Ritmo sugerido: ${_money(progress.recommendedMonthlyMinor!)} al mes';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppShapes.largeRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGoal
                  ? plan.deadline == null
                      ? 'Sin fecha límite'
                      : 'Fecha objetivo: ${DateFormat('dd/MM/yyyy').format(plan.deadline!)}'
                  : 'Categoría: ${plan.category ?? 'Todos los gastos'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('$latest · ${progress.activityCount} movimientos vinculados'),
            if (recommendation != null) ...[
              const SizedBox(height: 4),
              Text(
                recommendation,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.themeController,
    required this.household,
    required this.onSignOut,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final ThemeController themeController;
  final Household household;
  final Future<void> Function() onSignOut;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  bool? _biometricEnabled;
  bool? _notificationsEnabled;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    widget.services.biometricLock.isEnabled(widget.user.uid).then((value) {
      if (mounted) setState(() => _biometricEnabled = value);
    });
    widget.services.notifications?.isEnabled(widget.user.uid).then((value) {
      if (mounted) setState(() => _notificationsEnabled = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<Household>(
        stream: widget.services.households.watchHousehold(
          widget.householdId,
          widget.user.uid,
        ),
        builder: (context, snapshot) {
          final currentHousehold = snapshot.data ?? widget.household;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            children: [
              const AppPageHeader(
                icon: Icons.person_outline,
                title: 'Perfil y configuración',
                subtitle: 'Tu cuenta, espacios, seguridad y preferencias.',
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  key: const Key('open_profile_tile'),
                  leading: _ProfileAvatar(user: widget.user),
                  title: Text(
                    widget.user.displayName.isEmpty
                        ? 'Mi perfil'
                        : widget.user.displayName,
                  ),
                  subtitle: Text(widget.user.email),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _openProfile,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(_householdKindIcon(currentHousehold.kind)),
                  ),
                  title: Text(currentHousehold.name),
                  subtitle: Text(
                    snapshot.hasError
                        ? _errorText(snapshot.error)
                        : '${currentHousehold.memberCount} ${currentHousehold.memberCount == 1 ? 'integrante' : 'integrantes'} · ${currentHousehold.kind.label}',
                  ),
                  trailing:
                      currentHousehold.isCollaborative
                          ? const Icon(Icons.chevron_right)
                          : null,
                  onTap:
                      currentHousehold.isCollaborative
                          ? () => _showMembers(currentHousehold)
                          : () => _openSpaces(),
                ),
              ),
              if (!currentHousehold.canContribute) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('Acceso de lector / Integrante Jr'),
                    subtitle: Text(
                      'Puedes consultar movimientos, reportes y metas. Solo el propietario puede darte permisos para modificar.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Espacios',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  key: const Key('manage_spaces'),
                  leading: const Icon(Icons.space_dashboard_outlined),
                  title: const Text('Mis espacios'),
                  subtitle: const Text(
                    'Cambia entre tus datos personales y compartidos',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openSpaces,
                ),
              ),
              if (currentHousehold.isIndividual) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    key: const Key('create_shared_from_individual'),
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Crear espacio compartido'),
                    subtitle: const Text(
                      'Crea una Pareja, Familia o Grupo sin compartir tu historial personal',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => _openSpaces(HouseholdSpacesAction.createShared),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  key: const Key('join_space_from_settings'),
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('Unirse a un espacio'),
                  subtitle: const Text(
                    'Ingresa el código de una Pareja, Familia o Grupo',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openSpaces(HouseholdSpacesAction.join),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Organización',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categorías'),
                  subtitle: const Text('Predeterminadas y personalizadas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => CategoriesScreen(
                                householdId: widget.householdId,
                                uid: widget.user.uid,
                                repository: widget.services.finance,
                                authRepository: widget.services.auth,
                                preferredCategories:
                                    widget.user.preferredCategories.toSet(),
                                canContribute: currentHousehold.canContribute,
                              ),
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Tutorial de la app'),
                  subtitle: const Text('Repasa las funciones principales'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder:
                              (_) => AppTutorialScreen(onFinished: () async {}),
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      secondary: const Icon(
                        Icons.notifications_active_outlined,
                      ),
                      title: const Text('Notificaciones inteligentes'),
                      subtitle: Text(
                        currentHousehold.isCollaborative
                            ? 'Alertas de saldo, presupuestos, metas, recurrencias e invitaciones'
                            : 'Alertas de saldo, presupuestos, metas y recurrencias',
                      ),
                      value: _notificationsEnabled ?? false,
                      onChanged:
                          widget.services.notifications == null ||
                                  _notificationsEnabled == null
                              ? null
                              : _changeNotifications,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.fingerprint),
                      title: const Text('Bloqueo del dispositivo'),
                      subtitle: Text(
                        _biometricEnabled == true
                            ? 'Activo · usa la seguridad configurada en este teléfono'
                            : 'Desactivado · elige cómo proteger HomeWallet',
                      ),
                      value: _biometricEnabled ?? false,
                      onChanged:
                          _biometricEnabled == null ? null : _changeBiometric,
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.enhanced_encryption_outlined),
                      title: Text('Cifrado AES-256-GCM'),
                      subtitle: Text(
                        'Montos y detalles se cifran antes de salir del dispositivo',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Apariencia',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Claro'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Oscuro'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.settings_suggest_outlined),
                    label: Text('Sistema'),
                  ),
                ],
                selected: {widget.themeController.themeMode},
                onSelectionChanged:
                    (selection) =>
                        widget.themeController.select(selection.first),
              ),
              const SizedBox(height: 18),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Términos y privacidad'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LegalScreen(),
                            ),
                          ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Acerca de HomeWallet'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AboutHomeWalletScreen(),
                            ),
                          ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('sign_out_tile'),
                      leading:
                          _signingOut
                              ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                              : const Icon(Icons.logout),
                      title: Text(
                        _signingOut ? 'Cerrando sesión…' : 'Cerrar sesión',
                      ),
                      enabled: !_signingOut,
                      onTap: _signingOut ? null : _signOut,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'HomeWallet 1.0.16 · Firebase Blaze',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cerrar la sesión.')),
      );
    }
  }

  Future<void> _changeNotifications(bool enabled) async {
    final service = widget.services.notifications;
    if (service == null) return;
    try {
      final active = await service.setEnabled(widget.user.uid, enabled);
      if (mounted) {
        setState(() => _notificationsEnabled = active);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              active
                  ? 'Notificaciones inteligentes activadas.'
                  : enabled
                  ? 'El sistema no concedió permiso. Actívalo en los ajustes del teléfono.'
                  : 'Notificaciones desactivadas en este dispositivo.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cambiar la configuración de avisos.'),
          ),
        );
      }
    }
  }

  Future<void> _changeBiometric(bool enabled) async {
    if (enabled) {
      final action = await showModalBottomSheet<_DeviceLockAction>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder:
            (context) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppPageHeader(
                    icon: Icons.fingerprint,
                    title: 'Protege HomeWallet',
                    subtitle:
                        'Android valida la huella, el rostro, PIN o patrón sin compartir esos datos con la app.',
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: ListTile(
                      key: const Key('use_current_device_lock'),
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Usar el bloqueo actual'),
                      subtitle: const Text(
                        'Utiliza la seguridad que ya está configurada en este teléfono.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.pop(
                            context,
                            _DeviceLockAction.useCurrent,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      key: const Key('configure_device_lock'),
                      leading: const Icon(Icons.add_moderator_outlined),
                      title: const Text('Agregar o cambiar seguridad'),
                      subtitle: const Text(
                        'Abre los ajustes del teléfono para añadir una huella, rostro, PIN o patrón.',
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap:
                          () => Navigator.pop(
                            context,
                            _DeviceLockAction.configure,
                          ),
                    ),
                  ),
                ],
              ),
            ),
      );
      if (!mounted || action == null) return;
      if (action == _DeviceLockAction.configure) {
        try {
          await widget.services.biometricLock.openEnrollmentSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cuando termines en los ajustes, vuelve y activa el bloqueo usando la seguridad actual.',
                ),
              ),
            );
          }
        } on AppException catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
        return;
      }
    }
    try {
      await widget.services.biometricLock.setEnabled(widget.user.uid, enabled);
      if (mounted) {
        setState(() => _biometricEnabled = enabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Bloqueo de HomeWallet activado.'
                  : 'Bloqueo de HomeWallet desactivado.',
            ),
          ),
        );
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ProfileScreen(
              user: widget.user,
              householdId: widget.householdId,
              services: widget.services,
            ),
      ),
    );
  }

  void _showMembers(Household household) {
    if (household.isIndividual) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => HouseholdMembersScreen(
              user: widget.user,
              household: household,
              repository: widget.services.households,
            ),
      ),
    );
  }

  Future<void> _openSpaces([HouseholdSpacesAction? initialAction]) async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => HouseholdSpacesScreen(
              user: widget.user,
              currentHouseholdId: widget.householdId,
              repository: widget.services.households,
              initialAction: initialAction,
            ),
      ),
    );
    if (selected != null && selected != widget.householdId && mounted) {
      Navigator.of(context).pop();
    }
  }
}

enum _DeviceLockAction { useCurrent, configure }

IconData _householdKindIcon(HouseholdKind kind) => switch (kind) {
  HouseholdKind.individual => Icons.person_outline,
  HouseholdKind.family => Icons.family_restroom,
  HouseholdKind.couple => Icons.favorite_outline,
  HouseholdKind.group => Icons.groups_outlined,
};

class _MovementTypePicker extends StatelessWidget {
  const _MovementTypePicker({required this.isCollaborative});

  final bool isCollaborative;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '¿Qué quieres registrar?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              const Text('Elige una opción para abrir el formulario correcto.'),
              const SizedBox(height: 14),
              ...TransactionType.values.map(
                (type) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    key: ValueKey('movement_type_${type.name}'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(child: Icon(_movementTypeIcon(type))),
                    title: Text(
                      _movementTypeLabel(type),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(_movementTypePickerDescription(type)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(type),
                  ),
                ),
              ),
              if (isCollaborative) ...[
                const SizedBox(height: 2),
                const Text(
                  'Para repartir una cuenta entre personas, usa “Dividir gasto” en los accesos de Inicio.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementTypeBanner extends StatelessWidget {
  const _MovementTypeBanner({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: AppShapes.largeRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(_movementTypeIcon(type)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Estás registrando: ${_movementTypeLabel(type)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionForm extends StatefulWidget {
  const _TransactionForm({
    required this.plans,
    required this.transactions,
    required this.customCategories,
    required this.preferredCategories,
    required this.initialType,
    this.initialLinkedPlanId,
    this.initialCategory,
    this.existing,
  });

  final Stream<List<FinancePlan>> plans;
  final Stream<List<FinanceTransaction>> transactions;
  final Stream<List<FinanceCategory>> customCategories;
  final Set<String> preferredCategories;
  final TransactionType initialType;
  final String? initialLinkedPlanId;
  final String? initialCategory;
  final FinanceTransaction? existing;

  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  TransactionType _type = TransactionType.expense;
  String _category = TransactionCategories.expenses.first;
  String? _linkedPlanId;
  ExpenseFundingSource _fundingSource = ExpenseFundingSource.general;
  DateTime _occurredAt = DateTime.now();
  List<FinancePlan> _goals = const [];
  List<FinancePlan> _plans = const [];
  List<FinanceTransaction> _transactions = const [];
  int _budgetCount = 0;
  List<FinanceCategory> _customCategories = const [];
  int _availableSavingsMinor = 0;
  bool _categoryChosen = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = widget.initialType;
    if (existing != null) {
      _descriptionController.text = existing.description;
      _amountController.text = (existing.amountMinor / 100).toStringAsFixed(2);
      _type = existing.type;
      _category = existing.category;
      _categoryChosen = true;
      _linkedPlanId = existing.linkedPlanId;
      _fundingSource = existing.fundingSource;
      _occurredAt = existing.occurredAt;
    } else {
      _category =
          widget.initialCategory ?? TransactionCategories.forType(_type).first;
      _linkedPlanId = widget.initialLinkedPlanId;
      _categoryChosen = widget.initialCategory != null;
    }
    _descriptionController.addListener(_suggestCategory);
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_suggestCategory);
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinancePlan>>(
      stream: widget.plans,
      builder: (context, planSnapshot) {
        final availablePlans = planSnapshot.data ?? const <FinancePlan>[];
        _plans = availablePlans;
        _goals =
            availablePlans
                .where(
                  (plan) => plan.kind == FinancePlanKind.goal && plan.isActive,
                )
                .toList();
        _budgetCount =
            availablePlans
                .where(
                  (plan) =>
                      plan.kind == FinancePlanKind.budget && plan.isActive,
                )
                .length;
        if (_linkedPlanId != null &&
            !_goals.any((plan) => plan.id == _linkedPlanId)) {
          _linkedPlanId = null;
          if (_fundingSource == ExpenseFundingSource.goal) {
            _fundingSource = ExpenseFundingSource.general;
          }
        }
        return StreamBuilder<List<FinanceTransaction>>(
          stream: widget.transactions,
          builder: (context, transactionSnapshot) {
            final transactions =
                (transactionSnapshot.data ?? const <FinanceTransaction>[])
                    .where((item) => item.id != widget.existing?.id)
                    .toList();
            _transactions = transactions;
            _availableSavingsMinor =
                FinanceBalances.calculate(
                  transactions,
                  _goals,
                  currentPeriod: DateTime.now(),
                ).savings;
            return StreamBuilder<List<FinanceCategory>>(
              stream: widget.customCategories,
              builder: (context, categorySnapshot) {
                _customCategories =
                    categorySnapshot.data ?? const <FinanceCategory>[];
                return _buildForm(context);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildForm(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: SizedBox(width: 42, child: Divider(thickness: 4)),
            ),
            const SizedBox(height: 18),
            Text(
              widget.existing == null
                  ? _movementFormTitle(_type)
                  : 'Editar ${_movementTypeLabel(_type).toLowerCase()}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(_movementFormDescription(_type)),
            const SizedBox(height: 14),
            _MovementTypeBanner(type: _type),
            const SizedBox(height: 14),
            TextField(
              key: const Key('transaction_description'),
              controller: _descriptionController,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _movementDescriptionLabel(_type),
                hintText: _movementDescriptionHint(_type),
                prefixIcon: const Icon(Icons.edit_note_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('transaction_amount'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _movementAmountLabel(_type),
                prefixText: '\$ ',
                helperText: 'Dólares de Estados Unidos (USD)',
              ),
            ),
            const SizedBox(height: 12),
            if (_type != TransactionType.expense) ...[
              _goalAllocationField(),
              const SizedBox(height: 12),
            ],
            _TransactionCategoryField(
              category: _category,
              type: _type,
              enabled:
                  !(_type != TransactionType.expense && _linkedPlanId != null),
              automaticallySuggested:
                  !_categoryChosen &&
                  _descriptionController.text.trim().isNotEmpty,
              onTap: _pickCategory,
            ),
            const SizedBox(height: 12),
            _TransactionDateField(date: _occurredAt, onTap: _pickDate),
            const SizedBox(height: 12),
            if (_type == TransactionType.expense) _expenseSourceField(),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save_transaction'),
              onPressed: _save,
              icon: const Icon(Icons.enhanced_encryption_outlined),
              label: Text(
                widget.existing == null
                    ? 'Revisar y guardar'
                    : 'Revisar cambios',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expenseSourceField() {
    final selectedValue =
        _fundingSource == ExpenseFundingSource.goal && _linkedPlanId != null
            ? 'goal:$_linkedPlanId'
            : _fundingSource.name;
    return DropdownButtonFormField<String>(
      value: selectedValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '¿De dónde salió el dinero?',
        helperText: 'El gasto se descontará únicamente de este saldo.',
      ),
      items: [
        const DropdownMenuItem(
          value: 'general',
          child: Text('Saldo disponible del espacio'),
        ),
        DropdownMenuItem(
          value: 'savings',
          child: Text('Ahorros · ${_money(_availableSavingsMinor)}'),
        ),
        ..._goals.map(
          (plan) => DropdownMenuItem(
            value: 'goal:${plan.id}',
            child: Text(
              'Meta: ${plan.name} · ${_money(plan.currentMinor)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          if (value == 'savings') {
            _fundingSource = ExpenseFundingSource.savings;
            _linkedPlanId = null;
          } else if (value.startsWith('goal:')) {
            _fundingSource = ExpenseFundingSource.goal;
            _linkedPlanId = value.substring(5);
          } else {
            _fundingSource = ExpenseFundingSource.general;
            _linkedPlanId = null;
          }
        });
      },
    );
  }

  Widget _goalAllocationField() {
    if (_goals.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppShapes.largeRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _budgetCount > 0
                      ? 'Tienes $_budgetCount presupuesto${_budgetCount == 1 ? '' : 's'}, pero ninguna meta de ahorro. Los presupuestos no aparecen aquí porque controlan gastos. Crea una “Meta de ahorro” desde Planes.'
                      : 'No hay metas activas. Crea una “Meta de ahorro” desde Planes para asignarle dinero.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return DropdownButtonFormField<String?>(
      key: const Key('transaction_goal'),
      value: _linkedPlanId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText:
            _type == TransactionType.income
                ? '¿Este ingreso va a una meta?'
                : '¿A qué meta va este ahorro?',
        helperText:
            _type == TransactionType.income
                ? 'La parte asignada aumentará la meta y no quedará como saldo disponible.'
                : 'Al guardar, el avance de la meta aumentará automáticamente.',
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('No asignar a una meta'),
        ),
        ..._goals.map(
          (plan) => DropdownMenuItem<String?>(
            value: plan.id,
            child: Text(
              '${plan.name} · ${_money(plan.currentMinor)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _linkedPlanId = value),
    );
  }

  Future<void> _save() async {
    final amount = _parseMoneyMinor(_amountController.text);
    final description = _descriptionController.text.trim();
    if (amount == null || amount <= 0 || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa una descripción y un monto válido.'),
        ),
      );
      return;
    }
    if (amount > 99999999999) {
      _showError('El monto supera el máximo permitido por movimiento.');
      return;
    }
    if (_type == TransactionType.expense &&
        _fundingSource == ExpenseFundingSource.savings &&
        amount > _availableSavingsMinor) {
      _showError('Tus ahorros no alcanzan para cubrir este gasto.');
      return;
    }
    final linkedPlan =
        _linkedPlanId == null
            ? null
            : _goals.cast<FinancePlan?>().firstWhere(
              (plan) => plan?.id == _linkedPlanId,
              orElse: () => null,
            );
    if (_type == TransactionType.expense &&
        _fundingSource == ExpenseFundingSource.goal &&
        linkedPlan == null) {
      _showError('Selecciona la meta de la que salió el dinero.');
      return;
    }
    final guidance = evaluateTransactionGuidance(
      type: _type,
      description: description,
      category: _category,
      amountMinor: amount,
      occurredAt: _occurredAt,
      fundingSource: _fundingSource,
      transactions: _transactions,
      plans: _plans,
      linkedPlan: linkedPlan,
    );
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (_) => _MovementReviewSheet(
            description: description,
            category: _category,
            amountMinor: amount,
            type: _type,
            occurredAt: _occurredAt,
            linkedPlan: linkedPlan,
            fundingSource: _fundingSource,
            editing: widget.existing != null,
            guidance: guidance,
          ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(
      _TransactionInput(
        description: description,
        category: _category,
        amountMinor: amount,
        type: _type,
        linkedPlan: linkedPlan,
        fundingSource: _fundingSource,
        occurredAt: _occurredAt,
        shared: false,
        paidByUid: null,
        splitMode: ExpenseSplitMode.equal,
        participantSharesMinor: const {},
        guidance: guidance,
      ),
    );
  }

  Future<void> _pickDate() async {
    final selection = await showModalBottomSheet<_TransactionDateSelection>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '¿Cuándo ocurrió?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Usa Programar para pagos o ingresos que todavía no han ocurrido.',
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    leading: const Icon(Icons.today_outlined),
                    title: const Text('Hoy'),
                    subtitle: Text(_friendlyDate(DateTime.now())),
                    trailing:
                        _isSameDay(_occurredAt, DateTime.now())
                            ? const Icon(Icons.check_circle)
                            : null,
                    onTap:
                        () => Navigator.pop(
                          context,
                          _TransactionDateSelection.today,
                        ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: const Text('Ayer'),
                    subtitle: Text(
                      _friendlyDate(
                        DateTime.now().subtract(const Duration(days: 1)),
                      ),
                    ),
                    trailing:
                        _isSameDay(
                              _occurredAt,
                              DateTime.now().subtract(const Duration(days: 1)),
                            )
                            ? const Icon(Icons.check_circle)
                            : null,
                    onTap:
                        () => Navigator.pop(
                          context,
                          _TransactionDateSelection.yesterday,
                        ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Elegir otra fecha'),
                    subtitle: const Text('Consulta el calendario'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => Navigator.pop(
                          context,
                          _TransactionDateSelection.custom,
                        ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (selection == null || !mounted) return;
    final now = DateTime.now();
    if (selection != _TransactionDateSelection.custom) {
      final selected =
          selection == _TransactionDateSelection.today
              ? now
              : now.subtract(const Duration(days: 1));
      setState(() => _setOccurredDay(selected));
      return;
    }
    final today = DateTime(now.year, now.month, now.day);
    final current = DateTime(
      _occurredAt.year,
      _occurredAt.month,
      _occurredAt.day,
    );
    final date = await showDatePicker(
      context: context,
      locale: const Locale('es', 'EC'),
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(1),
      lastDate: today,
      helpText: 'FECHA DEL MOVIMIENTO',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
    );
    if (date != null && mounted) {
      setState(() => _setOccurredDay(date));
    }
  }

  void _setOccurredDay(DateTime value) {
    _occurredAt = DateTime(
      value.year,
      value.month,
      value.day,
      _occurredAt.hour,
      _occurredAt.minute,
    );
  }

  Future<void> _pickCategory() async {
    final categories = _categoriesForType(_type);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (_) => _CategoryPickerSheet(
            type: _type,
            categories: categories,
            customCategories:
                _customCategories
                    .where((category) => category.type == _type)
                    .map((category) => category.name)
                    .toSet(),
            selected: _category,
            suggested:
                _descriptionController.text.trim().isEmpty
                    ? null
                    : TransactionCategories.suggestFor(
                      _type,
                      _descriptionController.text,
                    ),
          ),
    );
    if (selected != null && mounted) {
      setState(() {
        _category = selected;
        _categoryChosen = true;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _suggestCategory() {
    if (_categoryChosen || !mounted) return;
    final suggestion = TransactionCategories.suggestFor(
      _type,
      _descriptionController.text,
    );
    if (suggestion != _category) setState(() => _category = suggestion);
  }

  List<String> _categoriesForType(TransactionType type) {
    final defaults = TransactionCategories.forType(type);
    final enabledDefaults =
        widget.preferredCategories.isEmpty
            ? defaults
            : defaults.where(widget.preferredCategories.contains);
    final values =
        {
          ...enabledDefaults,
          ..._customCategories
              .where((category) => category.type == type)
              .map((category) => category.name),
          if (_type == type) _category,
        }.toList();
    values.sort();
    return values;
  }
}

class _TransactionCategoryField extends StatelessWidget {
  const _TransactionCategoryField({
    required this.category,
    required this.type,
    required this.enabled,
    required this.automaticallySuggested,
    required this.onTap,
  });

  final String category;
  final TransactionType type;
  final bool enabled;
  final bool automaticallySuggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(borderRadius: AppShapes.mediumRadius),
      child: InkWell(
        key: const Key('transaction_category'),
        onTap: enabled ? onTap : null,
        borderRadius: AppShapes.mediumRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  _categoryIcon(category),
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categoría de ${_movementTypeLabel(type).toLowerCase()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? automaticallySuggested
                              ? 'Sugerida según la descripción · toca para cambiar'
                              : 'Toca para elegir otra categoría'
                          : 'Definida por la meta seleccionada',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(enabled ? Icons.chevron_right : Icons.lock_outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.type,
    required this.categories,
    required this.customCategories,
    required this.selected,
    required this.suggested,
  });

  final TransactionType type;
  final List<String> categories;
  final Set<String> customCategories;
  final String selected;
  final String? suggested;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible =
        widget.categories
            .where((category) => category.toLowerCase().contains(query))
            .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Elige una categoría',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Esto mejora tus reportes de ${_movementTypeLabel(widget.type).toLowerCase()}s.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Buscar categoría',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon:
                        query.isEmpty
                            ? null
                            : IconButton(
                              onPressed: _searchController.clear,
                              tooltip: 'Limpiar búsqueda',
                              icon: const Icon(Icons.close),
                            ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                visible.isEmpty
                    ? const Center(
                      child: Text('No hay categorías coincidentes.'),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final category = visible[index];
                        final selected = category == widget.selected;
                        final suggested = category == widget.suggested;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(_categoryIcon(category), size: 20),
                          ),
                          title: Text(
                            category,
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w600,
                            ),
                          ),
                          subtitle:
                              widget.customCategories.contains(category)
                                  ? const Text('Categoría personalizada')
                                  : suggested
                                  ? const Text('Sugerida por la descripción')
                                  : null,
                          trailing:
                              selected
                                  ? const Icon(Icons.check_circle)
                                  : suggested
                                  ? const Icon(Icons.auto_awesome, size: 20)
                                  : null,
                          onTap: () => Navigator.pop(context, category),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _TransactionDateField extends StatelessWidget {
  const _TransactionDateField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(borderRadius: AppShapes.mediumRadius),
      child: InkWell(
        key: const Key('transaction_date'),
        onTap: onTap,
        borderRadius: AppShapes.mediumRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fecha del movimiento',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _friendlyDate(date),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Los movimientos futuros se crean desde Programar',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementReviewSheet extends StatelessWidget {
  const _MovementReviewSheet({
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.type,
    required this.occurredAt,
    required this.linkedPlan,
    required this.fundingSource,
    required this.editing,
    required this.guidance,
  });

  final String description;
  final String category;
  final int amountMinor;
  final TransactionType type;
  final DateTime occurredAt;
  final FinancePlan? linkedPlan;
  final ExpenseFundingSource fundingSource;
  final bool editing;
  final FinancialGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final effect = switch (type) {
      TransactionType.expense
          when fundingSource == ExpenseFundingSource.savings =>
        'Se descontará únicamente de tus ahorros.',
      TransactionType.expense when fundingSource == ExpenseFundingSource.goal =>
        'Se descontará de la meta ${linkedPlan?.name ?? 'seleccionada'}.',
      TransactionType.expense =>
        'Se descontará del saldo disponible del espacio.',
      TransactionType.income when linkedPlan != null =>
        'Aumentará la meta ${linkedPlan!.name} y no quedará disponible para gastar.',
      TransactionType.income => 'Aumentará el saldo disponible del espacio.',
      TransactionType.saving when linkedPlan != null =>
        'Aumentará el avance de la meta ${linkedPlan!.name}.',
      TransactionType.saving =>
        'Quedará separado como ahorro y reducirá el dinero disponible para gastar.',
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? 'Revisa los cambios' : 'Revisa antes de guardar',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Confirma que el monto, la fecha y el efecto sean correctos.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  _TransactionDetailRow(
                    label: 'Descripción',
                    value: description,
                  ),
                  const Divider(height: 1),
                  _TransactionDetailRow(
                    label: 'Monto',
                    value: _money(amountMinor),
                  ),
                  const Divider(height: 1),
                  _TransactionDetailRow(label: 'Categoría', value: category),
                  const Divider(height: 1),
                  _TransactionDetailRow(
                    label: 'Fecha',
                    value: _longSpanishDate(occurredAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Efecto en tus finanzas'),
                subtitle: Text(effect),
              ),
            ),
            const SizedBox(height: 10),
            _FinancialGuidanceCard(guidance: guidance),
            const SizedBox(height: 12),
            const Text(
              'El registro se cifra antes de sincronizarse. Conserva aparte tus comprobantes bancarios o tributarios.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.lock_outline),
              label: Text(
                editing ? 'Confirmar cambios' : 'Confirmar y guardar',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver a revisar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialGuidanceCard extends StatelessWidget {
  const _FinancialGuidanceCard({required this.guidance});

  final FinancialGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, foreground, icon) = switch (guidance.tone) {
      FinancialGuidanceTone.critical => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning_amber_rounded,
      ),
      FinancialGuidanceTone.caution => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.speed_outlined,
      ),
      FinancialGuidanceTone.positive => (
        AppColors.accessibleGreen.withValues(alpha: .16),
        scheme.onSurface,
        Icons.celebration_outlined,
      ),
      FinancialGuidanceTone.informative => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.lightbulb_outline,
      ),
    };
    return Card(
      key: const Key('financial_guidance'),
      color: color,
      child: ListTile(
        leading: Icon(icon, color: foreground),
        title: Text(
          guidance.title,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
        ),
        subtitle: Text(guidance.message, style: TextStyle(color: foreground)),
      ),
    );
  }
}

class _PlanForm extends StatefulWidget {
  const _PlanForm({this.existing});

  final FinancePlan? existing;

  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  FinancePlanKind? _kind;
  String _category = TransactionCategories.expenses.first;
  DateTime? _deadline;
  double _alertThreshold = 0.8;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _targetController = TextEditingController(
      text:
          existing == null
              ? ''
              : (existing.targetMinor / 100).toStringAsFixed(2),
    );
    _kind = existing?.kind;
    _category =
        existing?.category != null &&
                TransactionCategories.expenses.contains(existing!.category)
            ? existing.category!
            : TransactionCategories.expenses.first;
    _deadline = existing?.deadline;
    _alertThreshold = existing?.alertThreshold ?? 0.8;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: SizedBox(width: 42, child: Divider(thickness: 4)),
            ),
            const SizedBox(height: 18),
            Text(
              widget.existing == null ? 'Nuevo plan' : 'Editar plan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.existing == null
                  ? 'Primero elige qué quieres controlar.'
                  : 'El tipo del plan se conserva para proteger su historial.',
            ),
            const SizedBox(height: 14),
            if (widget.existing == null) ...[
              _PlanKindOption(
                key: const Key('plan_kind_budget'),
                selected: _kind == FinancePlanKind.budget,
                icon: Icons.account_balance_wallet_outlined,
                title: 'Presupuesto mensual',
                description:
                    'Define un límite de gasto. Los ingresos no llenan esta barra.',
                onTap: () => setState(() => _kind = FinancePlanKind.budget),
              ),
              const SizedBox(height: 9),
              _PlanKindOption(
                key: const Key('plan_kind_goal'),
                selected: _kind == FinancePlanKind.goal,
                icon: Icons.flag_outlined,
                title: 'Meta de ahorro',
                description:
                    'Reúne dinero poco a poco asignando ingresos o ahorros.',
                onTap:
                    () => setState(() {
                      _kind = FinancePlanKind.goal;
                      _deadline ??= DateTime.now().add(
                        const Duration(days: 90),
                      );
                    }),
              ),
            ] else
              _PlanKindOption(
                selected: _kind == FinancePlanKind.budget,
                icon:
                    _kind == FinancePlanKind.goal
                        ? Icons.flag_outlined
                        : Icons.account_balance_wallet_outlined,
                title:
                    _kind == FinancePlanKind.goal
                        ? 'Meta de ahorro'
                        : 'Presupuesto mensual',
                description: 'Tipo protegido para conservar la trazabilidad.',
                onTap: () {},
              ),
            if (_kind != null) ...[
              const SizedBox(height: 18),
              Text(
                _kind == FinancePlanKind.goal
                    ? 'Configura tu meta'
                    : 'Configura tu presupuesto',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText:
                      _kind == FinancePlanKind.goal
                          ? 'Nombre de la meta'
                          : 'Nombre del presupuesto',
                  hintText:
                      _kind == FinancePlanKind.goal
                          ? 'Ej. Vacaciones al Caribe'
                          : 'Ej. Alimentación del mes',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      _kind == FinancePlanKind.goal
                          ? '¿Cuánto quieres reunir?'
                          : 'Límite mensual',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 12),
              if (_kind == FinancePlanKind.budget) ...[
                DropdownButtonFormField<String>(
                  value: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoría del presupuesto',
                    helperText:
                        'Los gastos del mes se sumarán automáticamente.',
                  ),
                  items:
                      TransactionCategories.expenses
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                  onChanged:
                      (value) => setState(() => _category = value ?? _category),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  value: _alertThreshold,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Avisarme al llegar a',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0.7, child: Text('70% utilizado')),
                    DropdownMenuItem(value: 0.8, child: Text('80% utilizado')),
                    DropdownMenuItem(value: 0.9, child: Text('90% utilizado')),
                    DropdownMenuItem(value: 1.0, child: Text('100% utilizado')),
                  ],
                  onChanged:
                      (value) => setState(() => _alertThreshold = value ?? 0.8),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _pickDeadline,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    _deadline == null
                        ? 'Elegir fecha límite'
                        : 'Fecha límite: ${DateFormat('dd/MM/yyyy').format(_deadline!)}',
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.enhanced_encryption_outlined),
                label: Text(
                  widget.existing != null
                      ? 'Guardar cambios'
                      : _kind == FinancePlanKind.goal
                      ? 'Crear meta de ahorro'
                      : 'Crear presupuesto mensual',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _save() {
    final target = _parseMoneyMinor(_targetController.text);
    final name = _nameController.text.trim();
    if (_kind == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elige presupuesto mensual o meta de ahorro.'),
        ),
      );
      return;
    }
    if (target == null || target <= 0 || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa un nombre y un objetivo válidos.'),
        ),
      );
      return;
    }
    if (_kind == FinancePlanKind.goal && _deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige la fecha límite de la meta.')),
      );
      return;
    }
    Navigator.of(context).pop(
      _PlanInput(
        name: name,
        kind: _kind!,
        targetMinor: target,
        category: _kind == FinancePlanKind.budget ? _category : null,
        deadline: _kind == FinancePlanKind.goal ? _deadline : null,
        alertThreshold: _alertThreshold,
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial =
        _deadline == null || _deadline!.isBefore(today) ? today : _deadline!;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 20),
      helpText: 'Fecha límite de la meta',
    );
    if (value != null && mounted) setState(() => _deadline = value);
  }
}

class _PlanKindOption extends StatelessWidget {
  const _PlanKindOption({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: AppShapes.largeRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.largeRadius,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? scheme.primary : null),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(description),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoUrl?.isNotEmpty == true;
    return CircleAvatar(
      backgroundColor: AppColors.blushPinkLight,
      foregroundColor: AppColors.blushPinkDark,
      backgroundImage: hasPhoto ? NetworkImage(user.photoUrl!) : null,
      child:
          hasPhoto
              ? null
              : Text(
                _initials(user.displayName),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction, this.onTap});

  final FinanceTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == TransactionType.income;
    final saving = transaction.type == TransactionType.saving;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color =
        income
            ? (dark ? AppColors.mint : AppColors.deepMint)
            : saving
            ? scheme.secondary
            : scheme.error;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: dark ? 0.18 : 0.12),
          foregroundColor: color,
          child: Icon(
            income
                ? Icons.south_west
                : saving
                ? Icons.savings_outlined
                : Icons.north_east,
          ),
        ),
        title: Text(
          transaction.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${transaction.category} · ${DateFormat('dd/MM/yyyy').format(transaction.occurredAt)}',
              ),
              if (transaction.origin == TransactionOrigin.imported)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        transaction.sourceVerified
                            ? Icons.verified_outlined
                            : Icons.file_upload_outlined,
                        size: 14,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          transaction.sourceName ?? 'Archivo importado',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (transaction.linkedPlanName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Meta: ${transaction.linkedPlanName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 106),
          child: Text(
            '${income
                ? '+'
                : saving
                ? '→'
                : '−'}${_money(transaction.amountMinor)}',
            textAlign: TextAlign.end,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StreamError extends StatelessWidget {
  const _StreamError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              'No se pudieron cargar los datos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TransactionInput {
  const _TransactionInput({
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.type,
    required this.fundingSource,
    required this.occurredAt,
    required this.shared,
    required this.splitMode,
    required this.participantSharesMinor,
    required this.guidance,
    this.linkedPlan,
    this.paidByUid,
  });

  final String description;
  final String category;
  final int amountMinor;
  final TransactionType type;
  final FinancePlan? linkedPlan;
  final ExpenseFundingSource fundingSource;
  final DateTime occurredAt;
  final bool shared;
  final String? paidByUid;
  final ExpenseSplitMode splitMode;
  final Map<String, int> participantSharesMinor;
  final FinancialGuidance guidance;
}

class _PlanInput {
  const _PlanInput({
    required this.name,
    required this.kind,
    required this.targetMinor,
    required this.alertThreshold,
    this.category,
    this.deadline,
  });

  final String name;
  final FinancePlanKind kind;
  final int targetMinor;
  final String? category;
  final DateTime? deadline;
  final double alertThreshold;
}

enum _TransactionDateSelection { today, yesterday, custom }

bool _isSameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _friendlyDate(DateTime date) {
  final now = DateTime.now();
  final prefix =
      _isSameDay(date, now)
          ? 'Hoy · '
          : _isSameDay(date, now.subtract(const Duration(days: 1)))
          ? 'Ayer · '
          : '';
  return '$prefix${_longSpanishDate(date, includeWeekday: true)}';
}

String _longSpanishDate(DateTime date, {bool includeWeekday = false}) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  const weekdays = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  final value = '${date.day} de ${months[date.month - 1]} de ${date.year}';
  if (!includeWeekday) return value;
  final weekday = weekdays[date.weekday - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)}, $value';
}

String _monthYearLabel(DateTime date) {
  const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

IconData _categoryIcon(String category) => switch (category) {
  'Alimentación' || 'Comida y restaurantes' => Icons.restaurant_outlined,
  'Vivienda' || 'Vivienda futura' || 'Arriendo' => Icons.home_outlined,
  'Servicios' || 'Servicios básicos' => Icons.receipt_long_outlined,
  'Transporte' => Icons.directions_bus_outlined,
  'Salud' => Icons.health_and_safety_outlined,
  'Educación' => Icons.school_outlined,
  'Entretenimiento' => Icons.movie_outlined,
  'Ropa y accesorios' || 'Compras' => Icons.shopping_bag_outlined,
  'Deudas' || 'Préstamos recibidos' => Icons.payments_outlined,
  'Sueldo' || 'Honorarios' || 'Bonos' => Icons.work_outline,
  'Negocio' || 'Ventas' => Icons.storefront_outlined,
  'Intereses' || 'Inversión' => Icons.trending_up,
  'Reembolsos' => Icons.currency_exchange,
  'Fondo de emergencia' => Icons.shield_outlined,
  'Vacaciones' || 'Viaje' => Icons.flight_outlined,
  'Meta personal' => Icons.flag_outlined,
  _ => Icons.category_outlined,
};

String _movementTypeLabel(TransactionType type) => switch (type) {
  TransactionType.expense => 'Gasto',
  TransactionType.income => 'Ingreso',
  TransactionType.saving => 'Ahorro',
};

IconData _movementTypeIcon(TransactionType type) => switch (type) {
  TransactionType.expense => Icons.shopping_bag_outlined,
  TransactionType.income => Icons.add_card_outlined,
  TransactionType.saving => Icons.savings_outlined,
};

String _movementTypePickerDescription(TransactionType type) => switch (type) {
  TransactionType.expense => 'Dinero que salió para una compra o pago.',
  TransactionType.income => 'Dinero que recibiste, como sueldo o venta.',
  TransactionType.saving => 'Dinero que apartaste para el futuro.',
};

String _movementFormTitle(TransactionType type) => switch (type) {
  TransactionType.expense => 'Registrar un gasto',
  TransactionType.income => 'Registrar un ingreso',
  TransactionType.saving => 'Registrar un ahorro',
};

String _movementFormDescription(TransactionType type) => switch (type) {
  TransactionType.expense => 'Anota qué pagaste y de qué saldo salió.',
  TransactionType.income => 'Anota de dónde llegó el dinero.',
  TransactionType.saving => 'Anota cuánto dinero decidiste apartar.',
};

String _movementDescriptionLabel(TransactionType type) => switch (type) {
  TransactionType.expense => '¿En qué gastaste?',
  TransactionType.income => '¿De dónde vino el ingreso?',
  TransactionType.saving => '¿Para qué estás ahorrando?',
};

String _movementDescriptionHint(TransactionType type) => switch (type) {
  TransactionType.expense => 'Ej. Compra del supermercado',
  TransactionType.income => 'Ej. Sueldo de agosto',
  TransactionType.saving => 'Ej. Fondo de emergencia',
};

String _movementAmountLabel(TransactionType type) => switch (type) {
  TransactionType.expense => '¿Cuánto pagaste?',
  TransactionType.income => '¿Cuánto recibiste?',
  TransactionType.saving => '¿Cuánto apartaste?',
};

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);

int? _parseMoneyMinor(String input) {
  var value = input.trim().replaceAll(RegExp(r'[^0-9,\.]'), '');
  if (value.isEmpty) return null;
  final lastComma = value.lastIndexOf(',');
  final lastDot = value.lastIndexOf('.');
  final decimalIndex = lastComma > lastDot ? lastComma : lastDot;
  String whole;
  String decimals;
  if (decimalIndex >= 0 && value.length - decimalIndex - 1 <= 2) {
    whole = value.substring(0, decimalIndex).replaceAll(RegExp(r'[,\.]'), '');
    decimals = value.substring(decimalIndex + 1);
  } else {
    whole = value.replaceAll(RegExp(r'[,\.]'), '');
    decimals = '';
  }
  if (whole.isEmpty) whole = '0';
  if (!RegExp(r'^\d+$').hasMatch(whole) ||
      (decimals.isNotEmpty && !RegExp(r'^\d{1,2}$').hasMatch(decimals))) {
    return null;
  }
  final paddedDecimals = decimals.padRight(2, '0');
  return int.tryParse(whole) == null
      ? null
      : int.parse(whole) * 100 +
          (paddedDecimals.isEmpty ? 0 : int.parse(paddedDecimals));
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty);
  final initials = words.take(2).map((value) => value[0].toUpperCase()).join();
  return initials.isEmpty ? 'HW' : initials;
}

String _errorText(Object? error) => switch (error) {
  AppException value => value.message,
  _ => 'Revisa tu conexión o los permisos del espacio.',
};
