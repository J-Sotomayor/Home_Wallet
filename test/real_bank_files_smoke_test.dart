import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/services/bank_statement_service.dart';

void main() {
  const service = BankStatementService();

  for (final entry
      in <String, String>{
        'HOMEWALLET_BANK_XLS': 'importa el XLS bancario real',
        'HOMEWALLET_BANK_XLSX': 'importa el XLSX bancario real',
      }.entries) {
    final path = Platform.environment[entry.key];
    test(
      entry.value,
      () async {
        final file = File(path!);
        final result = await service.importFile(
          fileName: _fileName(path),
          bytes: await file.readAsBytes(),
          path: path,
        );

        expect(result.items, isNotEmpty);
        expect(result.bankName, anyOf('Banco Pichincha', 'Banco Guayaquil'));
        // No imprime descripciones, cuentas ni montos de los archivos reales.
        // ignore: avoid_print
        print(
          '${result.bankName}: ${result.items.length} movimientos; '
          'totales verificados=${result.totalsVerified}',
        );
      },
      skip:
          path == null
              ? 'Define ${entry.key} para ejecutar esta prueba.'
              : false,
    );
  }

  final pdfPath = Platform.environment['HOMEWALLET_BANK_PDF'];
  final pdftotext = Platform.environment['HOMEWALLET_PDFTOTEXT'];
  test(
    'importa el PDF bancario real',
    () async {
      final extraction = await Process.run(
        pdftotext!,
        ['-layout', pdfPath!, '-'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(extraction.exitCode, 0, reason: '${extraction.stderr}');

      final pages =
          (extraction.stdout as String)
              .split('\f')
              .where((page) => page.trim().isNotEmpty)
              .toList();
      final result = service.parsePdfPages(_fileName(pdfPath), pages);

      expect(result.bankName, 'Banco Pichincha');
      expect(result.items, isNotEmpty);
      expect(result.totalsVerified, isTrue);
      // ignore: avoid_print
      print(
        '${result.bankName}: ${result.items.length} movimientos; '
        'totales verificados=${result.totalsVerified}',
      );
    },
    skip:
        pdfPath == null || pdftotext == null
            ? 'Define HOMEWALLET_BANK_PDF y HOMEWALLET_PDFTOTEXT.'
            : false,
  );
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;
