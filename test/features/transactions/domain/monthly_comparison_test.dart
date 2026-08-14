import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/domain/monthly_comparison.dart';

void main() {
  test('compares expenses and income with the previous calendar month', () {
    final transactions = [
      _transaction(
        'old-food',
        10000,
        DateTime(2026, 7, 5),
        TransactionType.expense,
        'Comida',
      ),
      _transaction(
        'new-food',
        11800,
        DateTime(2026, 8, 5),
        TransactionType.expense,
        'Comida',
      ),
      _transaction(
        'old-income',
        50000,
        DateTime(2026, 7, 1),
        TransactionType.income,
        'Sueldo',
      ),
      _transaction(
        'new-income',
        55000,
        DateTime(2026, 8, 1),
        TransactionType.income,
        'Sueldo',
      ),
    ];

    final result = compareFinancialMonths(transactions, DateTime(2026, 8));

    expect(result.expenseChangePercent, closeTo(18, 0.001));
    expect(result.incomeChangePercent, closeTo(10, 0.001));
    expect(result.categoryWithLargestIncrease, 'Comida');
    expect(result.largestCategoryIncreaseMinor, 1800);
  });
}

FinanceTransaction _transaction(
  String id,
  int amountMinor,
  DateTime occurredAt,
  TransactionType type,
  String category,
) => FinanceTransaction(
  id: id,
  description: id,
  category: category,
  amountMinor: amountMinor,
  occurredAt: occurredAt,
  type: type,
  createdBy: 'user',
  shared: false,
);
