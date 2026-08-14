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
    required this.canManage,
  });

  final String householdId;
  final String currentUid;
  final FinanceRepository repository;
  final HouseholdRepository households;
  final bool canContribute;
  final bool canManage;

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
              return StreamBuilder<List<SharedExpensePayment>>(
                stream: widget.repository.watchSharedExpensePayments(
                  widget.householdId,
                ),
                builder: (context, paymentSnapshot) {
                  if (memberSnapshot.hasError ||
                      expenseSnapshot.hasError ||
                      paymentSnapshot.hasError) {
                    return const Center(
                      child: Text(
                        'No se pudieron cargar los gastos divididos.',
                      ),
                    );
                  }
                  if (!memberSnapshot.hasData ||
                      !expenseSnapshot.hasData ||
                      !paymentSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _buildContent(
                    memberSnapshot.data!,
                    expenseSnapshot.data!,
                    paymentSnapshot.data!,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    List<HouseholdMember> members,
    List<SharedExpense> expenses,
    List<SharedExpensePayment> payments,
  ) {
    final names = {
      for (final member in members) member.uid: member.displayName,
    };
    final owedToMe = expenses
        .where((expense) => expense.paidByUid == widget.currentUid)
        .fold<int>(
          0,
          (sum, expense) => sum + expense.pendingMinorWith(payments),
        );
    final iOwe = expenses
        .where(
          (expense) =>
              expense.paidByUid != widget.currentUid &&
              expense.participantSharesMinor.containsKey(widget.currentUid),
        )
        .fold<int>(
          0,
          (sum, expense) =>
              sum + expense.remainingMinorFor(widget.currentUid, payments),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      children: [
        Text(
          'Cuentas entre personas',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 5),
        const Text(
          'Divide una cuenta sin duplicar movimientos ni cambiar tus saldos o reportes.',
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 14),
                Expanded(child: _DebtTotal(label: 'Te deben', value: owedToMe)),
                const SizedBox(width: 12),
                Expanded(child: _DebtTotal(label: 'Debes', value: iOwe)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Icon(Icons.verified_outlined, size: 17),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Una devolución reduce la deuda cuando quien pagó la confirma.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (expenses.isEmpty)
          _EmptySharedState(onAdd: _createExpense)
        else ...[
          Text(
            'Gastos divididos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          ...expenses.map((expense) {
            final expensePayments =
                payments
                    .where((payment) => payment.expenseId == expense.id)
                    .toList();
            return _SharedExpenseCard(
              expense: expense,
              payments: expensePayments,
              names: names,
              currentUid: widget.currentUid,
              onTap:
                  () => _openExpenseDetail(expense, expensePayments, members),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _createExpense() async {
    final values = await Future.wait([
      widget.households.watchMembers(widget.householdId).first,
      widget.repository.watchTransactions(widget.householdId).first,
      widget.repository.watchSharedExpenses(widget.householdId).first,
    ]);
    final members = values[0] as List<HouseholdMember>;
    if (!mounted) return;
    if (members.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Necesitas al menos dos integrantes para dividir.'),
        ),
      );
      return;
    }
    final transactions = values[1] as List<FinanceTransaction>;
    final existing = values[2] as List<SharedExpense>;
    final linkedIds =
        existing
            .map((expense) => expense.sourceTransactionId)
            .whereType<String>()
            .toSet();
    final eligible =
        transactions
            .where(
              (transaction) =>
                  transaction.type == TransactionType.expense &&
                  transaction.countsInHouseholdFinances &&
                  !linkedIds.contains(transaction.id),
            )
            .toList();
    final choice = await showModalBottomSheet<_CreationChoice>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿De dónde sale la cuenta?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Elige la opción que evita volver a escribir datos.',
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text(
                        'Usar un gasto registrado',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        eligible.isEmpty
                            ? 'No hay gastos disponibles sin dividir.'
                            : 'Recomendado · completa monto, fecha y categoría.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: eligible.isNotEmpty,
                      onTap:
                          eligible.isEmpty
                              ? null
                              : () => Navigator.pop(
                                context,
                                const _CreationChoice.pickTransaction(),
                              ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.add_card_outlined),
                      title: const Text('Crear cuenta independiente'),
                      subtitle: const Text(
                        'Sólo calcula la deuda; no crea un movimiento.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.pop(
                            context,
                            const _CreationChoice.independent(),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (choice == null || !mounted) return;
    FinanceTransaction? source;
    if (choice.pickRegistered) {
      source = await Navigator.of(context).push<FinanceTransaction>(
        MaterialPageRoute(
          builder: (_) => _TransactionPickerScreen(transactions: eligible),
        ),
      );
      if (source == null || !mounted) return;
    }
    final draft = await Navigator.of(context).push<SharedExpenseDraft>(
      MaterialPageRoute(
        builder:
            (_) => _SharedExpenseForm(
              members: members,
              currentUid: widget.currentUid,
              sourceTransaction: source,
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

  Future<void> _openExpenseDetail(
    SharedExpense expense,
    List<SharedExpensePayment> payments,
    List<HouseholdMember> members,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => _SharedExpenseDetailScreen(
              householdId: widget.householdId,
              currentUid: widget.currentUid,
              expense: expense,
              initialPayments: payments,
              members: members,
              repository: widget.repository,
              canContribute: widget.canContribute,
              canManage: widget.canManage,
            ),
      ),
    );
  }
}

class _SharedExpenseCard extends StatelessWidget {
  const _SharedExpenseCard({
    required this.expense,
    required this.payments,
    required this.names,
    required this.currentUid,
    required this.onTap,
  });

  final SharedExpense expense;
  final List<SharedExpensePayment> payments;
  final Map<String, String> names;
  final String currentUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payer = names[expense.paidByUid] ?? 'Quien pagó';
    final pending = expense.pendingMinorWith(payments);
    final reported = payments.any(
      (payment) => payment.status == SharedExpensePaymentStatus.reported,
    );
    final currentRemaining = expense.remainingMinorFor(currentUid, payments);
    final status =
        pending == 0
            ? 'Saldado'
            : reported
            ? 'Pago por confirmar'
            : currentUid == expense.paidByUid
            ? 'Te deben ${_money(pending)}'
            : currentRemaining > 0
            ? 'Debes ${_money(currentRemaining)} a $payer'
            : '${_money(pending)} pendiente';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          child: Icon(
            pending == 0
                ? Icons.check_outlined
                : reported
                ? Icons.hourglass_top_outlined
                : Icons.groups_outlined,
          ),
        ),
        title: Text(
          expense.description,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${expense.category} · ${DateFormat('dd/MM/yyyy').format(expense.occurredAt)}\n$status',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _money(expense.totalMinor),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _DebtTotal extends StatelessWidget {
  const _DebtTotal({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(
        _money(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
    ],
  );
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

class _CreationChoice {
  const _CreationChoice.pickTransaction() : pickRegistered = true;
  const _CreationChoice.independent() : pickRegistered = false;

  final bool pickRegistered;
}

class _TransactionPickerScreen extends StatefulWidget {
  const _TransactionPickerScreen({required this.transactions});

  final List<FinanceTransaction> transactions;

  @override
  State<_TransactionPickerScreen> createState() =>
      _TransactionPickerScreenState();
}

class _TransactionPickerScreenState extends State<_TransactionPickerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final visible =
        widget.transactions
            .where(
              (item) =>
                  normalized.isEmpty ||
                  item.description.toLowerCase().contains(normalized) ||
                  item.category.toLowerCase().contains(normalized),
            )
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Elegir gasto registrado')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por descripción o categoría',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Text(
              'Sólo aparecen gastos que todavía no tienen una división.',
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.receipt_long_outlined),
                    ),
                    title: Text(item.description),
                    subtitle: Text(
                      '${item.category} · ${DateFormat('dd/MM/yyyy').format(item.occurredAt)}',
                    ),
                    trailing: Text(
                      _money(item.amountMinor),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    onTap: () => Navigator.pop(context, item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedExpenseDetailScreen extends StatefulWidget {
  const _SharedExpenseDetailScreen({
    required this.householdId,
    required this.currentUid,
    required this.expense,
    required this.initialPayments,
    required this.members,
    required this.repository,
    required this.canContribute,
    required this.canManage,
  });

  final String householdId;
  final String currentUid;
  final SharedExpense expense;
  final List<SharedExpensePayment> initialPayments;
  final List<HouseholdMember> members;
  final FinanceRepository repository;
  final bool canContribute;
  final bool canManage;

  @override
  State<_SharedExpenseDetailScreen> createState() =>
      _SharedExpenseDetailScreenState();
}

class _SharedExpenseDetailScreenState
    extends State<_SharedExpenseDetailScreen> {
  bool _busy = false;

  Map<String, String> get _names => {
    for (final member in widget.members) member.uid: member.displayName,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SharedExpensePayment>>(
      stream: widget.repository.watchSharedExpensePayments(widget.householdId),
      initialData: widget.initialPayments,
      builder: (context, snapshot) {
        final payments =
            (snapshot.data ?? const <SharedExpensePayment>[])
                .where((payment) => payment.expenseId == widget.expense.id)
                .toList();
        final payer = _names[widget.expense.paidByUid] ?? 'Quien pagó';
        final pending = widget.expense.pendingMinorWith(payments);
        final canDelete =
            widget.canContribute &&
            (widget.canManage || widget.expense.createdBy == widget.currentUid);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Detalle de la división'),
            actions: [
              if (canDelete)
                IconButton(
                  tooltip: 'Eliminar división',
                  onPressed: _busy ? null : () => _deleteExpense(payments),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                widget.expense.description,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.expense.category} · ${DateFormat('dd/MM/yyyy').format(widget.expense.occurredAt)}',
              ),
              if (widget.expense.sourceTransactionId != null) ...[
                const SizedBox(height: 8),
                const Chip(
                  avatar: Icon(Icons.link, size: 18),
                  label: Text('Vinculado a un gasto registrado'),
                ),
              ],
              const SizedBox(height: 14),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$payer pagó la cuenta'),
                      const SizedBox(height: 3),
                      Text(
                        _money(widget.expense.totalMinor),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Divider(),
                      Text(
                        pending == 0
                            ? 'Todo está saldado'
                            : 'Falta devolver ${_money(pending)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Quién debe a quién',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ...widget.expense.participantSharesMinor.entries.map((entry) {
                final isPayer = entry.key == widget.expense.paidByUid;
                final confirmed = widget.expense.confirmedPaidMinorFor(
                  entry.key,
                  payments,
                );
                final reported = widget.expense.reportedPaidMinorFor(
                  entry.key,
                  payments,
                );
                final remaining = widget.expense.remainingMinorFor(
                  entry.key,
                  payments,
                );
                return Card(
                  child: ListTile(
                    leading: Icon(
                      isPayer || remaining == 0
                          ? Icons.check_circle
                          : reported > 0
                          ? Icons.hourglass_top
                          : Icons.schedule,
                      color:
                          isPayer || remaining == 0
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      entry.key == widget.currentUid
                          ? 'Tú · ${_names[entry.key] ?? 'Integrante'}'
                          : _names[entry.key] ?? 'Integrante',
                    ),
                    subtitle: Text(
                      isPayer
                          ? 'Pagó la cuenta · su parte es ${_money(entry.value)}'
                          : remaining == 0
                          ? 'Devolución completada a $payer'
                          : reported > 0
                          ? '${_money(reported)} esperando confirmación'
                          : confirmed > 0
                          ? 'Pagó ${_money(confirmed)} · falta ${_money(remaining)}'
                          : 'Debe devolver ${_money(remaining)} a $payer',
                    ),
                  ),
                );
              }),
              if (_canReportPayment(payments)) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _reportPayment(payments),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Informar una devolución'),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Quien pagó recibirá una notificación y deberá confirmarla.',
                  textAlign: TextAlign.center,
                ),
              ],
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'Historial de devoluciones',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                ...payments.map((payment) => _paymentTile(payment)),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _canReportPayment(List<SharedExpensePayment> payments) {
    if (!widget.canContribute ||
        widget.currentUid == widget.expense.paidByUid ||
        !widget.expense.participantSharesMinor.containsKey(widget.currentUid)) {
      return false;
    }
    final available =
        widget.expense.remainingMinorFor(widget.currentUid, payments) -
        widget.expense.reportedPaidMinorFor(widget.currentUid, payments);
    return available > 0;
  }

  Widget _paymentTile(SharedExpensePayment payment) {
    final canResolve =
        payment.status == SharedExpensePaymentStatus.reported &&
        (widget.currentUid == payment.payerUid || widget.canManage);
    final canCancel =
        payment.status == SharedExpensePaymentStatus.reported &&
        widget.currentUid == payment.participantUid;
    return Card(
      child: ListTile(
        leading: Icon(_paymentIcon(payment.status)),
        title: Text(
          '${_names[payment.participantUid] ?? 'Integrante'} · ${_money(payment.amountMinor)}',
        ),
        subtitle: Text(
          '${_paymentStatusLabel(payment.status)} · ${DateFormat('dd/MM/yyyy HH:mm').format(payment.createdAt)}'
          '${payment.note?.isNotEmpty ?? false ? '\n${payment.note}' : ''}',
        ),
        isThreeLine: payment.note?.isNotEmpty ?? false,
        trailing:
            canResolve
                ? PopupMenuButton<SharedExpensePaymentStatus>(
                  tooltip: 'Confirmar o rechazar',
                  onSelected: (status) => _resolve(payment, status),
                  itemBuilder:
                      (_) => const [
                        PopupMenuItem(
                          value: SharedExpensePaymentStatus.confirmed,
                          child: Text('Confirmar pago'),
                        ),
                        PopupMenuItem(
                          value: SharedExpensePaymentStatus.rejected,
                          child: Text('Rechazar'),
                        ),
                      ],
                )
                : canCancel
                ? IconButton(
                  tooltip: 'Cancelar informe',
                  onPressed:
                      () => _resolve(
                        payment,
                        SharedExpensePaymentStatus.cancelled,
                      ),
                  icon: const Icon(Icons.close),
                )
                : null,
      ),
    );
  }

  Future<void> _reportPayment(List<SharedExpensePayment> payments) async {
    final available =
        widget.expense.remainingMinorFor(widget.currentUid, payments) -
        widget.expense.reportedPaidMinorFor(widget.currentUid, payments);
    final amountController = TextEditingController(
      text: (available / 100).toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Informar devolución'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Puedes informar hasta ${_money(available)}.'),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monto devuelto',
                    prefixText: r'$ ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nota opcional',
                    hintText: 'Ej. Transferencia bancaria',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Informar pago'),
              ),
            ],
          ),
    );
    if (accepted != true) {
      amountController.dispose();
      noteController.dispose();
      return;
    }
    final amount = _parseMoneyMinor(amountController.text);
    final note = noteController.text;
    amountController.dispose();
    noteController.dispose();
    if (amount == null || amount <= 0 || amount > available) {
      _message('Ingresa un monto entre 0,01 y ${_money(available)}.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.addSharedExpensePayment(
        householdId: widget.householdId,
        uid: widget.currentUid,
        expense: widget.expense,
        amountMinor: amount,
        note: note,
      );
      _message('Devolución informada. Falta que $payerName la confirme.');
    } on AppException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get payerName => _names[widget.expense.paidByUid] ?? 'quien pagó';

  Future<void> _resolve(
    SharedExpensePayment payment,
    SharedExpensePaymentStatus status,
  ) async {
    setState(() => _busy = true);
    try {
      await widget.repository.resolveSharedExpensePayment(
        householdId: widget.householdId,
        uid: widget.currentUid,
        payment: payment,
        status: status,
      );
      _message(
        status == SharedExpensePaymentStatus.confirmed
            ? 'Pago confirmado. La deuda fue actualizada.'
            : status == SharedExpensePaymentStatus.rejected
            ? 'Pago rechazado.'
            : 'Informe de pago cancelado.',
      );
    } on AppException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteExpense(List<SharedExpensePayment> payments) async {
    if (payments.isNotEmpty) {
      _message('No se puede eliminar porque ya existe historial de pagos.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar división'),
            content: const Text(
              'Se eliminará sólo la división. El gasto registrado, si existe, se conservará.',
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
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.deleteSharedExpense(
        widget.householdId,
        widget.expense,
      );
      if (mounted) Navigator.pop(context);
    } on AppException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

IconData _paymentIcon(SharedExpensePaymentStatus status) => switch (status) {
  SharedExpensePaymentStatus.confirmed => Icons.check_circle,
  SharedExpensePaymentStatus.rejected => Icons.error_outline,
  SharedExpensePaymentStatus.cancelled => Icons.cancel_outlined,
  SharedExpensePaymentStatus.reported => Icons.hourglass_top,
};

String _paymentStatusLabel(SharedExpensePaymentStatus status) =>
    switch (status) {
      SharedExpensePaymentStatus.confirmed => 'Confirmado',
      SharedExpensePaymentStatus.rejected => 'Rechazado',
      SharedExpensePaymentStatus.cancelled => 'Cancelado',
      SharedExpensePaymentStatus.reported => 'Esperando confirmación',
    };

class _SharedExpenseForm extends StatefulWidget {
  const _SharedExpenseForm({
    required this.members,
    required this.currentUid,
    this.sourceTransaction,
  });

  final List<HouseholdMember> members;
  final String currentUid;
  final FinanceTransaction? sourceTransaction;

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
    final source = widget.sourceTransaction;
    if (source != null) {
      _descriptionController.text = source.description;
      _amountController.text = (source.amountMinor / 100).toStringAsFixed(2);
      _category =
          SharedExpenseCategories.values.contains(source.category)
              ? source.category
              : 'Otro';
      _occurredAt = source.occurredAt;
    }
    final preferredPayer = source?.createdBy ?? widget.currentUid;
    _paidByUid =
        widget.members.any((member) => member.uid == preferredPayer)
            ? preferredPayer
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
              widget.sourceTransaction == null
                  ? '¿Qué cuenta van a dividir?'
                  : 'Divide este gasto registrado',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            Text(
              widget.sourceTransaction == null
                  ? 'Esta cuenta es independiente y no se descontará de ningún saldo.'
                  : 'La división se vincula al movimiento sin duplicarlo ni cambiar su valor.',
            ),
            if (widget.sourceTransaction != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.link),
                  title: Text('Datos completados automáticamente'),
                  subtitle: Text(
                    'Descripción, monto, fecha y categoría vienen del gasto original.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              key: const Key('shared_description'),
              controller: _descriptionController,
              readOnly: widget.sourceTransaction != null,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Descripción',
                hintText: 'Ej. Cena, arriendo o viaje a Baños',
                prefixIcon: const Icon(Icons.receipt_long_outlined),
                counterText: widget.sourceTransaction == null ? null : '',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
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
                  widget.sourceTransaction == null
                      ? (value) =>
                          setState(() => _category = value ?? _category)
                      : null,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('shared_amount'),
              controller: _amountController,
              readOnly: widget.sourceTransaction != null,
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
            if (widget.sourceTransaction == null)
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
                              ? (value) => setState(
                                () => _includeService = value ?? false,
                              )
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
              onPressed: widget.sourceTransaction == null ? _pickDate : null,
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
              isExpanded: true,
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
                          child: Text(
                            member.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
            if (_splitMode == ExpenseSplitMode.income) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome_outlined),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ingresos tomados automáticamente de Inicio',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...widget.members
                          .where((member) => _participants.contains(member.uid))
                          .map(
                            (member) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      member.uid == widget.currentUid
                                          ? 'Tú · ${member.displayName}'
                                          : member.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    member.hasMonthlyIncome
                                        ? _money(member.monthlyIncomeMinor)
                                        : 'Sin registrar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color:
                                          member.hasMonthlyIncome
                                              ? null
                                              : Theme.of(
                                                context,
                                              ).colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cada integrante registra su ingreso neto mensual desde la tarjeta azul de Inicio.',
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_splitMode != ExpenseSplitMode.equal) ...[
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
                          labelText: member.displayName,
                          suffixText:
                              _splitMode == ExpenseSplitMode.percentage
                                  ? '%'
                                  : r'USD',
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
        final member = widget.members.firstWhere((item) => item.uid == id);
        if (!member.hasMonthlyIncome) {
          if (showErrors) {
            _showError(
              '${member.displayName} debe registrar su ingreso mensual desde Inicio.',
            );
          }
          return const {};
        }
        incomes[id] = member.monthlyIncomeMinor;
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
        sourceTransactionId: widget.sourceTransaction?.id,
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
