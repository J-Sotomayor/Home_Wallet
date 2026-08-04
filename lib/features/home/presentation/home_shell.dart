import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../app/theme/theme_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../about/presentation/about_homewallet_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../households/domain/household_models.dart';
import '../../households/presentation/family_invite_screen.dart';
import '../../households/presentation/household_members_screen.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../transactions/domain/transaction_categories.dart';
import '../../transactions/domain/finance_balances.dart';
import '../../transactions/domain/finance_models.dart';
import '../../transactions/presentation/data_tools_screen.dart';
import '../../transactions/presentation/categories_screen.dart';
import '../../transactions/presentation/finance_insights.dart';
import '../../transactions/presentation/finance_reports_tab.dart';
import '../../transactions/presentation/recurring_transactions_screen.dart';
import '../../transactions/presentation/shared_debts_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.user,
    required this.householdId,
    required this.services,
    required this.themeController,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final ThemeController themeController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final notifications = widget.services.notifications;
    if (notifications != null) {
      unawaited(notifications.registerUser(widget.user.uid));
    }
  }

  @override
  void dispose() {
    final notifications = widget.services.notifications;
    if (notifications != null) {
      unawaited(notifications.unregisterUser(widget.user.uid));
    }
    super.dispose();
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
            onAdd: () => _showTransactionForm(context),
            onOpenProfile: _openProfile,
            canContribute: canContribute,
          ),
          _TransactionsTab(
            user: widget.user,
            householdId: widget.householdId,
            services: widget.services,
            canContribute: canContribute,
            onEdit:
                (transaction) =>
                    _showTransactionForm(context, existing: transaction),
          ),
          FinanceReportsTab(
            householdId: widget.householdId,
            repository: widget.services.finance,
            members: widget.services.households.watchMembers(
              widget.householdId,
            ),
          ),
          _PlansTab(
            user: widget.user,
            householdId: widget.householdId,
            services: widget.services,
            canContribute: canContribute,
          ),
          _MoreTab(
            user: widget.user,
            householdId: widget.householdId,
            services: widget.services,
            themeController: widget.themeController,
            household: household,
          ),
        ];

        return Scaffold(
          body: IndexedStack(index: _index, children: pages),
          floatingActionButton:
              canContribute && _index <= 1
                  ? FloatingActionButton.extended(
                    onPressed: () => _showTransactionForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Movimiento'),
                  )
                  : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Movimientos',
              ),
              NavigationDestination(
                icon: Icon(Icons.query_stats_outlined),
                selectedIcon: Icon(Icons.query_stats),
                label: 'Reportes',
              ),
              NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: 'Planes',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more),
                label: 'Más',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showTransactionForm(
    BuildContext context, {
    FinanceTransaction? existing,
  }) async {
    final input = await showModalBottomSheet<_TransactionInput>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => _TransactionForm(
            plans: widget.services.finance.watchPlans(widget.householdId),
            transactions: widget.services.finance.watchTransactions(
              widget.householdId,
            ),
            members: widget.services.households.watchMembers(
              widget.householdId,
            ),
            customCategories: widget.services.finance.watchCategories(
              widget.householdId,
            ),
            currentUid: widget.user.uid,
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
        _showMessage('Movimiento cifrado y guardado.');
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
        transactions: values[0] as List<FinanceTransaction>,
        plans: values[1] as List<FinancePlan>,
      );
    } catch (_) {
      // Las alertas no deben bloquear el guardado del movimiento.
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.onAdd,
    required this.onOpenProfile,
    required this.canContribute,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final VoidCallback onAdd;
  final VoidCallback onOpenProfile;
  final bool canContribute;

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
              final transactions = transactionSnapshot.data!;
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
                  final balances = FinanceBalances.calculate(
                    transactions,
                    planSnapshot.data!,
                  );
                  return RefreshIndicator(
                    onRefresh: () async {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 350),
                      );
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    household.name,
                                    style:
                                        Theme.of(
                                          context,
                                        ).textTheme.headlineSmall,
                                  ),
                                  Text(
                                    '${household.memberCount} ${household.memberCount == 1 ? 'integrante' : 'integrantes'} · datos cifrados',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
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
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primaryBlue,
                                AppColors.primaryBlueDark,
                              ],
                            ),
                            borderRadius: AppShapes.extraLargeRadius,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Saldo disponible',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _money(balances.available),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: _SummaryValue(
                                      label: 'Ingresos',
                                      value: _money(balances.income),
                                      icon: Icons.south_west,
                                    ),
                                  ),
                                  Expanded(
                                    child: _SummaryValue(
                                      label: 'Ahorros',
                                      value: _money(balances.savings),
                                      icon: Icons.savings_outlined,
                                    ),
                                  ),
                                  Expanded(
                                    child: _SummaryValue(
                                      label: 'Metas',
                                      value: _money(balances.goals),
                                      icon: Icons.flag_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Gastos del período: ${_money(balances.expenses)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (balances.uncoveredExpenses > 0) ...[
                          const SizedBox(height: 12),
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: Icon(
                                Icons.warning_amber_rounded,
                                color: Theme.of(context).colorScheme.error,
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
                        const SizedBox(height: 18),
                        FinanceInsights(transactions: transactions),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Text(
                              'Actividad reciente',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Agregar movimiento',
                              onPressed: canContribute ? onAdd : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (transactions.isEmpty)
                          _EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'Aún no hay movimientos',
                            description:
                                'El hogar inicia vacío. Agrega tu primer ingreso o gasto real.',
                            actionLabel:
                                canContribute ? 'Agregar movimiento' : null,
                            onAction: canContribute ? onAdd : null,
                          )
                        else
                          ...transactions
                              .take(5)
                              .map(
                                (transaction) =>
                                    _TransactionTile(transaction: transaction),
                              ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.canContribute,
    required this.onEdit,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final bool canContribute;
  final ValueChanged<FinanceTransaction> onEdit;

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  final _searchController = TextEditingController();
  TransactionType? _filter;
  DateTimeRange? _dateRange;
  String? _category;
  String? _createdBy;
  bool? _shared;
  bool _showAdvanced = false;

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

  void _refresh() {
    if (mounted) setState(() {});
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
          final all = snapshot.data!;
          return StreamBuilder<List<HouseholdMember>>(
            stream: widget.services.households.watchMembers(widget.householdId),
            builder: (context, memberSnapshot) {
              final members = memberSnapshot.data ?? const <HouseholdMember>[];
              final availableCategories =
                  {
                      ...TransactionCategories.all,
                      ...all.map((item) => item.category),
                    }.toList()
                    ..sort();
              final query = _searchController.text.trim().toLowerCase();
              final visible =
                  all.where((item) {
                    if (_filter != null && item.type != _filter) return false;
                    if (_category != null && item.category != _category) {
                      return false;
                    }
                    if (_createdBy != null && item.createdBy != _createdBy) {
                      return false;
                    }
                    if (_shared != null && item.shared != _shared) return false;
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
                      if (day.isBefore(start) || day.isAfter(end)) return false;
                    }
                    return query.isEmpty ||
                        item.description.toLowerCase().contains(query) ||
                        item.category.toLowerCase().contains(query);
                  }).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
                children: [
                  Text(
                    'Movimientos',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ingresos, gastos y ahorros del hogar, cifrados en el dispositivo.',
                  ),
                  const SizedBox(height: 18),
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
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      ChoiceChip(
                        label: const Text('Ingresos'),
                        selected: _filter == TransactionType.income,
                        onSelected:
                            (_) => setState(
                              () => _filter = TransactionType.income,
                            ),
                      ),
                      ChoiceChip(
                        label: const Text('Gastos'),
                        selected: _filter == TransactionType.expense,
                        onSelected:
                            (_) => setState(
                              () => _filter = TransactionType.expense,
                            ),
                      ),
                      ChoiceChip(
                        label: const Text('Ahorros'),
                        selected: _filter == TransactionType.saving,
                        onSelected:
                            (_) => setState(
                              () => _filter = TransactionType.saving,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed:
                          () => setState(() => _showAdvanced = !_showAdvanced),
                      icon: Icon(
                        _showAdvanced ? Icons.expand_less : Icons.tune,
                      ),
                      label: Text(
                        _hasAdvancedFilters ? 'Filtros activos' : 'Más filtros',
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
                                  (value) => setState(() => _category = value),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String?>(
                              value: _createdBy,
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
                                    child: Text(member.displayName),
                                  ),
                                ),
                              ],
                              onChanged:
                                  (value) => setState(() => _createdBy = value),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<bool?>(
                              value: _shared,
                              decoration: const InputDecoration(
                                labelText: 'Alcance',
                              ),
                              items: const [
                                DropdownMenuItem<bool?>(
                                  value: null,
                                  child: Text('Personal y compartido'),
                                ),
                                DropdownMenuItem<bool?>(
                                  value: false,
                                  child: Text('Personal'),
                                ),
                                DropdownMenuItem<bool?>(
                                  value: true,
                                  child: Text('Compartido'),
                                ),
                              ],
                              onChanged:
                                  (value) => setState(() => _shared = value),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _pickDateRange,
                                    icon: const Icon(Icons.date_range_outlined),
                                    label: Text(
                                      _dateRange == null
                                          ? 'Elegir período'
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
                  if (visible.isEmpty)
                    const _EmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'No hay resultados',
                      description: 'No existen movimientos para este filtro.',
                    )
                  else
                    ...visible.map(
                      (transaction) => Dismissible(
                        key: ValueKey(transaction.id),
                        direction:
                            widget.canContribute &&
                                    transaction.createdBy == widget.user.uid
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                        confirmDismiss: (_) => _confirmDelete(context),
                        onDismissed:
                            (_) => widget.services.finance.deleteTransaction(
                              widget.householdId,
                              transaction,
                            ),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: AppShapes.largeRadius,
                          onTap:
                              widget.canContribute &&
                                      transaction.createdBy == widget.user.uid
                                  ? () => widget.onEdit(transaction)
                                  : null,
                          child: _TransactionTile(transaction: transaction),
                        ),
                      ),
                    ),
                ],
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
      _createdBy != null ||
      _shared != null;

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: _dateRange,
      helpText: 'Filtrar movimientos por fecha',
    );
    if (range != null && mounted) setState(() => _dateRange = range);
  }

  void _clearAdvancedFilters() {
    setState(() {
      _dateRange = null;
      _category = null;
      _createdBy = null;
      _shared = null;
    });
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Eliminar movimiento'),
              content: const Text(
                'Esta acción lo eliminará para todos los integrantes del hogar.',
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
}

class _PlansTab extends StatelessWidget {
  const _PlansTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.canContribute,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final bool canContribute;

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
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Presupuestos y metas',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Nuevo plan',
                        onPressed:
                            canContribute ? () => _addPlan(context) : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'El avance se calcula automáticamente con tus movimientos.',
                  ),
                  const SizedBox(height: 20),
                  if (plans.isEmpty)
                    _EmptyState(
                      icon: Icons.savings_outlined,
                      title: 'Aún no tienes planes',
                      description: 'Crea un presupuesto o una meta de ahorro.',
                      actionLabel: canContribute ? 'Crear plan' : null,
                      onAction: canContribute ? () => _addPlan(context) : null,
                    )
                  else
                    ...plans.map(
                      (plan) => _planCard(context, plan, transactions),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _planCard(
    BuildContext context,
    FinancePlan plan,
    List<FinanceTransaction> transactions,
  ) {
    final current = automaticPlanProgress(plan, transactions, DateTime.now());
    final progress = plan.targetMinor == 0 ? 0.0 : current / plan.targetMinor;
    final remaining = (plan.targetMinor - current).clamp(0, 99999999999);
    final warning =
        plan.kind == FinancePlanKind.budget && progress >= plan.alertThreshold;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: warning ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  plan.kind == FinancePlanKind.goal
                      ? Icons.flag_outlined
                      : Icons.account_balance_wallet_outlined,
                  color:
                      warning
                          ? scheme.error
                          : plan.kind == FinancePlanKind.goal
                          ? AppColors.accessibleGreen
                          : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    plan.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  plan.kind == FinancePlanKind.goal ? 'Meta' : 'Presupuesto',
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              plan.kind == FinancePlanKind.goal
                  ? 'Faltan ${_money(remaining)}${plan.deadline == null ? '' : ' · límite ${DateFormat('dd/MM/yyyy').format(plan.deadline!)}'}'
                  : '${plan.category ?? 'Todas las categorías'} · quedan ${_money(remaining)} este mes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              color: warning ? scheme.error : null,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_money(current)} de ${_money(plan.targetMinor)}',
                  ),
                ),
                Text(
                  '${(progress * 100).clamp(0, 999).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (warning) ...[
              const SizedBox(height: 10),
              Text(
                progress >= 1
                    ? 'Límite agotado. Evita nuevos gastos en esta categoría.'
                    : 'Alerta: alcanzaste ${(plan.alertThreshold * 100).round()}% del presupuesto.',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
}

class _MoreTab extends StatefulWidget {
  const _MoreTab({
    required this.user,
    required this.householdId,
    required this.services,
    required this.themeController,
    required this.household,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final ThemeController themeController;
  final Household household;

  @override
  State<_MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<_MoreTab> {
  bool? _biometricEnabled;
  bool? _notificationsEnabled;

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
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            children: [
              Text(
                'Más opciones',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              const Text('Cuenta, familia, seguridad y apariencia.'),
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
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.blushPinkLight,
                    foregroundColor: AppColors.blushPinkDark,
                    child: Icon(Icons.family_restroom),
                  ),
                  title: Text(snapshot.data?.name ?? 'Hogar cifrado'),
                  subtitle: Text(
                    snapshot.hasError
                        ? _errorText(snapshot.error)
                        : '${snapshot.data?.memberCount ?? '—'} integrantes · ${widget.household.kind.label}',
                  ),
                  trailing: const Icon(Icons.verified_user_outlined),
                  onTap: _showMembers,
                ),
              ),
              if (!widget.household.canContribute) ...[
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
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.import_export_outlined),
                  title: const Text('Importar y exportar datos'),
                  subtitle: const Text(
                    'Estados de cuenta y reportes Excel/PDF',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => DataToolsScreen(
                                user: widget.user,
                                householdId: widget.householdId,
                                services: widget.services,
                                canImport: widget.household.canContribute,
                              ),
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
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
                                    canContribute:
                                        widget.household.canContribute,
                                  ),
                            ),
                          ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.event_repeat_outlined),
                      title: const Text('Movimientos recurrentes'),
                      subtitle: const Text(
                        'Semanal, quincenal, mensual o anual',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => RecurringTransactionsScreen(
                                    householdId: widget.householdId,
                                    uid: widget.user.uid,
                                    repository: widget.services.finance,
                                    canContribute:
                                        widget.household.canContribute,
                                  ),
                            ),
                          ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.handshake_outlined),
                      title: const Text('Gastos compartidos y deudas'),
                      subtitle: const Text(
                        'Divisiones pendientes y pagos realizados',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => SharedDebtsScreen(
                                    householdId: widget.householdId,
                                    repository: widget.services.finance,
                                    households: widget.services.households,
                                    canContribute:
                                        widget.household.canContribute,
                                  ),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.qr_code_2),
                      title: const Text('Invitar con QR'),
                      subtitle: const Text(
                        'Código cifrado, temporal y de un solo uso',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          widget.household.canManage
                              ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder:
                                      (_) => FamilyInviteScreen(
                                        householdId: widget.householdId,
                                        repository: widget.services.households,
                                      ),
                                ),
                              )
                              : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text('Integrantes'),
                      subtitle: const Text(
                        'Consulta quién tiene acceso al hogar',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showMembers,
                    ),
                  ],
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
                      subtitle: const Text(
                        'Alertas de saldo, presupuestos, metas, recurrencias e invitaciones',
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
                      subtitle: const Text(
                        'Solicita huella, rostro, PIN o patrón al reabrir',
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
                      leading: const Icon(Icons.logout),
                      title: const Text('Cerrar sesión'),
                      onTap: widget.services.auth.signOut,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'HomeWallet 1.0.0 · Firebase Blaze',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeNotifications(bool enabled) async {
    final service = widget.services.notifications;
    if (service == null) return;
    try {
      await service.setEnabled(widget.user.uid, enabled);
      if (mounted) {
        setState(() => _notificationsEnabled = enabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Notificaciones inteligentes activadas.'
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
    try {
      await widget.services.biometricLock.setEnabled(widget.user.uid, enabled);
      if (mounted) setState(() => _biometricEnabled = enabled);
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

  void _showMembers() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => HouseholdMembersScreen(
              user: widget.user,
              household: widget.household,
              repository: widget.services.households,
            ),
      ),
    );
  }
}

class _TransactionForm extends StatefulWidget {
  const _TransactionForm({
    required this.plans,
    required this.transactions,
    required this.members,
    required this.customCategories,
    required this.currentUid,
    this.existing,
  });

  final Stream<List<FinancePlan>> plans;
  final Stream<List<FinanceTransaction>> transactions;
  final Stream<List<HouseholdMember>> members;
  final Stream<List<FinanceCategory>> customCategories;
  final String currentUid;
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
  bool _shared = false;
  ExpenseSplitMode _splitMode = ExpenseSplitMode.equal;
  String? _paidByUid;
  final Set<String> _participantIds = {};
  final Map<String, String> _shareInputs = {};
  List<FinancePlan> _goals = const [];
  List<HouseholdMember> _members = const [];
  List<FinanceCategory> _customCategories = const [];
  int _availableSavingsMinor = 0;
  bool _categoryChosen = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _descriptionController.text = existing.description;
      _amountController.text = (existing.amountMinor / 100).toStringAsFixed(2);
      _type = existing.type;
      _category = existing.category;
      _categoryChosen = true;
      _linkedPlanId = existing.linkedPlanId;
      _fundingSource = existing.fundingSource;
      _occurredAt = existing.occurredAt;
      _shared = existing.shared;
      _splitMode = existing.splitMode;
      _paidByUid = existing.paidByUid ?? existing.createdBy;
      _participantIds.addAll(existing.participantSharesMinor.keys);
      for (final entry in existing.participantSharesMinor.entries) {
        _shareInputs[entry.key] =
            existing.splitMode == ExpenseSplitMode.percentage
                ? (entry.value * 100 / existing.amountMinor).toStringAsFixed(2)
                : (entry.value / 100).toStringAsFixed(2);
      }
    } else {
      _paidByUid = widget.currentUid;
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
        _goals =
            (planSnapshot.data ?? const <FinancePlan>[])
                .where(
                  (plan) => plan.kind == FinancePlanKind.goal && plan.isActive,
                )
                .toList();
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
            _availableSavingsMinor =
                FinanceBalances.calculate(transactions, _goals).savings;
            return StreamBuilder<List<FinanceCategory>>(
              stream: widget.customCategories,
              builder: (context, categorySnapshot) {
                _customCategories =
                    categorySnapshot.data ?? const <FinanceCategory>[];
                return StreamBuilder<List<HouseholdMember>>(
                  stream: widget.members,
                  builder: (context, memberSnapshot) {
                    _members = memberSnapshot.data ?? const <HouseholdMember>[];
                    return _buildForm(context);
                  },
                );
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
                  ? 'Nuevo movimiento'
                  : 'Editar movimiento',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Gasto'),
                  icon: Icon(Icons.north_east),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Ingreso'),
                  icon: Icon(Icons.south_west),
                ),
                ButtonSegment(
                  value: TransactionType.saving,
                  label: Text('Ahorro'),
                  icon: Icon(Icons.savings_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() {
                  _type = value.first;
                  _category = TransactionCategories.suggestFor(
                    _type,
                    _descriptionController.text,
                  );
                  _categoryChosen = false;
                  _linkedPlanId = null;
                  _fundingSource = ExpenseFundingSource.general;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('transaction_description'),
              controller: _descriptionController,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('transaction_amount'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items:
                  _categoriesForType(_type)
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged:
                  (value) => setState(() {
                    _category = value ?? _category;
                    _categoryChosen = true;
                  }),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                'Fecha: ${DateFormat('dd/MM/yyyy').format(_occurredAt)}',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.person_outline),
                  label: Text('Personal'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.groups_outlined),
                  label: Text('Compartido'),
                ),
              ],
              selected: {_shared},
              onSelectionChanged: (value) {
                setState(() {
                  _shared = value.first;
                  if (_shared && _participantIds.isEmpty) {
                    _participantIds.addAll(
                      _members.map((member) => member.uid),
                    );
                    _paidByUid ??= widget.currentUid;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (_type == TransactionType.expense)
              _expenseSourceField()
            else
              _goalAllocationField(),
            if (_shared) ...[
              const SizedBox(height: 16),
              _sharedExpenseFields(),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save_transaction'),
              onPressed: _save,
              icon: const Icon(Icons.enhanced_encryption_outlined),
              label: Text(
                widget.existing == null
                    ? 'Cifrar y guardar'
                    : 'Guardar cambios',
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
      decoration: const InputDecoration(
        labelText: '¿De dónde salió el dinero?',
        helperText: 'El gasto se descontará únicamente de este saldo.',
      ),
      items: [
        const DropdownMenuItem(
          value: 'general',
          child: Text('Saldo disponible del hogar'),
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

  Widget _goalAllocationField() => DropdownButtonFormField<String?>(
    value: _linkedPlanId,
    decoration: const InputDecoration(
      labelText: 'Asignar a una meta (opcional)',
      helperText: 'Al guardar, el avance de la meta se actualizará solo.',
    ),
    items: [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('No asignar a una meta'),
      ),
      ..._goals.map(
        (plan) => DropdownMenuItem<String?>(
          value: plan.id,
          child: Text(plan.name, overflow: TextOverflow.ellipsis),
        ),
      ),
    ],
    onChanged: (value) => setState(() => _linkedPlanId = value),
  );

  Widget _sharedExpenseFields() {
    final selectedMembers =
        _members
            .where((member) => _participantIds.contains(member.uid))
            .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'División del movimiento',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _members
                      .map(
                        (member) => FilterChip(
                          label: Text(member.displayName),
                          selected: _participantIds.contains(member.uid),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _participantIds.add(member.uid);
                              } else {
                                _participantIds.remove(member.uid);
                                _shareInputs.remove(member.uid);
                              }
                            });
                          },
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value:
                  _members.any((member) => member.uid == _paidByUid)
                      ? _paidByUid
                      : null,
              decoration: const InputDecoration(labelText: 'Pagado por'),
              items:
                  _members
                      .map(
                        (member) => DropdownMenuItem(
                          value: member.uid,
                          child: Text(member.displayName),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _paidByUid = value),
            ),
            if (_type == TransactionType.expense) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<ExpenseSplitMode>(
                value: _splitMode,
                decoration: const InputDecoration(
                  labelText: 'Forma de dividir',
                ),
                items:
                    ExpenseSplitMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(),
                onChanged:
                    (value) => setState(
                      () => _splitMode = value ?? ExpenseSplitMode.equal,
                    ),
              ),
              if (_splitMode != ExpenseSplitMode.equal) ...[
                const SizedBox(height: 10),
                ...selectedMembers.map(
                  (member) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      key: ValueKey('${_splitMode.name}-${member.uid}'),
                      initialValue: _shareInputs[member.uid],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: member.displayName,
                        suffixText:
                            _splitMode == ExpenseSplitMode.percentage
                                ? '%'
                                : r'$',
                      ),
                      onChanged: (value) => _shareInputs[member.uid] = value,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _save() {
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
    var shares = const <String, int>{};
    if (_shared) {
      if (_participantIds.length < 2) {
        _showError('Elige al menos dos participantes.');
        return;
      }
      if (_paidByUid == null) {
        _showError('Indica quién pagó el movimiento.');
        return;
      }
      shares = _buildShares(amount);
      if (shares.isEmpty) return;
    }
    Navigator.of(context).pop(
      _TransactionInput(
        description: description,
        category: _category,
        amountMinor: amount,
        type: _type,
        linkedPlan: linkedPlan,
        fundingSource: _fundingSource,
        occurredAt: _occurredAt,
        shared: _shared,
        paidByUid: _paidByUid,
        splitMode: _splitMode,
        participantSharesMinor: shares,
      ),
    );
  }

  Map<String, int> _buildShares(int amountMinor) {
    final ids = _participantIds.toList()..sort();
    if (_splitMode == ExpenseSplitMode.equal) {
      final each = amountMinor ~/ ids.length;
      var remaining = amountMinor;
      return {
        for (var index = 0; index < ids.length; index++)
          ids[index]:
              index == ids.length - 1
                  ? remaining
                  : (() {
                    remaining -= each;
                    return each;
                  })(),
      };
    }
    if (_splitMode == ExpenseSplitMode.percentage) {
      final percentages = <String, double>{};
      for (final id in ids) {
        final value = double.tryParse(
          (_shareInputs[id] ?? '').replaceAll(',', '.'),
        );
        if (value == null || value < 0) {
          _showError('Completa porcentajes válidos para todos.');
          return const {};
        }
        percentages[id] = value;
      }
      final total = percentages.values.fold<double>(0, (a, b) => a + b);
      if ((total - 100).abs() > 0.01) {
        _showError('Los porcentajes deben sumar exactamente 100%.');
        return const {};
      }
      var remaining = amountMinor;
      final result = <String, int>{};
      for (var index = 0; index < ids.length; index++) {
        final share =
            index == ids.length - 1
                ? remaining
                : (amountMinor * percentages[ids[index]]! / 100).round();
        result[ids[index]] = share;
        remaining -= share;
      }
      return result;
    }
    final result = <String, int>{};
    for (final id in ids) {
      final share = _parseMoneyMinor(_shareInputs[id] ?? '');
      if (share == null || share < 0) {
        _showError('Completa valores válidos para todos.');
        return const {};
      }
      result[id] = share;
    }
    if (result.values.fold<int>(0, (a, b) => a + b) != amountMinor) {
      _showError(
        'Los valores personalizados deben sumar ${_money(amountMinor)}.',
      );
      return const {};
    }
    return result;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (date != null && mounted) {
      setState(
        () =>
            _occurredAt = DateTime(
              date.year,
              date.month,
              date.day,
              _occurredAt.hour,
              _occurredAt.minute,
            ),
      );
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
    final values =
        {
          ...TransactionCategories.forType(type),
          ..._customCategories
              .where((category) => category.type == type)
              .map((category) => category.name),
          if (_type == type) _category,
        }.toList();
    values.sort();
    return values;
  }
}

class _PlanForm extends StatefulWidget {
  const _PlanForm();

  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  FinancePlanKind _kind = FinancePlanKind.budget;
  String _category = TransactionCategories.expenses.first;
  DateTime? _deadline;
  double _alertThreshold = 0.8;

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
              'Nuevo plan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            SegmentedButton<FinancePlanKind>(
              segments: const [
                ButtonSegment(
                  value: FinancePlanKind.budget,
                  label: Text('Presupuesto'),
                ),
                ButtonSegment(value: FinancePlanKind.goal, label: Text('Meta')),
              ],
              selected: {_kind},
              onSelectionChanged:
                  (value) => setState(() {
                    _kind = value.first;
                    if (_kind == FinancePlanKind.goal) {
                      _deadline ??= DateTime.now().add(
                        const Duration(days: 90),
                      );
                    }
                  }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Objetivo',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            if (_kind == FinancePlanKind.budget) ...[
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoría del presupuesto',
                  helperText: 'Los gastos del mes se sumarán automáticamente.',
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
              label: const Text('Cifrar y guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final target = _parseMoneyMinor(_targetController.text);
    final name = _nameController.text.trim();
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
        kind: _kind,
        targetMinor: target,
        category: _kind == FinancePlanKind.budget ? _category : null,
        deadline: _kind == FinancePlanKind.goal ? _deadline : null,
        alertThreshold: _alertThreshold,
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
      helpText: 'Fecha límite de la meta',
    );
    if (value != null && mounted) setState(() => _deadline = value);
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
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
  const _TransactionTile({required this.transaction});

  final FinanceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == TransactionType.income;
    final saving = transaction.type == TransactionType.saving;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color =
        income
            ? (dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
            : saving
            ? scheme.primary
            : scheme.error;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
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
  _ => 'Revisa tu conexión o los permisos del hogar.',
};
