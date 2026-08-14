import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../households/data/household_repository.dart';
import '../../households/domain/household_models.dart';
import '../data/finance_repository.dart';
import '../domain/expense_split.dart';
import '../domain/finance_models.dart';

class SharedDebtsScreen extends StatefulWidget {
  const SharedDebtsScreen({
    super.key,
    required this.householdId,
    required this.currentUid,
    required this.repository,
    required this.households,
    required this.canContribute,
  });

  final String householdId;
  final String currentUid;
  final FinanceRepository repository;
  final HouseholdRepository households;
  final bool canContribute;

  @override
  State<SharedDebtsScreen> createState() => _SharedDebtsScreenState();
}

class _SharedDebtsScreenState extends State<SharedDebtsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dividir gastos')),
      floatingActionButton:
          widget.canContribute
              ? FloatingActionButton.extended(
                key: const Key('new_shared_expense'),
                onPressed: _createExpense,
                icon: const Icon(Icons.call_split_outlined),
                label: const Text('Dividir gasto'),
              )
              : null,
      body: StreamBuilder<List<HouseholdMember>>(
        stream: widget.households.watchMembers(widget.householdId),
        builder: (context, memberSnapshot) {
          return StreamBuilder<List<SharedExpense>>(
            stream: widget.repository.watchSharedExpenses(widget.householdId),
            builder: (context, expenseSnapshot) {
              if (memberSnapshot.hasError || expenseSnapshot.hasError) {
                return const Center(
                  child: Text('No se pudieron cargar los gastos divididos.'),
                );
              }
              if (!memberSnapshot.hasData || !expenseSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = memberSnapshot.data!;
              final names = {
                for (final member in members) member.uid: member.displayName,
              };
              final expenses = expenseSnapshot.data!;
              final pending = expenses.fold<int>(
                0,
                (sum, expense) => sum + expense.pendingMinor,
              );
              final pendingPeople =
                  <String>{
                    for (final expense in expenses)
                      for (final participant
                          in expense.participantSharesMinor.keys)
                        if (participant != expense.paidByUid &&
                            !expense.settledParticipantIds.contains(
                              participant,
                            ))
                          participant,
                  }.length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                children: [
                  Text(
                    'Cuentas entre personas',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Aquí sólo calculas quién paga qué. No modifica tus ingresos, gastos, ahorros ni reportes.',
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pendiente por devolver',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  pendingPeople == 1
                                      ? '1 persona tiene un pago pendiente'
                                      : '$pendingPeople personas tienen pagos pendientes',
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _money(pending),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (expenses.isEmpty)
                    _EmptySharedState(onAdd: _createExpense)
                  else ...[
                    Text(
                      'Gastos divididos',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    ...expenses.map(
                      (expense) => _SharedExpenseCard(
                        expense: expense,
                        names: names,
                        canContribute: widget.canContribute,
                        onSettle:
                            (participantUid) =>
                                _settle(expense, participantUid),
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createExpense() async {
    final members =
        await widget.households.watchMembers(widget.householdId).first;
    if (!mounted) return;
    if (members.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Necesitas al menos dos integrantes para dividir.'),
        ),
      );
      return;
    }
    final draft = await Navigator.of(context).push<SharedExpenseDraft>(
      MaterialPageRoute(
        builder:
            (_) => _SharedExpenseForm(
              members: members,
              currentUid: widget.currentUid,
            ),
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.addSharedExpense(
        householdId: widget.householdId,
        uid: widget.currentUid,
        expense: draft,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('División guardada correctamente.')),
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

  Future<void> _settle(SharedExpense expense, String participantUid) async {
    try {
      await widget.repository.settleSharedParticipant(
        householdId: widget.householdId,
        expense: expense,
        participantUid: participantUid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago marcado como devuelto.')),
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

class _SharedExpenseCard extends StatelessWidget {
  const _SharedExpenseCard({
    required this.expense,
    required this.names,
    required this.canContribute,
    required this.onSettle,
  });

  final SharedExpense expense;
  final Map<String, String> names;
  final bool canContribute;
  final ValueChanged<String> onSettle;

  @override
  Widget build(BuildContext context) {
    final payer = names[expense.paidByUid] ?? 'Quien pagó';
    final payerShare = expense.participantSharesMinor[expense.paidByUid] ?? 0;
    final advanced = expense.totalMinor - payerShare;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            expense.pendingMinor == 0
                ? Icons.check_outlined
                : Icons.groups_outlined,
          ),
        ),
        title: Text(
          expense.description,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${expense.category} · ${DateFormat('dd/MM/yyyy').format(expense.occurredAt)}\n$payer pagó ${_money(expense.totalMinor)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money(expense.totalMinor),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              expense.pendingMinor == 0
                  ? 'Saldado'
                  : '${_money(expense.pendingMinor)} pendiente',
              style: TextStyle(
                fontSize: 11,
                color:
                    expense.pendingMinor == 0
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$payer adelantó ${_money(advanced)} y su parte es ${_money(payerShare)}.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          ...expense.participantSharesMinor.entries.map((entry) {
            final isPayer = entry.key == expense.paidByUid;
            final settled =
                isPayer || expense.settledParticipantIds.contains(entry.key);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                settled ? Icons.check_circle : Icons.schedule_outlined,
                color:
                    settled
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary,
              ),
              title: Text(names[entry.key] ?? 'Integrante'),
              subtitle: Text(
                isPayer
                    ? 'Pagó la cuenta · esta es su parte'
                    : settled
                    ? 'Ya devolvió su parte a $payer'
                    : 'Debe devolverle a $payer',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _money(entry.value),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (!settled) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Marcar como devuelto',
                      onPressed:
                          canContribute ? () => onSettle(entry.key) : null,
                      icon: const Icon(Icons.done),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (expense.includesVat || expense.includesService)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (expense.includesVat) 'IVA 15%',
                  if (expense.includesService) 'servicio 10%',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptySharedState extends StatelessWidget {
  const _EmptySharedState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.call_split_outlined,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Divide tu primera cuenta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Indica quién pagó y HomeWallet calculará cuánto debe devolver cada persona.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Dividir un gasto'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedExpenseForm extends StatefulWidget {
  const _SharedExpenseForm({required this.members, required this.currentUid});

  final List<HouseholdMember> members;
  final String currentUid;

  @override
  State<_SharedExpenseForm> createState() => _SharedExpenseFormState();
}

class _SharedExpenseFormState extends State<_SharedExpenseForm> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final Map<String, TextEditingController> _shareControllers = {};
  final Set<String> _participants = {};
  String _category = SharedExpenseCategories.values.first;
  DateTime _occurredAt = DateTime.now();
  ExpenseSplitMode _splitMode = ExpenseSplitMode.equal;
  late String _paidByUid;
  bool _calculateEcuadorExtras = false;
  bool _includeVat = true;
  bool _includeService = false;

  @override
  void initState() {
    super.initState();
    _participants.addAll(widget.members.map((member) => member.uid));
    _paidByUid =
        widget.members.any((member) => member.uid == widget.currentUid)
            ? widget.currentUid
            : widget.members.first.uid;
    for (final member in widget.members) {
      _shareControllers[member.uid] = TextEditingController();
    }
    _amountController.addListener(_refresh);
  }

  @override
  void dispose() {
    _amountController.removeListener(_refresh);
    _descriptionController.dispose();
    _amountController.dispose();
    for (final controller in _shareControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = _calculatedTotalMinor;
    final shares = _buildShares(total, showErrors: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Dividir un gasto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Text(
              '¿Qué cuenta van a dividir?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            const Text(
              'Esta cuenta es independiente y no se descontará de ningún saldo.',
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('shared_description'),
              controller: _descriptionController,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Ej. Cena, arriendo o viaje a Baños',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Tipo de gasto',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items:
                  SharedExpenseCategories.values
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged:
                  (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('shared_amount'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    _calculateEcuadorExtras
                        ? 'Subtotal de la cuenta'
                        : 'Total de la cuenta',
                prefixText: r'$ ',
                helperText: 'Dólares de Estados Unidos (USD)',
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Calculadora para Ecuador'),
                subtitle: Text(
                  _calculateEcuadorExtras
                      ? 'Total calculado: ${_money(total)}'
                      : 'Úsala si ingresaste un subtotal',
                ),
                children: [
                  SwitchListTile(
                    title: const Text('Calcular desde el subtotal'),
                    subtitle: const Text(
                      'Suma únicamente los valores que correspondan a tu factura.',
                    ),
                    value: _calculateEcuadorExtras,
                    onChanged:
                        (value) =>
                            setState(() => _calculateEcuadorExtras = value),
                  ),
                  CheckboxListTile(
                    title: const Text('IVA general 15%'),
                    subtitle: const Text(
                      'No todos los bienes y servicios tienen esta tarifa.',
                    ),
                    value: _includeVat,
                    onChanged:
                        _calculateEcuadorExtras
                            ? (value) =>
                                setState(() => _includeVat = value ?? false)
                            : null,
                  ),
                  CheckboxListTile(
                    title: const Text('Servicio 10%'),
                    subtitle: const Text(
                      'Para establecimientos donde conste en la cuenta.',
                    ),
                    value: _includeService,
                    onChanged:
                        _calculateEcuadorExtras
                            ? (value) =>
                                setState(() => _includeService = value ?? false)
                            : null,
                  ),
                  if (_calculateEcuadorExtras)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total para dividir',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _money(total),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                'Fecha: ${DateFormat('dd/MM/yyyy').format(_occurredAt)}',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '1. ¿Quiénes participaron?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  widget.members.map((member) {
                    final selected = _participants.contains(member.uid);
                    return FilterChip(
                      label: Text(member.displayName),
                      selected: selected,
                      avatar: const Icon(Icons.person_outline, size: 18),
                      onSelected:
                          (value) => _toggleParticipant(member.uid, value),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 18),
            Text(
              '2. ¿Quién pagó toda la cuenta?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _participants.contains(_paidByUid) ? _paidByUid : null,
              decoration: const InputDecoration(
                labelText: 'Pagó la cuenta',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items:
                  widget.members
                      .where((member) => _participants.contains(member.uid))
                      .map(
                        (member) => DropdownMenuItem(
                          value: member.uid,
                          child: Text(member.displayName),
                        ),
                      )
                      .toList(),
              onChanged:
                  (value) => setState(() => _paidByUid = value ?? _paidByUid),
            ),
            const SizedBox(height: 20),
            Text(
              '3. ¿Cómo lo dividen?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...ExpenseSplitMode.values.map(
              (mode) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: RadioListTile<ExpenseSplitMode>(
                  value: mode,
                  groupValue: _splitMode,
                  title: Text(mode.label),
                  subtitle: Text(_splitModeDescription(mode)),
                  onChanged:
                      (value) => setState(
                        () => _splitMode = value ?? ExpenseSplitMode.equal,
                      ),
                ),
              ),
            ),
            if (_splitMode != ExpenseSplitMode.equal) ...[
              const SizedBox(height: 8),
              ...widget.members
                  .where((member) => _participants.contains(member.uid))
                  .map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _shareControllers[member.uid],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              _splitMode == ExpenseSplitMode.income
                                  ? 'Ingreso mensual de ${member.displayName}'
                                  : member.displayName,
                          suffixText:
                              _splitMode == ExpenseSplitMode.percentage
                                  ? '%'
                                  : r'USD',
                          helperText:
                              _splitMode == ExpenseSplitMode.income
                                  ? 'Solo se usa para calcular la proporción.'
                                  : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            _SplitPreview(
              totalMinor: total,
              shares: shares,
              members: widget.members,
              paidByUid: _paidByUid,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save_shared_expense'),
              onPressed: _save,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Guardar división'),
            ),
          ],
        ),
      ),
    );
  }

  int get _calculatedTotalMinor {
    final base = _parseMoneyMinor(_amountController.text) ?? 0;
    if (!_calculateEcuadorExtras) return base;
    final vat = _includeVat ? (base * 0.15).round() : 0;
    final service = _includeService ? (base * 0.10).round() : 0;
    return base + vat + service;
  }

  void _toggleParticipant(String uid, bool selected) {
    setState(() {
      if (selected) {
        _participants.add(uid);
      } else {
        _participants.remove(uid);
        if (_paidByUid == uid && _participants.isNotEmpty) {
          _paidByUid = _participants.first;
        }
      }
    });
  }

  Map<String, int> _buildShares(int total, {required bool showErrors}) {
    final ids = _participants.toList()..sort();
    if (total <= 0 || ids.length < 2) return const {};
    if (_splitMode == ExpenseSplitMode.equal) {
      final each = total ~/ ids.length;
      var remaining = total;
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
          _shareControllers[id]!.text.trim().replaceAll(',', '.'),
        );
        if (value == null || value < 0) return const {};
        percentages[id] = value;
      }
      final percentageTotal = percentages.values.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      if ((percentageTotal - 100).abs() > 0.01) {
        if (showErrors) _showError('Los porcentajes deben sumar 100%.');
        return const {};
      }
      var remaining = total;
      final result = <String, int>{};
      for (var index = 0; index < ids.length; index++) {
        final share =
            index == ids.length - 1
                ? remaining
                : (total * percentages[ids[index]]! / 100).round();
        result[ids[index]] = share;
        remaining -= share;
      }
      return result;
    }
    if (_splitMode == ExpenseSplitMode.income) {
      final incomes = <String, int>{};
      for (final id in ids) {
        final value = _parseMoneyMinor(_shareControllers[id]!.text);
        if (value == null || value < 0) return const {};
        incomes[id] = value;
      }
      final incomeTotal = incomes.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      if (incomeTotal <= 0) {
        if (showErrors) {
          _showError('Los ingresos deben sumar un valor mayor que cero.');
        }
        return const {};
      }
      return calculateProportionalShares(totalMinor: total, weights: incomes);
    }
    final result = <String, int>{};
    for (final id in ids) {
      final value = _parseMoneyMinor(_shareControllers[id]!.text);
      if (value == null || value < 0) return const {};
      result[id] = value;
    }
    if (result.values.fold<int>(0, (sum, value) => sum + value) != total) {
      if (showErrors) {
        _showError('Los montos deben sumar exactamente ${_money(total)}.');
      }
      return const {};
    }
    return result;
  }

  void _save() {
    final description = _descriptionController.text.trim();
    final total = _calculatedTotalMinor;
    if (description.isEmpty || total <= 0) {
      _showError('Completa una descripción y un monto válido.');
      return;
    }
    if (_participants.length < 2) {
      _showError('Elige al menos dos participantes.');
      return;
    }
    if (!_participants.contains(_paidByUid)) {
      _showError('Indica quién pagó toda la cuenta.');
      return;
    }
    final shares = _buildShares(total, showErrors: true);
    if (shares.isEmpty) {
      if (_splitMode == ExpenseSplitMode.percentage) {
        _showError('Completa el porcentaje de cada persona.');
      } else if (_splitMode == ExpenseSplitMode.income) {
        _showError('Completa el ingreso mensual de cada persona.');
      } else if (_splitMode == ExpenseSplitMode.custom) {
        _showError('Completa el monto de cada persona.');
      }
      return;
    }
    Navigator.of(context).pop(
      SharedExpenseDraft(
        description: description,
        category: _category,
        totalMinor: total,
        occurredAt: _occurredAt,
        paidByUid: _paidByUid,
        splitMode: _splitMode,
        participantSharesMinor: shares,
        includesVat: _calculateEcuadorExtras && _includeVat,
        includesService: _calculateEcuadorExtras && _includeService,
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(1),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (date != null && mounted) setState(() => _occurredAt = date);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SplitPreview extends StatelessWidget {
  const _SplitPreview({
    required this.totalMinor,
    required this.shares,
    required this.members,
    required this.paidByUid,
  });

  final int totalMinor;
  final Map<String, int> shares;
  final List<HouseholdMember> members;
  final String paidByUid;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final member in members) member.uid: member.displayName,
    };
    if (totalMinor <= 0 || shares.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  totalMinor <= 0
                      ? 'Ingresa el total para ver cuánto paga cada persona.'
                      : 'Completa la división para ver el resultado.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final payerName = names[paidByUid] ?? 'Quien pagó';
    final payerShare = shares[paidByUid] ?? 0;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Resultado de la división',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '$payerName paga ahora ${_money(totalMinor)} y luego recibe ${_money(totalMinor - payerShare)}.',
            ),
            const Divider(height: 22),
            ...shares.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key == paidByUid
                            ? '${names[entry.key] ?? 'Integrante'} (pagó)'
                            : names[entry.key] ?? 'Integrante',
                      ),
                    ),
                    Text(
                      _money(entry.value),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _splitModeDescription(ExpenseSplitMode mode) => switch (mode) {
  ExpenseSplitMode.equal => 'El total se reparte por igual automáticamente.',
  ExpenseSplitMode.percentage => 'Define qué porcentaje paga cada persona.',
  ExpenseSplitMode.income =>
    'Calcula una contribución justa según el ingreso mensual de cada persona.',
  ExpenseSplitMode.custom => 'Escribe el valor exacto de cada persona.',
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
  return int.parse(whole) * 100 + int.parse(decimals.padRight(2, '0'));
}
