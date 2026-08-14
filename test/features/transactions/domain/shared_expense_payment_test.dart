import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';

void main() {
  final expense = SharedExpense(
    id: 'dinner',
    description: 'Cena',
    category: 'Comida y restaurantes',
    totalMinor: 10000,
    occurredAt: DateTime(2026, 8, 14),
    createdBy: 'payer',
    paidByUid: 'payer',
    splitMode: ExpenseSplitMode.equal,
    participantSharesMinor: const {'payer': 5000, 'debtor': 5000},
  );

  test('reported payments do not settle a debt before confirmation', () {
    final payment = SharedExpensePayment(
      id: 'payment',
      expenseId: expense.id,
      participantUid: 'debtor',
      payerUid: 'payer',
      amountMinor: 2000,
      createdAt: DateTime(2026, 8, 14),
      createdBy: 'debtor',
      status: SharedExpensePaymentStatus.reported,
    );

    expect(expense.reportedPaidMinorFor('debtor', [payment]), 2000);
    expect(expense.remainingMinorFor('debtor', [payment]), 5000);
  });

  test('confirmed partial payments reduce only the participant debt', () {
    final payment = SharedExpensePayment(
      id: 'payment',
      expenseId: expense.id,
      participantUid: 'debtor',
      payerUid: 'payer',
      amountMinor: 2000,
      createdAt: DateTime(2026, 8, 14),
      createdBy: 'debtor',
      status: SharedExpensePaymentStatus.confirmed,
    );

    expect(expense.confirmedPaidMinorFor('debtor', [payment]), 2000);
    expect(expense.remainingMinorFor('debtor', [payment]), 3000);
    expect(expense.pendingMinorWith([payment]), 3000);
  });

  test('confirmed payments are capped at the assigned share', () {
    final overpayment = SharedExpensePayment(
      id: 'payment',
      expenseId: expense.id,
      participantUid: 'debtor',
      payerUid: 'payer',
      amountMinor: 9000,
      createdAt: DateTime(2026, 8, 14),
      createdBy: 'debtor',
      status: SharedExpensePaymentStatus.confirmed,
    );

    expect(expense.confirmedPaidMinorFor('debtor', [overpayment]), 5000);
    expect(expense.remainingMinorFor('debtor', [overpayment]), 0);
  });
}
