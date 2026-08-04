import 'finance_models.dart';

class FinanceBalances {
  const FinanceBalances({
    required this.income,
    required this.expenses,
    required this.available,
    required this.savings,
    required this.goals,
    required this.uncoveredExpenses,
  });

  factory FinanceBalances.calculate(
    List<FinanceTransaction> transactions,
    List<FinancePlan> plans,
  ) {
    var income = 0;
    var generalExpenses = 0;
    var expenses = 0;
    var savingsContributions = 0;
    var savingsWithdrawals = 0;
    var goalContributions = 0;

    for (final transaction in transactions) {
      switch (transaction.type) {
        case TransactionType.income:
          income += transaction.amountMinor;
          if (transaction.linkedPlanId != null &&
              transaction.planDeltaMinor > 0) {
            goalContributions += transaction.planDeltaMinor;
          }
        case TransactionType.saving:
          if (transaction.linkedPlanId == null) {
            savingsContributions += transaction.amountMinor;
          } else if (transaction.planDeltaMinor > 0) {
            goalContributions += transaction.planDeltaMinor;
          }
        case TransactionType.expense:
          expenses += transaction.amountMinor;
          switch (transaction.fundingSource) {
            case ExpenseFundingSource.general:
              generalExpenses += transaction.amountMinor;
            case ExpenseFundingSource.savings:
              savingsWithdrawals += transaction.amountMinor;
            case ExpenseFundingSource.goal:
              break;
          }
      }
    }

    final spendableIncome = income - savingsContributions - goalContributions;
    final available = (spendableIncome - generalExpenses).clamp(0, 99999999999);
    final uncovered = (generalExpenses - spendableIncome).clamp(0, 99999999999);
    final savings = (savingsContributions - savingsWithdrawals).clamp(
      0,
      99999999999,
    );
    final goals = plans
        .where((plan) => plan.kind == FinancePlanKind.goal && plan.isActive)
        .fold<int>(0, (sum, plan) => sum + plan.currentMinor);

    return FinanceBalances(
      income: income,
      expenses: expenses,
      available: available,
      savings: savings,
      goals: goals,
      uncoveredExpenses: uncovered,
    );
  }

  final int income;
  final int expenses;
  final int available;
  final int savings;
  final int goals;
  final int uncoveredExpenses;
}

int automaticPlanProgress(
  FinancePlan plan,
  List<FinanceTransaction> transactions,
  DateTime now,
) {
  if (plan.kind == FinancePlanKind.goal) return plan.currentMinor;
  return transactions
      .where(
        (item) =>
            item.type == TransactionType.expense &&
            item.occurredAt.year == now.year &&
            item.occurredAt.month == now.month &&
            (plan.category == null || item.category == plan.category),
      )
      .fold<int>(0, (sum, item) => sum + item.amountMinor);
}
