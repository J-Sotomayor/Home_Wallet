import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/widgets/app_page_header.dart';
import '../../../core/errors/app_exception.dart';
import '../data/finance_repository.dart';
import '../../households/domain/household_models.dart';
import '../domain/finance_models.dart';
import '../domain/monthly_comparison.dart';
import '../services/transaction_csv_service.dart';
import '../services/transaction_export_service.dart';

enum _ReportView { month, bank }

enum _BankSelection {
  pichincha('Pichincha'),
  guayaquil('Guayaquil');

  const _BankSelection(this.label);

  final String label;

  bool matches(FinanceTransaction transaction) => (transaction.sourceName ?? '')
      .toLowerCase()
      .contains(label.toLowerCase());
}

class FinanceReportsTab extends StatefulWidget {
  const FinanceReportsTab({
    super.key,
    required this.householdId,
    required this.repository,
    required this.members,
    this.currentUid = '',
    this.currentUserName = '',
    this.householdKind = HouseholdKind.individual,
  });

  final String householdId;
  final FinanceRepository repository;
  final Stream<List<HouseholdMember>> members;
  final String currentUid;
  final String currentUserName;
  final HouseholdKind householdKind;

  @override
  State<FinanceReportsTab> createState() => _FinanceReportsTabState();
}

class _FinanceReportsTabState extends State<FinanceReportsTab> {
  static const _csv = TransactionCsvService();
  static const _exports = TransactionExportService();
  _ReportView _view = _ReportView.month;
  _BankSelection _bank = _BankSelection.pichincha;
  String? _category;
  DateTime? _selectedMonth;
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
          if (!transactionSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all =
              transactionSnapshot.data!
                  .where((transaction) => transaction.countsInHouseholdFinances)
                  .toList();
          final appMonths =
              all
                  .where((item) => item.origin == TransactionOrigin.manual)
                  .map(
                    (item) =>
                        DateTime(item.occurredAt.year, item.occurredAt.month),
                  )
                  .toSet()
                  .toList()
                ..sort((left, right) => right.compareTo(left));
          final now = DateTime.now();
          final requestedMonth =
              _selectedMonth ?? DateTime(now.year, now.month);
          final reportMonth = appMonths.firstWhere(
            (month) => _sameMonth(month, requestedMonth),
            orElse: () => appMonths.isEmpty ? requestedMonth : appMonths.first,
          );
          final scoped =
              all.where((item) {
                if (_view == _ReportView.month) {
                  return item.origin == TransactionOrigin.manual &&
                      _sameMonth(item.occurredAt, reportMonth);
                }
                return item.origin == TransactionOrigin.imported &&
                    _bank.matches(item);
              }).toList();
          final categories =
              scoped.map((item) => item.category).toSet().toList()..sort();
          final selectedCategory =
              categories.contains(_category) ? _category : null;
          final transactions =
              scoped
                  .where(
                    (item) =>
                        selectedCategory == null ||
                        item.category == selectedCategory,
                  )
                  .toList();
          return StreamBuilder<List<HouseholdMember>>(
            stream: widget.members,
            builder: (context, memberSnapshot) {
              final members = memberSnapshot.data ?? const <HouseholdMember>[];
              return _ReportBody(
                transactions: transactions,
                comparison: compareFinancialMonths(
                  all,
                  reportMonth,
                  category: selectedCategory,
                ),
                categories: categories,
                availableMonths: appMonths,
                selectedMonth: reportMonth,
                view: _view,
                bank: _bank,
                category: selectedCategory,
                onViewChanged: _changeView,
                onMonthChanged:
                    (value) => setState(() {
                      _selectedMonth = value;
                      _category = null;
                    }),
                onBankChanged:
                    (value) => setState(() {
                      _bank = value;
                      _category = null;
                    }),
                onCategoryChanged: (value) => setState(() => _category = value),
                exporting: _exporting,
                onExport: () => _chooseExport(transactions, members),
              );
            },
          );
        },
      ),
    );
  }

  void _changeView(_ReportView value) {
    setState(() {
      _view = value;
      _category = null;
    });
  }

  Future<void> _chooseExport(
    List<FinanceTransaction> filteredTransactions,
    List<HouseholdMember> members,
  ) async {
    if (filteredTransactions.isEmpty || _exporting) return;
    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => _ExportSheet(
            transactions: filteredTransactions,
            members: members,
            currentUid: widget.currentUid,
            currentUserName: widget.currentUserName,
            householdKind: widget.householdKind,
          ),
    );
    if (choice == null || !mounted) return;

    final selected =
        transactionsForExport(filteredTransactions, choice.scope)
            .where(
              (item) =>
                  choice.memberUids.isEmpty ||
                  choice.memberUids.contains(item.createdBy),
            )
            .toList();
    if (selected.isEmpty) {
      _showMessage(
        'No hay movimientos de ese origen con los filtros actuales.',
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final Uint8List bytes = switch (choice.format) {
        _ExportFormat.excel => _exports.exportExcel(
          selected,
          memberNames: choice.memberNames,
        ),
        _ExportFormat.pdf => await _exports.exportPdf(
          selected,
          memberNames: choice.memberNames,
        ),
        _ExportFormat.csv => _csv.exportBytes(
          selected,
          memberNames: choice.memberNames,
        ),
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
    required this.comparison,
    required this.categories,
    required this.availableMonths,
    required this.selectedMonth,
    required this.view,
    required this.bank,
    required this.category,
    required this.onViewChanged,
    required this.onMonthChanged,
    required this.onBankChanged,
    required this.onCategoryChanged,
    required this.exporting,
    required this.onExport,
  });

  final List<FinanceTransaction> transactions;
  final MonthlyComparison comparison;
  final List<String> categories;
  final List<DateTime> availableMonths;
  final DateTime selectedMonth;
  final _ReportView view;
  final _BankSelection bank;
  final String? category;
  final ValueChanged<_ReportView> onViewChanged;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<_BankSelection> onBankChanged;
  final ValueChanged<String?> onCategoryChanged;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final income = _total(TransactionType.income);
    final expenses = _total(TransactionType.expense);
    final balance = income - expenses;
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
    final priority = const ['Agua', 'Luz', 'Internet'];
    final destinationCategories = <MapEntry<String, int>>[
      ...priority
          .where(categoryTotals.containsKey)
          .map((name) => MapEntry(name, categoryTotals[name]!)),
      ...rankedCategories.where((entry) => !priority.contains(entry.key)),
    ];
    final dates = transactions.map((item) => item.occurredAt).toList()..sort();
    final otherExpense =
        (categoryTotals['Otro'] ?? 0) + (categoryTotals['Otros'] ?? 0);
    final tips = _buildTips(
      income: income,
      expenses: expenses,
      otherExpense: otherExpense,
      topCategory: rankedCategories.isEmpty ? null : rankedCategories.first.key,
    );
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
      children: [
        const AppPageHeader(
          icon: Icons.query_stats_outlined,
          title: 'Reportes',
          subtitle:
              'Entiende tu dinero, comprueba lo importado y recibe recomendaciones claras.',
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_ReportView>(
            segments: const [
              ButtonSegment(
                value: _ReportView.month,
                label: Text('Por mes'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
              ButtonSegment(
                value: _ReportView.bank,
                label: Text('Imp. bancarias'),
                icon: Icon(Icons.account_balance_outlined),
              ),
            ],
            selected: {view},
            onSelectionChanged: (values) => onViewChanged(values.first),
          ),
        ),
        if (view == _ReportView.month) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<DateTime>(
            key: const Key('report_month_filter'),
            value: selectedMonth,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mes del reporte',
              prefixIcon: Icon(Icons.calendar_view_month_outlined),
            ),
            items:
                (availableMonths.isEmpty
                        ? <DateTime>[selectedMonth]
                        : availableMonths)
                    .map(
                      (month) => DropdownMenuItem<DateTime>(
                        value: month,
                        child: Text(_monthLabel(month)),
                      ),
                    )
                    .toList(),
            onChanged:
                availableMonths.isEmpty
                    ? null
                    : (value) {
                      if (value != null) onMonthChanged(value);
                    },
          ),
          const SizedBox(height: 5),
          Text(
            'Los datos registrados en HomeWallet están separados por mes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (view == _ReportView.bank) ...[
          const SizedBox(height: 18),
          Text(
            'Importaciones bancarias',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text('¿Qué banco quieres ver?'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children:
                _BankSelection.values
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value.label),
                        selected: bank == value,
                        onSelected: (selected) {
                          if (selected) onBankChanged(value);
                        },
                      ),
                    )
                    .toList(),
          ),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Período del archivo: ${DateFormat('dd/MM/yyyy').format(dates.first)} – ${DateFormat('dd/MM/yyyy').format(dates.last)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todas las categorías'),
            ),
            ...categories.map(
              (value) => DropdownMenuItem<String?>(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: onCategoryChanged,
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
                  'Usará únicamente los datos de la vista y categoría seleccionadas.',
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
        if (view == _ReportView.month) ...[
          _MonthlyComparisonCard(comparison: comparison),
          const SizedBox(height: 16),
        ],
        if (transactions.isEmpty)
          const _EmptyReport()
        else ...[
          if (view == _ReportView.bank) ...[
            _BankTrendChart(transactions: transactions, bank: bank),
            const SizedBox(height: 16),
          ],
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
                  'Resultado',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(balance),
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
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.donut_large_outlined,
            title: 'Destino de los gastos',
            children:
                destinationCategories.isEmpty
                    ? const [Text('No hay gastos en este periodo.')]
                    : destinationCategories
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
            title: 'Consejos',
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
        ],
      ],
    );
  }

  int _total(TransactionType type) => transactions
      .where((item) => item.type == type)
      .fold(0, (sum, item) => sum + item.amountMinor);

  static List<_Tip> _buildTips({
    required int income,
    required int expenses,
    required int otherExpense,
    required String? topCategory,
  }) {
    final result = <_Tip>[];
    if (otherExpense > 0) {
      result.add(
        const _Tip(
          Icons.category_outlined,
          '¿Qué se fue a “Otros”? Revisa esos movimientos y asígnales una categoría más específica.',
          true,
        ),
      );
    }
    if (topCategory != null) {
      result.add(
        _Tip(
          Icons.trending_up,
          'Mejora tus hábitos: revisa primero $topCategory, que concentra el mayor gasto del período.',
          false,
        ),
      );
    }
    if (income > 0 && expenses > income) {
      result.add(
        const _Tip(
          Icons.warning_amber_outlined,
          'Los gastos superan los ingresos de este período. Revisa pagos repetidos o consumos que puedas reducir.',
          true,
        ),
      );
    }
    if (result.isEmpty) {
      result.add(
        const _Tip(
          Icons.auto_awesome_outlined,
          'Mejora tus hábitos revisando cada semana los gastos y sus categorías.',
          false,
        ),
      );
    }
    return result;
  }
}

