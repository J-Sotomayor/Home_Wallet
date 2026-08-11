import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/core/errors/app_exception.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/domain/transaction_validation.dart';

void main() {
  final referenceNow = DateTime(2026, 8, 11, 10, 49);
  final oldTemplate = FinanceTransactionDraft(
    description: 'Sueldo',
    category: 'Sueldo',
    amountMinor: 55000,
    occurredAt: DateTime(2024, 1, 1),
    type: TransactionType.income,
    shared: false,
  );

  test('una plantilla recurrente no caduca por superar 365 días', () {
    expect(
      () => validateTransactionDraft(
        oldTemplate,
        enforceHistoryWindow: false,
        now: referenceNow,
      ),
      returnsNormally,
    );
  });

  test('un movimiento normal sí respeta la ventana de 365 días', () {
    expect(
      () => validateTransactionDraft(oldTemplate, now: referenceNow),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          contains('últimos 365 días'),
        ),
      ),
    );
  });
}
