import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/services/transaction_csv_service.dart';
import 'package:homewallet/features/transactions/services/transaction_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const exports = TransactionExportService();
  const csv = TransactionCsvService();
  final transactions = <FinanceTransaction>[
    FinanceTransaction(
      id: 'income',
      description: 'Sueldo agosto',
      category: 'Sueldo',
      amountMinor: 120000,
      occurredAt: DateTime(2026, 8, 1),
      type: TransactionType.income,
      createdBy: 'owner',
      shared: false,
    ),
    FinanceTransaction(
      id: 'expense',
      description: 'Supermercado',
      category: 'Alimentacion',
      amountMinor: 2567,
      occurredAt: DateTime(2026, 8, 2),
      type: TransactionType.expense,
      createdBy: 'owner',
      shared: false,
    ),
  ];

  test('generates a valid XLSX package', () {
    final bytes = exports.exportExcel(transactions);

    expect(bytes, isNotEmpty);
    expect(bytes.take(2), <int>[0x50, 0x4b]);
  });

  test('generates a valid PDF document', () async {
    final bytes = await exports.exportPdf(transactions);

    expect(bytes, isNotEmpty);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('generates CSV with the selected financial data', () {
    final content = utf8.decode(csv.exportBytes(transactions));

    expect(content, contains('Sueldo agosto'));
    expect(content, contains('Supermercado'));
    expect(content, contains('1200.00'));
  });
}
