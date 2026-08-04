import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/finance_models.dart';

class FinanceInsights extends StatelessWidget {
  const FinanceInsights({super.key, required this.transactions});

  final List<FinanceTransaction> transactions;

  static const _chartColors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF64748B),
  ];
  static const _months = <String>[
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor =
        dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    final expenseColor = scheme.error;
    final now = DateTime.now();
    final monthly =
        transactions
            .where(
              (item) =>
                  item.occurredAt.year == now.year &&
                  item.occurredAt.month == now.month,
            )
            .toList();
    final income = _total(monthly, TransactionType.income);
    final expenses = _total(monthly, TransactionType.expense);
    final savings = _total(monthly, TransactionType.saving);
    final expenseShare = income == 0 ? 0.0 : expenses / income;
    final savingsRate = income == 0 ? 0.0 : (savings / income).clamp(0.0, 1.0);
    final byCategory = <String, int>{};
    for (final item in monthly.where(
      (item) => item.type == TransactionType.expense,
    )) {
      byCategory.update(
        item.category,
        (value) => value + item.amountMinor,
        ifAbsent: () => item.amountMinor,
      );
    }
    final categories =
        byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Análisis de ${_months[now.month - 1]}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _MetricBars(
              income: income,
              expenses: expenses,
              savings: savings,
              incomeColor: incomeColor,
              expenseColor: expenseColor,
              savingColor: scheme.primary,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PercentageTile(
                    label: 'Gasto/ingreso',
                    value: expenseShare,
                    color: expenseColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PercentageTile(
                    label: 'Tasa de ahorro',
                    value: savingsRate,
                    color: incomeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              '¿En qué se fue el dinero?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 14),
            if (expenses == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Agrega gastos este mes para ver el gráfico.'),
                ),
              )
            else ...[
              Center(
                child: SizedBox.square(
                  dimension: 156,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(156),
                        painter: _DonutPainter(
                          values:
                              categories.map((entry) => entry.value).toList(),
                          colors: _chartColors,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '100%',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Text('gastos'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ...categories.take(6).toList().asMap().entries.map((indexed) {
                final entry = indexed.value;
                final percentage = entry.value / expenses;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color:
                              _chartColors[indexed.key % _chartColors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.key)),
                      Text(
                        '${(percentage * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Text(_money(entry.value)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  static int _total(List<FinanceTransaction> values, TransactionType type) =>
      values
          .where((item) => item.type == type)
          .fold(0, (sum, item) => sum + item.amountMinor);
}

class _MetricBars extends StatelessWidget {
  const _MetricBars({
    required this.income,
    required this.expenses,
    required this.savings,
    required this.incomeColor,
    required this.expenseColor,
    required this.savingColor,
  });

  final int income;
  final int expenses;
  final int savings;
  final Color incomeColor;
  final Color expenseColor;
  final Color savingColor;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(1, math.max(income, math.max(expenses, savings)));
    return Column(
      children: [
        _MetricBar(
          label: 'Ingresos',
          value: income,
          fraction: income / maximum,
          color: incomeColor,
        ),
        const SizedBox(height: 10),
        _MetricBar(
          label: 'Gastos',
          value: expenses,
          fraction: expenses / maximum,
          color: expenseColor,
        ),
        const SizedBox(height: 10),
        _MetricBar(
          label: 'Ahorros',
          value: savings,
          fraction: savings / maximum,
          color: savingColor,
        ),
      ],
    );
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          SizedBox(width: 68, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1),
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(
              _money(value),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ],
  );
}

class _PercentageTile extends StatelessWidget {
  const _PercentageTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '${(value * 100).clamp(0, 999).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return;
    final rect = Offset.zero & size;
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    const gap = 0.025;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      paint.color = colors[index % colors.length];
      canvas.drawArc(
        rect.deflate(14),
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);
