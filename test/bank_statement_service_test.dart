import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/services/bank_statement_service.dart';
import 'package:homewallet/features/transactions/services/transaction_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const statements = BankStatementService();
  const exports = TransactionExportService();

  test('reconoce y concilia un PDF digital de Banco Pichincha', () {
    final result = statements.parsePdfPages('estado.pdf', const [
      'BANCO PICHINCHA\n'
          'FECHA ESTE CORTE\n'
          '05-06-2026\n'
          'DEPÓSITO / CRÉDITOS\n'
          '(1)\n'
          '40.00\n'
          'CHEQUES / DÉBITOS\n'
          '(1)\n'
          '10.00\n',
      'DETALLE DE MOVIMIENTOS\n'
          'FECHA\nOFIC.\nN.DOC.\nDESCRIPCION\nDEBITO\nCREDITO\nSALDO\n'
          '11-may.\n12\n123\nCNSM GAS ESTACION DE SERVICIO\n10.00\n0.00\n30.00\n'
          '12-may.\n12\n124\nTRANSFERENCIA INTERBANCARIA RECIBIDA\n0.00\n40.00\n70.00\n',
    ]);

    expect(result.bankName, 'Banco Pichincha');
    expect(result.items, hasLength(2));
    expect(result.totalFor(TransactionType.income), 4000);
    expect(result.totalFor(TransactionType.expense), 1000);
    expect(result.items.first.category, 'Transporte');
    expect(result.totalsVerified, isTrue);
  });

  test('reconoce y concilia el PDF de cuenta corriente Banco Guayaquil', () {
    final result = statements.parsePdfPages('EECC_BG_202604.pdf', const [
      'BANCO GUAYAQUIL S.A.\n'
          'FECHA DE CORTE: 2026/MAR/17 - 2026/ABR/20\n'
          'FECHA OFICINA NUMERO CANAL TIPO DESCRIPCION VALOR SALDO\n'
          '23/MAR MAT 485537 BVI N/C TRANSF.INTRABANCARIAS 100.00 152.09\n'
          '30/MAR MAT 587676 BVI N/D RECAUD. EEE QUITO 14.13 132.15\n'
          '20/ABR MAT 215856 VEN N/C PAGO DIRECTO PICHINCHA 300.00 347.67\n'
          'RESUMEN DE MOVIMIENTOS\n'
          '3 NOTAS DE CREDITO 400.00\n'
          '1 NOTAS DE DEBITO 14.13\n',
    ]);

    expect(result.bankName, 'Banco Guayaquil');
    expect(result.items, hasLength(3));
    expect(result.totalFor(TransactionType.income), 40000);
    expect(result.totalFor(TransactionType.expense), 1413);
    expect(result.items[1].category, 'Luz');
    expect(result.totalsVerified, isTrue);
  });

  test('acepta el orden de texto que entrega PDFBox en Android', () {
    final result = statements.parsePdfPages('estado.pdf', const [
      'BANCO PICHINCHA C.A.\n'
          'FECHA ESTE CORTE 05-06-2026\n'
          'DEPÓSITO / CRÉDITOS (1) 40.00\n'
          'CHEQUES / DÉBITOS (1) 10.00\n',
      'DETALLE DE MOVIMIENTOS\n'
          'FECHA OFIC. N.DOC. DESCRIPCION DEBITO CREDITO SALDO\n'
          '11-may. 12 1234567\n'
          '8\n'
          'CNSM GAS ESTACION DE SERVICIOS 10.00 0.00 30.00\n'
          '12-may. 12 124 TRANSFERENCIA INTERBANCARIA RECIBIDA 0.00 40.00 70.00\n'
          'ESTADO DE CUENTA\n',
    ]);

    expect(result.items, hasLength(2));
    expect(result.totalFor(TransactionType.income), 4000);
    expect(result.totalFor(TransactionType.expense), 1000);
    expect(result.items.first.category, 'Transporte');
    expect(result.totalsVerified, isTrue);
  });

  test('acepta la etiqueta FECHA ESTE CORTE (FACTURA) del PDF real', () {
    final result = statements.parsePdfPages('estado.pdf', const [
      'BANCO PICHINCHA C.A.\n'
          'CUENTA 123456 FECHA ESTE CORTE (FACTURA)\n'
          '05-06-2026\n'
          'DEPÓSITO / CRÉDITOS (1) 40.00\n'
          'CHEQUES / DÉBITOS (1) 10.00\n',
      'DETALLE DE MOVIMIENTOS\n'
          '11-may. 12 123 CNSM GAS ESTACION DE SERVICIO 10.00 0.00 30.00\n'
          '12-may. 12 124 TRANSFERENCIA INTERBANCARIA RECIBIDA 0.00 40.00 70.00\n',
    ]);

    expect(result.items, hasLength(2));
    expect(result.totalsVerified, isTrue);
  });

  test('rechaza un extracto cuyos movimientos no cuadran', () {
    expect(
      () => statements.parsePdfPages('estado.pdf', const [
        'BANCO PICHINCHA\n'
            'FECHA ESTE CORTE\n05-06-2026\n'
            'DEPÓSITO / CRÉDITOS\n50.00\n'
            'CHEQUES / DÉBITOS\n10.00\n',
        'DETALLE DE MOVIMIENTOS\n'
            '11-may.\n12\n123\nCOMPRA POS\n10.00\n0.00\n30.00\n'
            '12-may.\n12\n124\nDEPOSITO\n0.00\n40.00\n70.00\n',
      ]),
      throwsFormatException,
    );
  });

  test('el Excel exportado conserva tipos, categorías y montos', () async {
    final source = _transactions();
    final bytes = exports.exportExcel(source);
    final imported = await statements.importFile(
      fileName: 'homewallet_estado.xlsx',
      bytes: bytes,
    );

    expect(imported.items, hasLength(3));
    expect(
      imported.items.map((item) => item.type),
      containsAll(<TransactionType>[
        TransactionType.income,
        TransactionType.expense,
        TransactionType.saving,
      ]),
    );
    expect(imported.totalFor(TransactionType.income), 125000);
    expect(imported.totalFor(TransactionType.expense), 3025);
    expect(imported.totalFor(TransactionType.saving), 10000);
  });

  test('genera un PDF válido con contenido', () async {
    final bytes = await exports.exportPdf(_transactions());

    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(3000));
  });

  test('separa los movimientos propios de los importados al exportar', () {
    final values = [
      ..._transactions(),
      FinanceTransaction(
        id: 'bank-1',
        description: 'Compra importada',
        category: 'Compras',
        amountMinor: 1999,
        occurredAt: DateTime(2026, 7, 4),
        type: TransactionType.expense,
        createdBy: 'user',
        shared: false,
        origin: TransactionOrigin.imported,
        sourceName: 'Banco Pichincha · PDF',
      ),
    ];

    expect(
      transactionsForExport(values, TransactionExportScope.homeWallet),
      hasLength(3),
    );
    expect(
      transactionsForExport(values, TransactionExportScope.imported).single.id,
      'bank-1',
    );
    expect(
      transactionsForExport(values, TransactionExportScope.all),
      hasLength(4),
    );
  });
}

List<FinanceTransaction> _transactions() => [
  FinanceTransaction(
    id: '1',
    description: 'Sueldo mensual',
    category: 'Sueldo',
    amountMinor: 125000,
    occurredAt: DateTime(2026, 7, 1),
    type: TransactionType.income,
    createdBy: 'user',
    shared: true,
  ),
  FinanceTransaction(
    id: '2',
    description: 'Supermercado familiar',
    category: 'Alimentación',
    amountMinor: 3025,
    occurredAt: DateTime(2026, 7, 2),
    type: TransactionType.expense,
    createdBy: 'user',
    shared: true,
  ),
  FinanceTransaction(
    id: '3',
    description: 'Fondo de emergencia',
    category: 'Fondo de emergencia',
    amountMinor: 10000,
    occurredAt: DateTime(2026, 7, 3),
    type: TransactionType.saving,
    createdBy: 'user',
    shared: true,
  ),
];
