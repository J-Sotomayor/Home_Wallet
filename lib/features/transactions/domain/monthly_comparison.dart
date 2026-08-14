import 'finance_models.dart';

class MonthlyComparison {
  const MonthlyComparison({
    required this.month,
    required this.previousMonth,
    required this.currentIncomeMinor,
    required this.previousIncomeMinor,
    required this.currentExpenseMinor,
    required this.previousExpenseMinor,
    this.categoryWithLargestIncrease,
    this.largestCategoryIncreaseMinor = 0,
  });

  final DateTime month;
  final DateTime previousMonth;
  final int currentIncomeMinor;
  final int previousIncomeMinor;
  final int currentExpenseMinor;
  final int previousExpenseMinor;
  final String? categoryWithLargestIncrease;
  final int largestCategoryIncreaseMinor;

  double? get expenseChangePercent =>
      _changePercent(currentExpenseMinor, previousExpenseMinor);

  double? get incomeChangePercent =>
      _changePercent(currentIncomeMinor, previousIncomeMinor);

  static double? _changePercent(int current, int previous) =>
      previous == 0 ? null : (current - previous) * 100 / previous;
}

MonthlyComparison compareFinancialMonths(
  List<FinanceTransaction> transactions,
  DateTime month, {
  String? category,
}) {
  final normalizedMonth = DateTime(month.year, month.month);
  final previousMonth = DateTime(month.year, month.month - 1);
  final current = <FinanceTransaction>[];
  final previous = <FinanceTransaction>[];

  for (final transaction in transactions) {
    if (!transaction.countsInHouseholdFinances ||
        transaction.origin != TransactionOrigin.manual ||
        (category != null && transaction.category != category)) {
      continue;
    }
    if (_sameMonth(transaction.occurredAt, normalizedMonth)) {
      current.add(transaction);
    } else if (_sameMonth(transaction.occurredAt, previousMonth)) {
      previous.add(transaction);
    }
  }

  int total(List<FinanceTransaction> values, TransactionType type) => values
      .where((item) => item.type == type)
      .fold(0, (sum, item) => sum + item.amountMinor);

  final currentCategories = _expenseTotalsByCategory(current);
  final previousCategories = _expenseTotalsByCategory(previous);
  String? largestCategory;
  var largestIncrease = 0;
  for (final name in {...currentCategories.keys, ...previousCategories.keys}) {
    final increase =
        (currentCategories[name] ?? 0) - (previousCategories[name] ?? 0);
    if (increase > largestIncrease) {
      largestIncrease = increase;
      largestCategory = name;
    }
  }

  return MonthlyComparison(
    month: normalizedMonth,
    previousMonth: previousMonth,
    currentIncomeMinor: total(current, TransactionType.income),
    previousIncomeMinor: total(previous, TransactionType.income),
    currentExpenseMinor: total(current, TransactionType.expense),
    previousExpenseMinor: total(previous, TransactionType.expense),
    categoryWithLargestIncrease: largestCategory,
    largestCategoryIncreaseMinor: largestIncrease,
  );
}

Map<String, int> _expenseTotalsByCategory(
  List<FinanceTransaction> transactions,
) {
  final totals = <String, int>{};
  for (final transaction in transactions.where(
    (item) => item.type == TransactionType.expense,
  )) {
    totals.update(
      transaction.category,
      (value) => value + transaction.amountMinor,
      ifAbsent: () => transaction.amountMinor,
    );
  }
  return totals;
}

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;
