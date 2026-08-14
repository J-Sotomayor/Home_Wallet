import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/services/transaction_csv_service.dart';
import 'package:homewallet/features/transactions/services/transaction_import_identity.dart';

void main() {
  const identity = TransactionImportIdentity();

  test('produces the same hash for an imported and stored movement', () async {
    final imported = ImportedTransaction(
      description: '  Pago   supermercado ',
      amountMinor: 2599,
      occurredAt: DateTime(2026, 8, 14),
      type: TransactionType.expense,
      category: 'Alimentación',
    );
    final stored = FinanceTransaction(
      id: 'stored',
      description: 'pago supermercado',
      category: 'Alimentación',
      amountMinor: 2599,
      occurredAt: DateTime(2026, 8, 14, 18, 30),
      type: TransactionType.expense,
      createdBy: 'user',
      shared: false,
      origin: TransactionOrigin.imported,
    );

    expect(
      await identity.forImported(imported),
      await identity.forExisting(stored),
    );
  });

  test('changes the hash when the amount changes', () async {
    final first = ImportedTransaction(
      description: 'Pago supermercado',
      amountMinor: 2599,
      occurredAt: DateTime(2026, 8, 14),
      type: TransactionType.expense,
      category: 'Alimentación',
    );
    final second = ImportedTransaction(
      description: first.description,
      amountMinor: 2600,
      occurredAt: first.occurredAt,
      type: first.type,
      category: first.category,
    );

    expect(
      await identity.forImported(first),
      isNot(await identity.forImported(second)),
    );
  });
}
