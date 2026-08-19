import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/services/bank_statement_service.dart';

void main() {
  const service = BankStatementService();

  test('imports a HomeWallet PDF when text is extracted by columns', () {
    const page = '''
H HOMEWALLET
ESTADO DE MOVIMIENTOS
Resumen del periodo
01/08/2026 al 03/08/2026
DETALLE DE MOVIMIENTOS
FECHA
TIPO
CATEGORÍA
DESCRIPCIÓN
01/08/2026
Ingreso
Sueldo
Sueldo agosto
02/08/2026
Gasto
Alimentación
Supermercado
03/08/2026
Ahorro
Vacaciones
Fondo para viaje
DÉBITO
CRÉDITO
\$1.200,00
\$25,67
\$100,00
Total débitos: \$125,67 Total créditos: \$1.200,00
Generado por HomeWallet. Tus datos permanecen bajo tu control.
''';

    final result = service.parsePdfPages('reporte-homewallet.pdf', [page]);

    expect(result.bankName, 'HomeWallet');
    expect(result.items, hasLength(3));
    expect(result.items[0].type, TransactionType.income);
    expect(result.items[0].amountMinor, 120000);
    expect(result.items[0].description, 'Sueldo agosto');
    expect(result.items[1].type, TransactionType.expense);
    expect(result.items[1].amountMinor, 2567);
    expect(result.items[2].type, TransactionType.saving);
    expect(result.items[2].amountMinor, 10000);
    expect(result.totalsVerified, isTrue);
  });

  test('imports a HomeWallet PDF when each movement is one text row', () {
    const page = '''
HOMEWALLET
DETALLE DE MOVIMIENTOS
FECHA  TIPO  CATEGORÍA  DESCRIPCIÓN  DÉBITO  CRÉDITO
01/08/2026 Ingreso Sueldo Sueldo agosto \$1.200,00
02/08/2026 Gasto Alimentacion Supermercado \$25,67
Total débitos: \$25,67 Total créditos: \$1.200,00
''';

    final result = service.parsePdfPages('movimientos.pdf', [page]);

    expect(result.items, hasLength(2));
    expect(result.items.first.category, 'Sueldo');
    expect(result.items.last.category, 'Alimentación');
  });

  test('explains that analysis-only HomeWallet PDFs cannot be imported', () {
    const page = '''
HOMEWALLET
ANÁLISIS BANCARIO
SALUD FINANCIERA
RECOMENDACIONES
''';

    expect(
      () => service.parsePdfPages('analisis.pdf', [page]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('solo el análisis'),
        ),
      ),
    );
  });
}
