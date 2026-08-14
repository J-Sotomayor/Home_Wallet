import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/core/errors/app_exception.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/domain/transaction_validation.dart';

void main() {
  FinanceTransactionDraft draft(DateTime occurredAt) => FinanceTransactionDraft(
    description: 'Movimiento histórico',
    category: 'Otros',
    amountMinor: 1000,
    occurredAt: occurredAt,
    type: TransactionType.expense,
    shared: false,
  );

  test('accepts historical movements without an arbitrary cutoff', () {
    expect(
      () => validateTransactionDraft(
        draft(DateTime(1901, 2, 3)),
        now: DateTime(2026, 8, 14),
      ),
      returnsNormally,
    );
  });

  test('accepts the earliest date supported by the UI', () {
    expect(
      () => validateTransactionDraft(
        draft(DateTime(1, 1, 1)),
        now: DateTime(2026, 8, 14),
      ),
      returnsNormally,
    );
  });

  test('rejects future movements', () {
    expect(
      () => validateTransactionDraft(
        draft(DateTime(2026, 8, 15)),
        now: DateTime(2026, 8, 14),
      ),
      throwsA(isA<AppException>()),
    );
  });
}