class _MonthlyComparisonCard extends StatelessWidget {
  const _MonthlyComparisonCard({required this.comparison});

  final MonthlyComparison comparison;

  @override
  Widget build(BuildContext context) {
    final expenseChange = comparison.expenseChangePercent;
    final incomeChange = comparison.incomeChangePercent;
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.compare_arrows_outlined,
      title: 'Comparación con ${_monthLabel(comparison.previousMonth)}',
      children: [
        _ComparisonRow(
          label: 'Gastos',
          currentMinor: comparison.currentExpenseMinor,
          previousMinor: comparison.previousExpenseMinor,
          changePercent: expenseChange,
          increaseIsPositive: false,
        ),
        const SizedBox(height: 12),
        _ComparisonRow(
          label: 'Ingresos',
          currentMinor: comparison.currentIncomeMinor,
          previousMinor: comparison.previousIncomeMinor,
          changePercent: incomeChange,
          increaseIsPositive: true,
        ),
        if (comparison.categoryWithLargestIncrease != null &&
            comparison.largestCategoryIncreaseMinor > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Mayor aumento: ${comparison.categoryWithLargestIncrease} '
            '(+${_money(comparison.largestCategoryIncreaseMinor)}).',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.currentMinor,
    required this.previousMinor,
    required this.changePercent,
    required this.increaseIsPositive,
  });

  final String label;
  final int currentMinor;
  final int previousMinor;
  final double? changePercent;
  final bool increaseIsPositive;

  @override
  Widget build(BuildContext context) {
    final change = changePercent;
    final increased = change != null && change > 0;
    final decreased = change != null && change < 0;
    final favorable = increased ? increaseIsPositive : decreased;
    final color =
        change == null || change == 0
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : favorable
            ? const Color(0xFF047857)
            : Theme.of(context).colorScheme.error;
    final description =
        change == null
            ? previousMinor == 0 && currentMinor == 0
                ? 'Sin valores en ambos meses'
                : 'Sin valor previo para calcular porcentaje'
            : change == 0
            ? 'Sin cambio'
            : '${change.abs().toStringAsFixed(0)}% ${change > 0 ? 'más' : 'menos'}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                'Antes ${_money(previousMinor)} · ahora ${_money(currentMinor)}',
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          description,
          textAlign: TextAlign.end,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _BankTrendChart extends StatelessWidget {
  const _BankTrendChart({required this.transactions, required this.bank});

  final List<FinanceTransaction> transactions;
  final _BankSelection bank;

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, int>{};
    for (final item in transactions) {
      final day = DateTime(
        item.occurredAt.year,
        item.occurredAt.month,
        item.occurredAt.day,
      );
      final signed =
          item.type == TransactionType.income
              ? item.amountMinor
              : -item.amountMinor;
      byDay.update(day, (value) => value + signed, ifAbsent: () => signed);
    }
    final entries =
        byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    var running = 0;
    final points = <double>[];
    for (final entry in entries) {
      running += entry.value;
      points.add(running.toDouble());
    }
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.show_chart,
      title: 'Evolución · ${bank.label}',
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              values: points,
              lineColor: scheme.primary,
              fillColor: scheme.primaryContainer,
              gridColor: scheme.outlineVariant,
            ),
          ),
        ),
        if (entries.isNotEmpty)
          Row(
            children: [
              Text(DateFormat('dd/MM').format(entries.first.key)),
              const Spacer(),
              Text(DateFormat('dd/MM').format(entries.last.key)),
            ],
          ),
        const SizedBox(height: 6),
        const Text(
          'Variación acumulada de ingresos y gastos del estado de cuenta.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = gridColor;
    for (var row = 0; row <= 3; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final minValue = math.min(0, values.reduce(math.min));
    final maxValue = math.max(0, values.reduce(math.max));
    final span = math.max(1, maxValue - minValue);
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x =
          values.length == 1
              ? size.width / 2
              : size.width * index / (values.length - 1);
      final y = size.height - ((values[index] - minValue) / span * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill =
        Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(fill, Paint()..color = fillColor.withValues(alpha: .5));
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.gridColor != gridColor;
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
  const _ExportChoice({
    required this.scope,
    required this.format,
    required this.memberUids,
    required this.memberNames,
  });

  final TransactionExportScope scope;
  final _ExportFormat format;
  final Set<String> memberUids;
  final Map<String, String> memberNames;
}

enum _PeopleExportMode { mine, household, selected }

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({
    required this.transactions,
    required this.members,
    required this.currentUid,
    required this.currentUserName,
    required this.householdKind,
  });

  final List<FinanceTransaction> transactions;
  final List<HouseholdMember> members;
  final String currentUid;
  final String currentUserName;
  final HouseholdKind householdKind;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late TransactionExportScope _scope;
  _PeopleExportMode _peopleMode = _PeopleExportMode.mine;
  final Set<String> _selectedMemberUids = {};

  @override
  void initState() {
    super.initState();
    _scope =
        widget.transactions.every(
              (item) => item.origin == TransactionOrigin.imported,
            )
            ? TransactionExportScope.imported
            : TransactionExportScope.homeWallet;
    if (widget.currentUid.isNotEmpty) {
      _selectedMemberUids.add(widget.currentUid);
    }
  }

  Map<String, String> get _memberNames {
    final result = <String, String>{};
    if (widget.currentUid.isNotEmpty) {
      result[widget.currentUid] =
          widget.currentUserName.trim().isEmpty
              ? 'Yo'
              : widget.currentUserName.trim();
    }
    for (final member in widget.members) {
      result[member.uid] = member.displayName;
    }
    for (final transaction in widget.transactions) {
      result.putIfAbsent(transaction.createdBy, () => 'Integrante');
    }
    return result;
  }

  bool get _isSharedHousehold =>
      widget.householdKind != HouseholdKind.individual &&
      _memberNames.length > 1;

  Set<String> get _selectedUids {
    if (!_isSharedHousehold) {
      return widget.currentUid.isEmpty ? const {} : {widget.currentUid};
    }
    return switch (_peopleMode) {
      _PeopleExportMode.mine => {widget.currentUid},
      _PeopleExportMode.household => _memberNames.keys.toSet(),
      _PeopleExportMode.selected => _selectedMemberUids,
    };
  }

  List<FinanceTransaction> get _selectedTransactions =>
      transactionsForExport(widget.transactions, _scope)
          .where(
            (item) =>
                _selectedUids.isEmpty || _selectedUids.contains(item.createdBy),
          )
          .toList();

  _ExportChoice _choice(_ExportFormat format) => _ExportChoice(
    scope: _scope,
    format: format,
    memberUids: _selectedUids,
    memberNames: _memberNames,
  );

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedTransactions.length;
    final orderedMembers =
        _memberNames.entries.toList()..sort((left, right) {
          if (left.key == widget.currentUid) return -1;
          if (right.key == widget.currentUid) return 1;
          return left.value.compareTo(right.value);
        });
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
              'El periodo, el origen y la categoría ya están aplicados. Elige de quién será el reporte.',
            ),
            const SizedBox(height: 18),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListTile(
                leading: Icon(_scope.icon),
                title: Text(_scope.title),
                subtitle: const Text(
                  'Definido por la vista actual del reporte.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '1. ¿De quién quieres descargar los datos?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (!_isSharedHousehold)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    widget.currentUserName.trim().isEmpty
                        ? 'Mi reporte individual'
                        : widget.currentUserName,
                  ),
                  subtitle: const Text('Solo incluye tus registros.'),
                  trailing: const Icon(Icons.check_circle),
                ),
              )
            else ...[
              RadioListTile<_PeopleExportMode>(
                value: _PeopleExportMode.mine,
                groupValue: _peopleMode,
                title: const Text('Solo mis datos'),
                subtitle: Text(
                  _memberNames[widget.currentUid] ?? 'Usuario actual',
                ),
                onChanged: (value) => setState(() => _peopleMode = value!),
              ),
              RadioListTile<_PeopleExportMode>(
                value: _PeopleExportMode.household,
                groupValue: _peopleMode,
                title: const Text('Todo el espacio'),
                subtitle: const Text(
                  'Primero aparecerán tus datos y después los de cada integrante, separados por nombre.',
                ),
                onChanged: (value) => setState(() => _peopleMode = value!),
              ),
              RadioListTile<_PeopleExportMode>(
                value: _PeopleExportMode.selected,
                groupValue: _peopleMode,
                title: const Text('Elegir integrantes'),
                subtitle: const Text('Selecciona una o varias personas.'),
                onChanged:
                    (value) => setState(() {
                      _peopleMode = value!;
                      if (_selectedMemberUids.isEmpty &&
                          widget.currentUid.isNotEmpty) {
                        _selectedMemberUids.add(widget.currentUid);
                      }
                    }),
              ),
              if (_peopleMode == _PeopleExportMode.selected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children:
                        orderedMembers
                            .map(
                              (member) => FilterChip(
                                label: Text(
                                  member.key == widget.currentUid
                                      ? '${member.value} (yo)'
                                      : member.value,
                                ),
                                selected: _selectedMemberUids.contains(
                                  member.key,
                                ),
                                onSelected:
                                    (selected) => setState(() {
                                      if (selected) {
                                        _selectedMemberUids.add(member.key);
                                      } else {
                                        _selectedMemberUids.remove(member.key);
                                      }
                                    }),
                              ),
                            )
                            .toList(),
                  ),
                ),
            ],
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
                      : () =>
                          Navigator.pop(context, _choice(_ExportFormat.excel)),
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
                              _choice(_ExportFormat.pdf),
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
                              _choice(_ExportFormat.csv),
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
        'No se pudo generar el reporte. Revisa el acceso cifrado del espacio.\n$error',
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

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;

String _monthLabel(DateTime value) {
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
  return '${months[value.month - 1]} ${value.year}';
}
