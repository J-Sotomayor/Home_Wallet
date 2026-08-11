import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../data/finance_repository.dart';
import '../../households/domain/household_models.dart';
import '../domain/finance_balances.dart';
import '../domain/finance_models.dart';
import '../services/transaction_csv_service.dart';
import '../services/transaction_export_service.dart';

enum _ReportPeriod { month, custom, all }

class FinanceReportsTab extends StatefulWidget {
  const FinanceReportsTab({
    super.key,
    required this.householdId,
    required this.repository,
    required this.members,
  });

  final String householdId;
  final FinanceRepository repository;
  final Stream<List<HouseholdMember>> members;

  @override
  State<FinanceReportsTab> createState() => _FinanceReportsTabState();
}

class _FinanceReportsTabState extends State<FinanceReportsTab> {
  static const _csv = TransactionCsvService();
  static const _exports = TransactionExportService();
  _ReportPeriod _period = _ReportPeriod.month;
  DateTimeRange? _dateRange;
  String? _category;
  String? _memberUid;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<FinanceTransaction>>(
        stream: widget.repository.watchTransactions(widget.householdId),
        builder: (context, transactionSnapshot) {
          if (transactionSnapshot.hasError) {
            return _ReportError(error: transactionSnapshot.error);
          }
          return StreamBuilder<List<FinancePlan>>(
            stream: widget.repository.watchPlans(widget.householdId),
            builder: (context, planSnapshot) {
              if (planSnapshot.hasError) {
                return _ReportError(error: planSnapshot.error);
              }
              if (!transactionSnapshot.hasData || !planSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<HouseholdMember>>(
                stream: widget.members,
                builder: (context, memberSnapshot) {
                  if (memberSnapshot.hasError) {
                    return _ReportError(error: memberSnapshot.error);
                  }
                  if (!memberSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final now = DateTime.now();
                  final all =
                      transactionSnapshot.data!
                          .where((transaction) => !transaction.shared)
                          .toList();
                  final categories =
                      all.map((item) => item.category).toSet().toList()..sort();
                  final transactions =
                      all.where((item) {
                        if (_category != null && item.category != _category) {
                          return false;
                        }
                        if (_memberUid != null &&
                            item.createdBy != _memberUid) {
                          return false;
                        }
                        if (_period == _ReportPeriod.month) {
                          return item.occurredAt.year == now.year &&
                              item.occurredAt.month == now.month;
                        }
                        if (_period == _ReportPeriod.custom &&
                            _dateRange != null) {
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
                          return !item.occurredAt.isBefore(start) &&
                              !item.occurredAt.isAfter(end);
                        }
                        return true;
                      }).toList();
                  return _ReportBody(
                    transactions: transactions,
                    plans: planSnapshot.data!,
                    members: memberSnapshot.data!,
                    categories: categories,
                    period: _period,
                    dateRange: _dateRange,
                    category: _category,
                    memberUid: _memberUid,
                    onPeriodChanged: _changePeriod,
                    onCategoryChanged:
                        (value) => setState(() => _category = value),
                    onMemberChanged:
                        (value) => setState(() => _memberUid = value),
                    exporting: _exporting,
                    onExport: () => _chooseExport(transactions),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _changePeriod(_ReportPeriod value) async {
    if (value != _ReportPeriod.custom) {
      setState(() => _period = value);
      return;
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: _dateRange,
      helpText: 'Período del reporte',
    );
    if (range != null && mounted) {
      setState(() {
        _dateRange = range;
        _period = _ReportPeriod.custom;
      });
    }
  }

  Future<void> _chooseExport(
    List<FinanceTransaction> filteredTransactions,
  ) async {
    if (filteredTransactions.isEmpty || _exporting) return;
    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ExportSheet(transactions: filteredTransactions),
    );
    if (choice == null || !mounted) return;

    final selected = transactionsForExport(filteredTransactions, choice.scope);
    if (selected.isEmpty) {
      _showMessage(
        'No hay movimientos de ese origen con los filtros actuales.',
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final Uint8List bytes = switch (choice.format) {
        _ExportFormat.excel => _exports.exportExcel(selected),
        _ExportFormat.pdf => await _exports.exportPdf(selected),
        _ExportFormat.csv => _csv.exportBytes(selected),
      };
      final extension = choice.format.extension;
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final path = await FilePicker.saveFile(
        dialogTitle: 'Guardar reporte de HomeWallet',
        fileName: 'homewallet_${choice.scope.fileLabel}_$date.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (!mounted) return;
      _showMessage(
        path == null
            ? 'Reporte generado. La ubicación depende de tu dispositivo.'
            : 'Reporte ${choice.format.label} guardado correctamente.',
      );
    } on AppException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('No se pudo generar el reporte. Inténtalo nuevamente.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.transactions,
    required this.plans,
    required this.period,
    required this.members,
    required this.categories,
    required this.dateRange,
    required this.category,
    required this.memberUid,
    required this.onPeriodChanged,
    required this.onCategoryChanged,
    required this.onMemberChanged,
    required this.exporting,
    required this.onExport,
  });

  final List<FinanceTransaction> transactions;
  final List<FinancePlan> plans;
  final _ReportPeriod period;
  final List<HouseholdMember> members;
  final List<String> categories;
  final DateTimeRange? dateRange;
  final String? category;
  final String? memberUid;
  final Future<void> Function(_ReportPeriod) onPeriodChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onMemberChanged;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final income = _total(TransactionType.income);
    final expenses = _total(TransactionType.expense);
    final savings = _total(TransactionType.saving);
    final balances = FinanceBalances.calculate(transactions, plans);
    final imported =
        transactions
            .where((item) => item.origin == TransactionOrigin.imported)
            .toList();
    final verified = imported.where((item) => item.sourceVerified).length;
    final sourceCounts = <String, int>{};
    for (final item in imported) {
      sourceCounts.update(
        item.sourceName ?? 'Archivo importado',
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final categoryTotals = <String, int>{};
    for (final item in transactions.where(
      (item) => item.type == TransactionType.expense,
    )) {
      categoryTotals.update(
        item.category,
        (value) => value + item.amountMinor,
        ifAbsent: () => item.amountMinor,
      );
    }
    final rankedCategories =
        categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final tips = _tips(
      income: income,
      expenses: expenses,
      savings: savings,
      otherExpense: categoryTotals['Otro'] ?? 0,
      unverifiedImports: imported.length - verified,
    );
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
      children: [
        Text('Reportes', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Entiende tu dinero, comprueba lo importado y recibe recomendaciones claras.',
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_ReportPeriod>(
            segments: const [
              ButtonSegment(
                value: _ReportPeriod.month,
                label: Text('Este mes'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
              ButtonSegment(
                value: _ReportPeriod.custom,
                label: Text('Fechas'),
                icon: Icon(Icons.date_range_outlined),
              ),
              ButtonSegment(
                value: _ReportPeriod.all,
                label: Text('Histórico'),
                icon: Icon(Icons.history),
              ),
            ],
            selected: {period},
            onSelectionChanged:
                (values) => unawaited(onPeriodChanged(values.first)),
          ),
        ),
        if (period == _ReportPeriod.custom && dateRange != null) ...[
          const SizedBox(height: 8),
          Text(
            '${DateFormat('dd/MM/yyyy').format(dateRange!.start)} – ${DateFormat('dd/MM/yyyy').format(dateRange!.end)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final categoryField = DropdownButtonFormField<String?>(
              value: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas'),
                ),
                ...categories.map(
                  (value) => DropdownMenuItem<String?>(
                    value: value,
                    child: Text(value, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: onCategoryChanged,
            );
            final memberField = DropdownButtonFormField<String?>(
              value: memberUid,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Integrante'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos'),
                ),
                ...members.map(
                  (member) => DropdownMenuItem<String?>(
                    value: member.uid,
                    child: Text(
                      member.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: onMemberChanged,
            );
            if (constraints.maxWidth < 420) {
              return Column(
                children: [
                  categoryField,
                  const SizedBox(height: 12),
                  memberField,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: categoryField),
                const SizedBox(width: 12),
                Expanded(child: memberField),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.download_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Descargar este reporte',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text('${transactions.length} mov.'),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Usará el periodo, la categoría y el integrante seleccionados arriba.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const Key('open_report_export'),
                  onPressed:
                      transactions.isEmpty || exporting ? null : onExport,
                  icon:
                      exporting
                          ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.ios_share_outlined),
                  label: Text(
                    exporting ? 'Creando reporte…' : 'Elegir datos y formato',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (transactions.isEmpty)
          const _EmptyReport()
        else ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withBlue(210)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resultado disponible',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(balances.available),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ReportMetric(
                        label: 'Ingresos',
                        value: income,
                        icon: Icons.south_west,
                      ),
                    ),
                    Expanded(
                      child: _ReportMetric(
                        label: 'Gastos',
                        value: expenses,
                        icon: Icons.north_east,
                      ),
                    ),
                    Expanded(
                      child: _ReportMetric(
                        label: 'Ahorros',
                        value: savings,
                        icon: Icons.savings_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Ahorros disponibles: ${_money(balances.savings)} · Metas: ${_money(balances.goals)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.fact_check_outlined,
            title: 'Calidad de los datos',
            children: [
              _StatusRow(
                icon: Icons.edit_note_outlined,
                label: 'Registrados manualmente',
                value: '${transactions.length - imported.length}',
              ),
              _StatusRow(
                icon: Icons.file_upload_outlined,
                label: 'Importados desde banco',
                value: '${imported.length}',
              ),
              _StatusRow(
                icon:
                    imported.isEmpty || verified == imported.length
                        ? Icons.verified_outlined
                        : Icons.info_outline,
                label: 'Totales bancarios validados',
                value:
                    imported.isEmpty
                        ? 'Sin archivos'
                        : '$verified/${imported.length}',
                positive: imported.isEmpty || verified == imported.length,
              ),
              if (sourceCounts.isNotEmpty) ...[
                const Divider(height: 24),
                ...sourceCounts.entries.map(
                  (entry) => _StatusRow(
                    icon: Icons.account_balance_outlined,
                    label: entry.key,
                    value: '${entry.value} mov.',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.donut_large_outlined,
            title: 'Destino de los gastos',
            children:
                rankedCategories.isEmpty
                    ? const [Text('No hay gastos en este periodo.')]
                    : rankedCategories
                        .take(7)
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Expanded(child: Text(entry.key)),
                                Text(
                                  expenses == 0
                                      ? '0%'
                                      : '${(entry.value / expenses * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(_money(entry.value)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.lightbulb_outline,
            title: 'Consejos para tu hogar',
            children:
                tips
                    .map(
                      (tip) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              tip.icon,
                              size: 20,
                              color:
                                  tip.warning ? scheme.error : scheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(tip.text)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.flag_outlined,
            title: 'Planes y metas',
            children: _goalRows(),
          ),
        ],
      ],
    );
  }

  int _total(TransactionType type) => transactions
      .where((item) => item.type == type)
      .fold(0, (sum, item) => sum + item.amountMinor);

  List<Widget> _goalRows() {
    final active = plans.where((plan) => plan.isActive).toList();
    if (active.isEmpty) {
      return const [Text('Todavía no existen planes activos.')];
    }
    return active.map((plan) {
      final current = automaticPlanProgress(plan, transactions, DateTime.now());
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(plan.name)),
                Text(
                  '${(current / plan.targetMinor * 100).clamp(0, 999).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (current / plan.targetMinor).clamp(0, 1),
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 4),
            Text(
              '${_money(current)} de ${_money(plan.targetMinor)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    }).toList();
  }

  static List<_Tip> _tips({
    required int income,
    required int expenses,
    required int savings,
    required int otherExpense,
    required int unverifiedImports,
  }) {
    final result = <_Tip>[];
    if (income == 0) {
      result.add(
        const _Tip(
          Icons.add_chart,
          'Registra los ingresos del periodo para calcular tasas y saldo real.',
          true,
        ),
      );
    } else {
      final expenseRate = expenses / income;
      final savingRate = (savings / income).clamp(0.0, 1.0);
      result.add(
        _Tip(
          expenseRate > .8 ? Icons.warning_amber : Icons.check_circle_outline,
          expenseRate > .8
              ? 'Los gastos consumen ${(expenseRate * 100).toStringAsFixed(0)}% de tus ingresos. Revisa primero la categoría más alta.'
              : 'Tus gastos representan ${(expenseRate * 100).toStringAsFixed(0)}% de los ingresos del periodo.',
          expenseRate > .8,
        ),
      );
      if (savings > income) {
        result.add(
          const _Tip(
            Icons.info_outline,
            'Los ahorros del período superan los ingresos registrados. Puede incluir dinero acumulado antes; revisa el período para interpretar la tasa.',
            false,
          ),
        );
      }
      result.add(
        _Tip(
          savingRate >= .1 ? Icons.savings_outlined : Icons.trending_up,
          savingRate >= .1
              ? 'Ahorraste ${(savingRate * 100).toStringAsFixed(0)}% de tus ingresos. Mantén ese hábito.'
              : 'Intenta asignar al menos una parte fija de cada ingreso a una meta.',
          false,
        ),
      );
    }
    if (expenses > 0 && otherExpense / expenses > .25) {
      result.add(
        const _Tip(
          Icons.category_outlined,
          'Hay muchos gastos en “Otro”. Clasificarlos mejora el análisis y los consejos.',
          true,
        ),
      );
    }
    if (unverifiedImports > 0) {
      result.add(
        const _Tip(
          Icons.info_outline,
          'Hay archivos sin totales declarados. Los movimientos son válidos, pero conviene compararlos con el saldo del banco.',
          false,
        ),
      );
    }
    if (result.isEmpty) {
      result.add(
        const _Tip(
          Icons.auto_awesome_outlined,
          'Los datos del periodo están equilibrados. Continúa registrando cada movimiento.',
          false,
        ),
      );
    }
    return result;
  }
}

enum _ExportFormat {
  excel,
  pdf,
  csv;

  String get label => switch (this) {
    _ExportFormat.excel => 'Excel',
    _ExportFormat.pdf => 'PDF',
    _ExportFormat.csv => 'CSV',
  };

  String get extension => switch (this) {
    _ExportFormat.excel => 'xlsx',
    _ExportFormat.pdf => 'pdf',
    _ExportFormat.csv => 'csv',
  };
}

extension on TransactionExportScope {
  String get title => switch (this) {
    TransactionExportScope.homeWallet => 'Registrados en HomeWallet',
    TransactionExportScope.imported => 'Solo importados',
    TransactionExportScope.all => 'Todos los movimientos',
  };

  String get description => switch (this) {
    TransactionExportScope.homeWallet =>
      'Incluye los creados manualmente y los programados. Excluye archivos bancarios.',
    TransactionExportScope.imported =>
      'Incluye únicamente los movimientos traídos desde estados de cuenta.',
    TransactionExportScope.all =>
      'Combina los registrados en la app y los importados desde bancos.',
  };

  String get fileLabel => switch (this) {
    TransactionExportScope.homeWallet => 'registrados',
    TransactionExportScope.imported => 'importados',
    TransactionExportScope.all => 'todos',
  };

  IconData get icon => switch (this) {
    TransactionExportScope.homeWallet => Icons.edit_note_outlined,
    TransactionExportScope.imported => Icons.account_balance_outlined,
    TransactionExportScope.all => Icons.all_inclusive,
  };
}

class _ExportChoice {
  const _ExportChoice({required this.scope, required this.format});

  final TransactionExportScope scope;
  final _ExportFormat format;
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.transactions});

  final List<FinanceTransaction> transactions;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  TransactionExportScope _scope = TransactionExportScope.homeWallet;

  int _count(TransactionExportScope scope) =>
      transactionsForExport(widget.transactions, scope).length;

  @override
  Widget build(BuildContext context) {
    final selectedCount = _count(_scope);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Exportar reporte',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            const Text(
              'El periodo y los filtros ya están aplicados. Ahora elige el origen de los datos.',
            ),
            const SizedBox(height: 18),
            Text(
              '1. ¿Qué quieres incluir?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...TransactionExportScope.values.map(
              (scope) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ExportScopeTile(
                  key: ValueKey('export_scope_${scope.name}'),
                  scope: scope,
                  count: _count(scope),
                  selected: _scope == scope,
                  onTap: () => setState(() => _scope = scope),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '2. ¿En qué formato?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              selectedCount == 0
                  ? 'No hay movimientos para esta opción con los filtros actuales.'
                  : selectedCount == 1
                  ? 'Se exportará 1 movimiento.'
                  : 'Se exportarán $selectedCount movimientos.',
              style: TextStyle(
                color:
                    selectedCount == 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('export_excel'),
              onPressed:
                  selectedCount == 0
                      ? null
                      : () => Navigator.pop(
                        context,
                        _ExportChoice(
                          scope: _scope,
                          format: _ExportFormat.excel,
                        ),
                      ),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Guardar como Excel'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('export_pdf'),
                    onPressed:
                        selectedCount == 0
                            ? null
                            : () => Navigator.pop(
                              context,
                              _ExportChoice(
                                scope: _scope,
                                format: _ExportFormat.pdf,
                              ),
                            ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('export_csv'),
                    onPressed:
                        selectedCount == 0
                            ? null
                            : () => Navigator.pop(
                              context,
                              _ExportChoice(
                                scope: _scope,
                                format: _ExportFormat.csv,
                              ),
                            ),
                    icon: const Icon(Icons.data_object_outlined),
                    label: const Text('CSV'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportScopeTile extends StatelessWidget {
  const _ExportScopeTile({
    super.key,
    required this.scope,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final TransactionExportScope scope;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(scope.icon, color: selected ? scheme.primary : null),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scope.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scope.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.positive = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          icon,
          size: 20,
          color:
              positive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Colors.white, size: 19),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      Text(
        _money(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.query_stats,
            size: 54,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Sin datos en este periodo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Agrega movimientos o importa un estado de cuenta para generar el reporte.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'No se pudo generar el reporte. Revisa el acceso cifrado del hogar.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _Tip {
  const _Tip(this.icon, this.text, this.warning);

  final IconData icon;
  final String text;
  final bool warning;
}

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);
