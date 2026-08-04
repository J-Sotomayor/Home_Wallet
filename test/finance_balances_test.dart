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
}
