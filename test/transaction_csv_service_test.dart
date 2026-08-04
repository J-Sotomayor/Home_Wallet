import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/domain/transaction_categories.dart';
import 'package:homewallet/features/transactions/services/transaction_csv_service.dart';

void main() {
  const service = TransactionCsvService();

  test('las categorías son independientes por tipo', () {
    expect(TransactionCategories.expenses, isNot(contains('Ahorro')));
    expect(TransactionCategories.incomes, contains('Sueldo'));
    expect(TransactionCategories.incomes, isNot(contains('Alimentación')));
    expect(TransactionCategories.savings, contains('Vacaciones'));
  });

  test('importa CSV bancario con montos firmados y asigna categorías', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        'Fecha;Descripción;Monto\n'
        '02/08/2026;Nómina mensual;482,00\n'
        '02/08/2026;Supermercado;-150,00\n'
        '03/08/2026;Ahorro vacaciones;-50,00\n',
      ),
    );

    final values = service.importBytes(bytes);

    expect(values, hasLength(3));
    expect(values[0].type, TransactionType.income);
    expect(values[0].category, 'Sueldo');
    expect(values[0].amountMinor, 48200);
    expect(values[1].type, TransactionType.expense);
    expect(values[1].category, 'Alimentación');
    expect(values[2].type, TransactionType.saving);
    expect(values[2].category, 'Vacaciones');
  });

  test('exporta un CSV legible con ahorro separado', () {
    final bytes = service.exportBytes([
      FinanceTransaction(
        id: '1',
        description: 'Fondo, familiar',
        category: 'Fondo de emergencia',
        amountMinor: 1250,
        occurredAt: DateTime(2026, 8, 2),
        type: TransactionType.saving,
        createdBy: 'user',
        shared: true,
      ),
    ]);
    final csv = utf8.decode(bytes);

    expect(csv, contains('Ahorro'));
    expect(csv, contains('"Fondo, familiar"'));
    expect(csv, contains('12.50'));
  });
}
