import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/transaction_categories.dart';

class RecurringTransactionsScreen extends StatefulWidget {
  const RecurringTransactionsScreen({
    super.key,
    required this.householdId,
    required this.uid,
    required this.repository,
    required this.canContribute,
  });

  final String householdId;
  final String uid;
  final FinanceRepository repository;
  final bool canContribute;

  @override
  State<RecurringTransactionsScreen> createState() =>
      _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState
    extends State<RecurringTransactionsScreen> {
  final Set<String> _processing = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos recurrentes')),
      floatingActionButton:
          widget.canContribute
              ? FloatingActionButton.extended(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Programar'),
              )
              : null,
      body: StreamBuilder<List<RecurringTransaction>>(
        stream: widget.repository.watchRecurring(widget.householdId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_errorText(snapshot.error)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          for (final recurring in items.where(
            (item) => item.active && !item.confirmBeforePosting && item.isDue,
          )) {
            _postAutomatically(recurring);
          }
          if (items.isEmpty) {
            return const _RecurringEmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final canEdit =
                  widget.canContribute && item.createdBy == widget.uid;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: canEdit ? () => _openForm(existing: item) : null,
                        leading: CircleAvatar(
                          child: Icon(_iconFor(item.template.type)),
                        ),
                        title: Text(
                          item.template.description,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${item.frequency.label} · próximo ${DateFormat('dd/MM/yyyy').format(item.nextDueAt)}\n${item.template.category} · ${item.confirmBeforePosting ? 'pide confirmación' : 'automático al abrir la app'}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          _money(item.template.amountMinor),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (canEdit)
                        Row(
                          children: [
                            Expanded(
                              child: SwitchListTile.adaptive(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                title: Text(item.active ? 'Activo' : 'Pausado'),
                                value: item.active,
                                onChanged:
                                    (value) => _toggleActive(item, value),
                              ),
                            ),
                            if (item.active &&
                                item.confirmBeforePosting &&
                                item.isDue)
                              FilledButton.tonalIcon(
                                onPressed:
                                    _processing.contains(item.id)
                                        ? null
                                        : () => _confirm(item),
                                icon: const Icon(Icons.check),
                                label: const Text('Registrar'),
                              ),
                            IconButton(
                              tooltip: 'Eliminar recurrencia',
                              onPressed: () => _delete(item),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openForm({RecurringTransaction? existing}) async {
    final input = await showModalBottomSheet<_RecurringInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecurringForm(existing: existing),
    );
    if (input == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.repository.addRecurring(
          householdId: widget.householdId,
          uid: widget.uid,
          template: input.template,
          frequency: input.frequency,
          nextDueAt: input.nextDueAt,
          confirmBeforePosting: input.confirmBeforePosting,
        );
      } else {
        await widget.repository.updateRecurring(
          householdId: widget.householdId,
          recurring: RecurringTransaction(
            id: existing.id,
            template: input.template,
            frequency: input.frequency,
            nextDueAt: input.nextDueAt,
            createdBy: existing.createdBy,
            active: existing.active,
            confirmBeforePosting: input.confirmBeforePosting,
          ),
        );
      }
      _message(
        existing == null
            ? 'Movimiento recurrente programado.'
            : 'Recurrencia actualizada.',
      );
    } on AppException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _confirm(RecurringTransaction recurring) async {
    if (!_processing.add(recurring.id)) return;
    if (mounted) setState(() {});
    try {
      await widget.repository.confirmRecurring(
        householdId: widget.householdId,
        uid: widget.uid,
        recurring: recurring,
      );
      _message('Movimiento registrado y próxima fecha actualizada.');
    } on AppException catch (error) {
      _message(error.message);
    } finally {
      _processing.remove(recurring.id);
      if (mounted) setState(() {});
    }
  }

  void _postAutomatically(RecurringTransaction recurring) {
    if (_processing.contains(recurring.id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_confirm(recurring));
    });
  }

  Future<void> _toggleActive(
    RecurringTransaction recurring,
    bool active,
  ) async {
    try {
      await widget.repository.updateRecurring(
        householdId: widget.householdId,
        recurring: RecurringTransaction(
          id: recurring.id,
          template: recurring.template,
          frequency: recurring.frequency,
          nextDueAt: recurring.nextDueAt,
          createdBy: recurring.createdBy,
          active: active,
          confirmBeforePosting: recurring.confirmBeforePosting,
        ),
      );
    } on AppException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _delete(RecurringTransaction recurring) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar recurrencia'),
            content: const Text(
              'Los movimientos ya registrados se conservarán.',
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteRecurring(widget.householdId, recurring);
      _message('Recurrencia eliminada.');
    } on AppException catch (error) {
      _message(error.message);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _RecurringForm extends StatefulWidget {
  const _RecurringForm({this.existing});

  final RecurringTransaction? existing;

  @override
  State<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<_RecurringForm> {
  late final TextEditingController _description = TextEditingController(
    text: widget.existing?.template.description,
  );
  late final TextEditingController _amount = TextEditingController(
    text:
        widget.existing == null
            ? null
            : (widget.existing!.template.amountMinor / 100).toStringAsFixed(2),
  );
  late TransactionType _type =
      widget.existing?.template.type ?? TransactionType.expense;
  late String _category =
      widget.existing?.template.category ??
      TransactionCategories.defaultFor(_type);
  late RecurrenceFrequency _frequency =
      widget.existing?.frequency ?? RecurrenceFrequency.monthly;
  late DateTime _nextDueAt =
      widget.existing?.nextDueAt ?? DateTime.now().add(const Duration(days: 1));
  late bool _confirmBeforePosting =
      widget.existing?.confirmBeforePosting ?? true;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
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
            const SizedBox(height: 16),
            Text(
              widget.existing == null
                  ? 'Programar movimiento'
                  : 'Editar recurrencia',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 14),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Gasto'),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Ingreso'),
                ),
                ButtonSegment(
                  value: TransactionType.saving,
                  label: Text('Ahorro'),
                ),
              ],
              selected: {_type},
              onSelectionChanged:
                  (value) => setState(() {
                    _type = value.first;
                    _category = TransactionCategories.defaultFor(_type);
                  }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: r'$ ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items:
                  TransactionCategories.forType(_type)
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged:
                  (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RecurrenceFrequency>(
              value: _frequency,
              decoration: const InputDecoration(labelText: 'Frecuencia'),
              items:
                  RecurrenceFrequency.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
              onChanged:
                  (value) => setState(
                    () => _frequency = value ?? RecurrenceFrequency.monthly,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_repeat_outlined),
              label: Text(
                'Próxima fecha: ${DateFormat('dd/MM/yyyy').format(_nextDueAt)}',
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Confirmar antes de registrar'),
              subtitle: const Text(
                'Si se desactiva, se registrará al abrir HomeWallet después de la fecha.',
              ),
              value: _confirmBeforePosting,
              onChanged:
                  (value) => setState(() => _confirmBeforePosting = value),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.schedule_send_outlined),
              label: const Text('Guardar programación'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _nextDueAt.isBefore(now) ? now : _nextDueAt,
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (date != null && mounted) {
      setState(() => _nextDueAt = DateTime(date.year, date.month, date.day, 9));
    }
  }

  void _save() {
    final amount = _parseMoneyMinor(_amount.text);
    final description = _description.text.trim();
    if (amount == null || amount <= 0 || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa descripción y monto válidos.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _RecurringInput(
        template: FinanceTransactionDraft(
          description: description,
          category: _category,
          amountMinor: amount,
          occurredAt: _nextDueAt,
          type: _type,
          shared: false,
        ),
        frequency: _frequency,
        nextDueAt: _nextDueAt,
        confirmBeforePosting: _confirmBeforePosting,
      ),
    );
  }
}

class _RecurringInput {
  const _RecurringInput({
    required this.template,
    required this.frequency,
    required this.nextDueAt,
    required this.confirmBeforePosting,
  });

  final FinanceTransactionDraft template;
  final RecurrenceFrequency frequency;
  final DateTime nextDueAt;
  final bool confirmBeforePosting;
}

class _RecurringEmptyState extends StatelessWidget {
  const _RecurringEmptyState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_repeat_outlined, size: 64),
          SizedBox(height: 14),
          Text('No hay movimientos recurrentes'),
          SizedBox(height: 6),
          Text(
            'Programa pagos o ingresos semanales, quincenales, mensuales o anuales.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

IconData _iconFor(TransactionType type) => switch (type) {
  TransactionType.expense => Icons.north_east,
  TransactionType.income => Icons.south_west,
  TransactionType.saving => Icons.savings_outlined,
};

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);

int? _parseMoneyMinor(String input) {
  var value = input.trim().replaceAll(RegExp(r'[^0-9,.]'), '');
  if (value.isEmpty) return null;
  final separator = value.lastIndexOf(',') > value.lastIndexOf('.') ? ',' : '.';
  if (value.contains(separator) &&
      value.length - value.lastIndexOf(separator) - 1 <= 2) {
    final parts = value.split(separator);
    final whole = parts
        .sublist(0, parts.length - 1)
        .join()
        .replaceAll(RegExp(r'[^0-9]'), '');
    final decimals = parts.last.padRight(2, '0');
    return int.tryParse(
      '${whole.isEmpty ? '0' : whole}${decimals.substring(0, 2)}',
    );
  }
  return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) == null
      ? null
      : int.parse(value.replaceAll(RegExp(r'[^0-9]'), '')) * 100;
}

String _errorText(Object? error) =>
    error is AppException ? error.message : 'No se pudieron cargar los datos.';
