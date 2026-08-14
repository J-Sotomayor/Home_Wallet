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
      appBar: AppBar(title: const Text('Movimientos programados')),
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
          final activeCount = items.where((item) => item.active).length;
          final dueCount =
              items
                  .where(
                    (item) =>
                        item.active && item.confirmBeforePosting && item.isDue,
                  )
                  .length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              Text(
                'Automatiza lo que se repite',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              const Text(
                'Organiza pagos, ingresos o ahorros y decide si quieres validarlos antes de guardarlos.',
              ),
              if (widget.canContribute && items.isNotEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('new_recurring'),
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Crear una programación'),
                ),
              ],
              const SizedBox(height: 18),
              if (items.isEmpty)
                _RecurringEmptyState(
                  canContribute: widget.canContribute,
                  onAdd: _openForm,
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _StatusSummary(
                        icon: Icons.event_available_outlined,
                        value: '$activeCount',
                        label: activeCount == 1 ? 'activa' : 'activas',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatusSummary(
                        icon: Icons.notification_important_outlined,
                        value: '$dueCount',
                        label: dueCount == 1 ? 'por revisar' : 'por revisar',
                        highlighted: dueCount > 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Tus programaciones',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                ...items.map(
                  (item) => _RecurringCard(
                    item: item,
                    canEdit:
                        widget.canContribute && item.createdBy == widget.uid,
                    processing: _processing.contains(item.id),
                    onEdit: () => _openForm(existing: item),
                    onToggle: (active) => _toggleActive(item, active),
                    onDelete: () => _delete(item),
                    onConfirm: () => _confirm(item),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openForm({RecurringTransaction? existing}) async {
    final input = await Navigator.of(context).push<_RecurringInput>(
      MaterialPageRoute(builder: (_) => _RecurringForm(existing: existing)),
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
            ? 'Programación creada correctamente.'
            : 'Programación actualizada.',
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
      _message('Registro validado. La próxima fecha ya fue calculada.');
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
      _message(active ? 'Programación reanudada.' : 'Programación pausada.');
    } on AppException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _delete(RecurringTransaction recurring) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar programación'),
            content: const Text(
              'Dejará de repetirse. Los movimientos que ya se registraron no se borrarán.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Conservar'),
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
      _message('Programación eliminada.');
    } on AppException catch (error) {
      _message(error.message);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

enum _RecurringAction { edit, pause, resume, delete }

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({
    required this.item,
    required this.canEdit,
    required this.processing,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onConfirm,
  });

  final RecurringTransaction item;
  final bool canEdit;
  final bool processing;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final needsReview = item.active && item.confirmBeforePosting && item.isDue;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: needsReview ? scheme.errorContainer.withValues(alpha: 0.45) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(_iconFor(item.template.type))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.template.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_typeLabel(item.template.type)} · ${item.template.category}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(item.template.amountMinor),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (canEdit)
                      PopupMenuButton<_RecurringAction>(
                        tooltip: 'Opciones de la programación',
                        padding: EdgeInsets.zero,
                        onSelected: (action) {
                          switch (action) {
                            case _RecurringAction.edit:
                              onEdit();
                            case _RecurringAction.pause:
                              onToggle(false);
                            case _RecurringAction.resume:
                              onToggle(true);
                            case _RecurringAction.delete:
                              onDelete();
                          }
                        },
                        itemBuilder:
                            (_) => [
                              const PopupMenuItem(
                                value: _RecurringAction.edit,
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Editar'),
                                ),
                              ),
                              PopupMenuItem(
                                value:
                                    item.active
                                        ? _RecurringAction.pause
                                        : _RecurringAction.resume,
                                child: ListTile(
                                  leading: Icon(
                                    item.active
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                  ),
                                  title: Text(
                                    item.active ? 'Pausar' : 'Reanudar',
                                  ),
                                ),
                              ),
                              const PopupMenuItem(
                                value: _RecurringAction.delete,
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Eliminar'),
                                ),
                              ),
                            ],
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: item.active ? Icons.play_arrow : Icons.pause,
                  label: item.active ? 'Activa' : 'Pausada',
                ),
                _InfoPill(
                  icon: Icons.repeat,
                  label: _frequencySentence(item.frequency),
                ),
                _InfoPill(
                  icon: Icons.event_outlined,
                  label:
                      'Próximo: ${DateFormat('dd/MM/yyyy · HH:mm').format(item.nextDueAt)}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  item.confirmBeforePosting
                      ? Icons.notifications_active_outlined
                      : Icons.bolt_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item.confirmBeforePosting
                        ? 'Te avisará a esa hora para que puedas validarlo.'
                        : 'Se validará y guardará al abrir HomeWallet después de la fecha.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (needsReview) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: processing ? null : onConfirm,
                icon:
                    processing
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.check_circle_outline),
                label: const Text('Revisar y validar ahora'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({
    required this.icon,
    required this.value,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlighted ? scheme.errorContainer : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 9),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
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
  void initState() {
    super.initState();
    _description.addListener(_refresh);
    _amount.addListener(_refresh);
  }

  @override
  void dispose() {
    _description.removeListener(_refresh);
    _amount.removeListener(_refresh);
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final amount = _parseMoneyMinor(_amount.text) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Nueva programación'
              : 'Editar programación',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Text(
              '1. ¿Qué se repetirá?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            const Text('Elige el tipo y describe el movimiento.'),
            const SizedBox(height: 14),
            ...TransactionType.values.map(
              (type) => _RecurringTypeOption(
                type: type,
                selected: _type == type,
                onTap: () {
                  setState(() {
                    _type = type;
                    _category = TransactionCategories.defaultFor(type);
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recurring_description'),
              controller: _description,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _descriptionLabel(_type),
                hintText: _descriptionHint(_type),
                prefixIcon: const Icon(Icons.edit_note_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('recurring_amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _amountLabel(_type),
                prefixText: r'$ ',
                helperText: 'Dólares de Estados Unidos (USD)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                prefixIcon: Icon(Icons.category_outlined),
              ),
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
            const SizedBox(height: 26),
            Text(
              '2. ¿Cuándo se repite?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            const Text('Define cada cuánto ocurre y desde qué fecha.'),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.75,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children:
                  RecurrenceFrequency.values
                      .map(
                        (frequency) => _FrequencyOption(
                          key: ValueKey(
                            'recurring_frequency_${frequency.name}',
                          ),
                          frequency: frequency,
                          selected: _frequency == frequency,
                          onTap: () => setState(() => _frequency = frequency),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Primera fecha'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(_nextDueAt)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 10),
            _ScheduleSentence(
              type: _type,
              frequency: _frequency,
              date: _nextDueAt,
            ),
            const SizedBox(height: 26),
            Text(
              '3. Al llegar la fecha',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            const Text('Elige cuánto control quieres conservar.'),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: RadioListTile<bool>(
                value: true,
                groupValue: _confirmBeforePosting,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Avisarme antes de validarlo'),
                subtitle: const Text(
                  'Elige una hora, revisa el monto y decide cuándo validarlo. Recomendado.',
                ),
                onChanged:
                    (value) =>
                        setState(() => _confirmBeforePosting = value ?? true),
              ),
            ),
            if (_confirmBeforePosting)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  key: const Key('recurring_reminder_time'),
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Hora del aviso'),
                  subtitle: Text(
                    '${DateFormat('HH:mm').format(_nextDueAt)} · toca para cambiarla',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _pickTime,
                ),
              ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: RadioListTile<bool>(
                value: false,
                groupValue: _confirmBeforePosting,
                secondary: const Icon(Icons.bolt_outlined),
                title: const Text('Validar automáticamente'),
                subtitle: const Text(
                  'Se validará y guardará cuando abras HomeWallet en o después de la fecha.',
                ),
                onChanged:
                    (value) =>
                        setState(() => _confirmBeforePosting = value ?? false),
              ),
            ),
            const SizedBox(height: 18),
            _RecurringPreview(
              description: _description.text.trim(),
              amountMinor: amount,
              type: _type,
              frequency: _frequency,
              nextDueAt: _nextDueAt,
              confirmBeforePosting: _confirmBeforePosting,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save_recurring'),
              onPressed: _save,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(
                widget.existing == null
                    ? 'Crear programación'
                    : 'Guardar cambios',
              ),
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
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 20),
      helpText: 'Elegir la primera fecha',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (date != null && mounted) {
      final today = DateTime(now.year, now.month, now.day);
      var chosen = DateTime(
        date.year,
        date.month,
        date.day,
        _nextDueAt.hour,
        _nextDueAt.minute,
      );
      if (DateTime(date.year, date.month, date.day) == today &&
          !chosen.isAfter(now)) {
        chosen = now.add(const Duration(minutes: 5));
      }
      setState(() => _nextDueAt = chosen);
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_nextDueAt),
      helpText: 'HORA DEL AVISO',
      cancelText: 'CANCELAR',
      confirmText: 'ELEGIR',
    );
    if (selected == null || !mounted) return;
    final chosen = DateTime(
      _nextDueAt.year,
      _nextDueAt.month,
      _nextDueAt.day,
      selected.hour,
      selected.minute,
    );
    if (!chosen.isAfter(DateTime.now())) {
      _showError('Elige una hora futura para el primer aviso.');
      return;
    }
    setState(() => _nextDueAt = chosen);
  }

  void _save() {
    final amount = _parseMoneyMinor(_amount.text);
    final description = _description.text.trim();
    if (description.isEmpty) {
      _showError('Escribe un nombre para reconocer esta programación.');
      return;
    }
    if (amount == null || amount <= 0) {
      _showError('Ingresa un monto válido.');
      return;
    }
    final now = DateTime.now();
    final safeNextDate =
        _nextDueAt.isBefore(now.subtract(const Duration(minutes: 1)))
            ? now.add(const Duration(minutes: 5))
            : _nextDueAt;
    Navigator.pop(
      context,
      _RecurringInput(
        template: FinanceTransactionDraft(
          description: description,
          category: _category,
          amountMinor: amount,
          occurredAt: safeNextDate,
          type: _type,
          shared: false,
        ),
        frequency: _frequency,
        nextDueAt: safeNextDate,
        confirmBeforePosting: _confirmBeforePosting,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RecurringTypeOption extends StatelessWidget {
  const _RecurringTypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final TransactionType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey('recurring_type_${type.name}'),
        leading: CircleAvatar(child: Icon(_iconFor(type))),
        title: Text(
          _typeLabel(type),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(_typeDescription(type)),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          color: selected ? scheme.primary : null,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _FrequencyOption extends StatelessWidget {
  const _FrequencyOption({
    super.key,
    required this.frequency,
    required this.selected,
    required this.onTap,
  });

  final RecurrenceFrequency frequency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                Icons.repeat,
                size: 17,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  frequency.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleSentence extends StatelessWidget {
  const _ScheduleSentence({
    required this.type,
    required this.frequency,
    required this.date,
  });

  final TransactionType type;
  final RecurrenceFrequency frequency;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_typeLabel(type)} ${_frequencySentence(frequency).toLowerCase()}, desde el ${DateFormat('dd/MM/yyyy').format(date)}.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurringPreview extends StatelessWidget {
  const _RecurringPreview({
    required this.description,
    required this.amountMinor,
    required this.type,
    required this.frequency,
    required this.nextDueAt,
    required this.confirmBeforePosting,
  });

  final String description;
  final int amountMinor;
  final TransactionType type;
  final RecurrenceFrequency frequency;
  final DateTime nextDueAt;
  final bool confirmBeforePosting;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Resumen', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description.isEmpty ? 'Movimiento sin nombre' : description,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              '${_typeLabel(type)} · ${amountMinor > 0 ? _money(amountMinor) : 'Falta el monto'}',
            ),
            Text(
              '${_frequencySentence(frequency)} · inicia ${DateFormat('dd/MM/yyyy').format(nextDueAt)}',
            ),
            Text(
              confirmBeforePosting
                  ? 'HomeWallet te pedirá revisión.'
                  : 'Se validará automáticamente al abrir la app.',
            ),
          ],
        ),
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
  const _RecurringEmptyState({
    required this.canContribute,
    required this.onAdd,
  });

  final bool canContribute;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              Icons.event_repeat_outlined,
              size: 58,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes programaciones',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Úsalas para recordar y validar registros que ocurren con frecuencia.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(Icons.home_outlined, size: 17),
                  label: Text('Arriendo'),
                ),
                Chip(
                  avatar: Icon(Icons.payments_outlined, size: 17),
                  label: Text('Sueldo'),
                ),
                Chip(
                  avatar: Icon(Icons.wifi_outlined, size: 17),
                  label: Text('Internet'),
                ),
                Chip(
                  avatar: Icon(Icons.savings_outlined, size: 17),
                  label: Text('Ahorro mensual'),
                ),
              ],
            ),
            if (canContribute) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('new_recurring'),
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Crear la primera'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(TransactionType type) => switch (type) {
  TransactionType.expense => Icons.shopping_bag_outlined,
  TransactionType.income => Icons.add_card_outlined,
  TransactionType.saving => Icons.savings_outlined,
};

String _typeLabel(TransactionType type) => switch (type) {
  TransactionType.expense => 'Gasto',
  TransactionType.income => 'Ingreso',
  TransactionType.saving => 'Ahorro',
};

String _typeDescription(TransactionType type) => switch (type) {
  TransactionType.expense => 'Un pago que haces periódicamente.',
  TransactionType.income => 'Dinero que recibes con frecuencia.',
  TransactionType.saving => 'Dinero que apartas regularmente.',
};

String _descriptionLabel(TransactionType type) => switch (type) {
  TransactionType.expense => '¿Qué pago se repetirá?',
  TransactionType.income => '¿Qué ingreso se repetirá?',
  TransactionType.saving => '¿Qué ahorro se repetirá?',
};

String _descriptionHint(TransactionType type) => switch (type) {
  TransactionType.expense => 'Ej. Arriendo o plan de internet',
  TransactionType.income => 'Ej. Sueldo o pensión',
  TransactionType.saving => 'Ej. Ahorro para emergencias',
};

String _amountLabel(TransactionType type) => switch (type) {
  TransactionType.expense => '¿Cuánto pagarás cada vez?',
  TransactionType.income => '¿Cuánto recibirás cada vez?',
  TransactionType.saving => '¿Cuánto apartarás cada vez?',
};

String _frequencySentence(RecurrenceFrequency frequency) => switch (frequency) {
  RecurrenceFrequency.weekly => 'Cada semana',
  RecurrenceFrequency.biweekly => 'Cada quince días',
  RecurrenceFrequency.monthly => 'Cada mes',
  RecurrenceFrequency.yearly => 'Cada año',
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
