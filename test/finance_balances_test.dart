import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_balances.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';

void main() {
  test('separa disponible, ahorros y metas sin mostrar saldo negativo', () {
    final now = DateTime(2026, 8, 2);
    final transactions = [
      FinanceTransaction(
        id: 'income',
        description: 'Sueldo',
        category: 'Sueldo',
        amountMinor: 100000,
        occurredAt: now,
        type: TransactionType.income,
        createdBy: 'u1',
        shared: false,
      ),
      FinanceTransaction(
        id: 'saving',
        description: 'Fondo',
        category: 'Fondo de emergencia',
        amountMinor: 30000,
        occurredAt: now,
        type: TransactionType.saving,
        createdBy: 'u1',
        shared: false,
      ),
      FinanceTransaction(
        id: 'goal',
        description: 'Aporte a viaje',
        category: 'Vacaciones',
        amountMinor: 20000,
        occurredAt: now,
        type: TransactionType.saving,
        createdBy: 'u1',
        shared: false,
        linkedPlanId: 'p1',
        linkedPlanName: 'Viaje',
        planDeltaMinor: 20000,
      ),
      FinanceTransaction(
        id: 'expense',
        description: 'Comida',
        category: 'Alimentación',
        amountMinor: 10000,
        occurredAt: now,
        type: TransactionType.expense,
        createdBy: 'u1',
        shared: false,
      ),
    ];
    const plans = [
      FinancePlan(
        id: 'p1',
        name: 'Viaje',
        kind: FinancePlanKind.goal,
        targetMinor: 100000,
        currentMinor: 20000,
        createdBy: 'u1',
      ),
    ];

    final balances = FinanceBalances.calculate(transactions, plans);

    expect(balances.income, 100000);
    expect(balances.available, 40000);
    expect(balances.savings, 30000);
    expect(balances.goals, 20000);
    expect(balances.uncoveredExpenses, 0);
  });

  test('calcula el presupuesto del mes por categoría automáticamente', () {
    final transactions = [
      FinanceTransaction(
        id: 'food',
        description: 'Mercado',
        category: 'Alimentación',
        amountMinor: 2500,
        occurredAt: DateTime(2026, 8, 2),
        type: TransactionType.expense,
        createdBy: 'u1',
        shared: false,
      ),
      FinanceTransaction(
        id: 'old',
        description: 'Mercado anterior',
        category: 'Alimentación',
        amountMinor: 9000,
        occurredAt: DateTime(2026, 7, 2),
        type: TransactionType.expense,
        createdBy: 'u1',
        shared: false,
      ),
    ];
    const plan = FinancePlan(
      id: 'budget',
      name: 'Comida',
      kind: FinancePlanKind.budget,
      targetMinor: 10000,
      currentMinor: 999999,
      createdBy: 'u1',
      category: 'Alimentación',
    );

    expect(
      automaticPlanProgress(plan, transactions, DateTime(2026, 8, 15)),
      2500,
    );
  });

  test('expone hitos y actividad del proceso de una meta', () {
    final now = DateTime(2026, 8, 9);
    final contribution = FinanceTransaction(
      id: 'contribution',
      description: 'Aporte de sueldo',
      category: 'Sueldo',
      amountMinor: 25000,
      occurredAt: DateTime(2026, 8, 8),
      type: TransactionType.income,
      createdBy: 'u1',
      shared: false,
      linkedPlanId: 'goal-1',
      linkedPlanName: 'Vacaciones',
      planDeltaMinor: 25000,
    );
    final plan = FinancePlan(
      id: 'goal-1',
      name: 'Vacaciones',
      kind: FinancePlanKind.goal,
      targetMinor: 100000,
      currentMinor: 25000,
      createdBy: 'u1',
      deadline: DateTime(2026, 11, 9),
    );

    final progress = calculatePlanProgress(plan, [contribution], now);

    expect(progress.currentMinor, 25000);
    expect(progress.remainingMinor, 75000);
    expect(progress.ratio, .25);
    expect(progress.nextMilestone, .5);
    expect(progress.activityCount, 1);
    expect(progress.latestActivityAt, DateTime(2026, 8, 8));
    expect(progress.recommendedMonthlyMinor, 18750);
  });

  test('un ingreso asignado aumenta la meta sin duplicar saldo disponible', () {
    final income = FinanceTransaction(
      id: 'direct-income',
      description: 'Ingreso para viaje',
      category: 'Sueldo',
      amountMinor: 40000,
      occurredAt: DateTime(2026, 8, 9),
      type: TransactionType.income,
      createdBy: 'u1',
      shared: false,
      linkedPlanId: 'goal-1',
      linkedPlanName: 'Viaje',
      planDeltaMinor: 40000,
    );
    const goal = FinancePlan(
      id: 'goal-1',
      name: 'Viaje',
      kind: FinancePlanKind.goal,
      targetMinor: 100000,
      currentMinor: 40000,
      createdBy: 'u1',
    );

    final balances = FinanceBalances.calculate([income], const [goal]);

    expect(balances.income, 40000);
    expect(balances.goals, 40000);
    expect(balances.available, 0);
    expect(
      calculatePlanProgress(goal, [income], DateTime(2026, 8, 9)).ratio,
      .4,
    );
  });

  test('una división no altera saldos ni presupuestos', () {
    final shared = FinanceTransaction(
      id: 'legacy-shared',
      description: 'Cena dividida',
      category: 'Alimentación',
      amountMinor: 6000,
      occurredAt: DateTime(2026, 8, 2),
      type: TransactionType.expense,
      createdBy: 'u1',
      shared: true,
      paidByUid: 'u1',
      participantSharesMinor: const {'u1': 3000, 'u2': 3000},
    );
    const plan = FinancePlan(
      id: 'budget',
      name: 'Comida',
      kind: FinancePlanKind.budget,
      targetMinor: 10000,
      currentMinor: 0,
      createdBy: 'u1',
      category: 'Alimentación',
    );

    final balances = FinanceBalances.calculate([shared], const [plan]);

    expect(balances.expenses, 0);
    expect(balances.available, 0);
    expect(automaticPlanProgress(plan, [shared], DateTime(2026, 8, 15)), 0);
  });

  test('la cuenta separada calcula sólo lo pendiente por devolver', () {
    final expense = SharedExpense(
      id: 'split-1',
      description: 'Cena',
      category: 'Comida y restaurantes',
      totalMinor: 9000,
      occurredAt: DateTime(2026, 8, 2),
      createdBy: 'u1',
      paidByUid: 'u1',
      splitMode: ExpenseSplitMode.equal,
      participantSharesMinor: const {'u1': 3000, 'u2': 3000, 'u3': 3000},
      settledParticipantIds: const {'u2'},
    );

    expect(expense.pendingMinor, 3000);
  });
}
