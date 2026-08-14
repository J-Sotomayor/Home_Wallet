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
    List<FinancePlan> plans, {
    DateTime? currentPeriod,
  }) {
    var income = 0;
    var generalExpenses = 0;
    var expenses = 0;
    var savingsContributions = 0;
    var savingsWithdrawals = 0;
    var goalContributions = 0;

    for (final transaction in transactions) {
      // Legacy shared transactions are reimbursement calculations, not cash
      // flow. New bill splits live in their own collection.
      if (!transaction.countsInHouseholdFinances) continue;
      if (currentPeriod != null &&
          !transaction.affectsLiveBalanceAt(currentPeriod)) {
        continue;
      }
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
            item.countsInHouseholdFinances &&
            item.type == TransactionType.expense &&
            item.occurredAt.year == now.year &&
            item.occurredAt.month == now.month &&
            (plan.category == null || item.category == plan.category),
      )
      .fold<int>(0, (sum, item) => sum + item.amountMinor);
}

class FinancePlanProgress {
  const FinancePlanProgress({
    required this.currentMinor,
    required this.targetMinor,
    required this.remainingMinor,
    required this.ratio,
    required this.activityCount,
    required this.nextMilestone,
    this.latestActivityAt,
    this.recommendedMonthlyMinor,
  });

  final int currentMinor;
  final int targetMinor;
  final int remainingMinor;
  final double ratio;
  final int activityCount;
  final DateTime? latestActivityAt;
  final double nextMilestone;
  final int? recommendedMonthlyMinor;

  bool get complete => ratio >= 1;
}

FinancePlanProgress calculatePlanProgress(
  FinancePlan plan,
  List<FinanceTransaction> transactions,
  DateTime now,
) {
  final relevant =
      transactions.where((item) {
          if (!item.countsInHouseholdFinances) return false;
          if (plan.kind == FinancePlanKind.goal) {
            return item.linkedPlanId == plan.id && item.planDeltaMinor != 0;
          }
          return item.type == TransactionType.expense &&
              item.occurredAt.year == now.year &&
              item.occurredAt.month == now.month &&
              (plan.category == null || item.category == plan.category);
        }).toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  final current = automaticPlanProgress(plan, transactions, now);
  final remaining = (plan.targetMinor - current).clamp(0, 99999999999);
  final ratio = plan.targetMinor <= 0 ? 0.0 : current / plan.targetMinor;
  final nextMilestone = switch (ratio) {
    < .25 => .25,
    < .50 => .50,
    < .75 => .75,
    < 1 => 1.0,
    _ => 1.0,
  };
  int? monthly;
  if (plan.kind == FinancePlanKind.goal &&
      plan.deadline != null &&
      remaining > 0) {
    final days = plan.deadline!.difference(now).inDays.clamp(1, 36500);
    final months = (days / 30).ceil().clamp(1, 1200);
    monthly = (remaining / months).ceil();
  }
  return FinancePlanProgress(
    currentMinor: current,
    targetMinor: plan.targetMinor,
    remainingMinor: remaining,
    ratio: ratio,
    activityCount: relevant.length,
    latestActivityAt: relevant.isEmpty ? null : relevant.first.occurredAt,
    nextMilestone: nextMilestone,
    recommendedMonthlyMinor: monthly,
  );
}
