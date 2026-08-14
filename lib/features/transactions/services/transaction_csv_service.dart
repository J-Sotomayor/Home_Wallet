import 'dart:convert';
import 'dart:typed_data';

import '../domain/finance_models.dart';
import 'transaction_import_rules.dart';

class ImportedTransaction {
  const ImportedTransaction({
    required this.description,
    required this.amountMinor,
    required this.occurredAt,
    required this.type,
    required this.category,
  });

  final String description;
  final int amountMinor;
  final DateTime occurredAt;
  final TransactionType type;
  final String category;
}

class TransactionCsvService {
  const TransactionCsvService();

  List<ImportedTransaction> importBytes(Uint8List bytes) {
    final content = utf8
        .decode(bytes, allowMalformed: true)
        .replaceFirst('\ufeff', '');
    final lines =
        const LineSplitter()
            .convert(content)
            .where((line) => line.trim().isNotEmpty)
            .toList();
    if (lines.length < 2) {
      throw const FormatException('El archivo CSV no contiene movimientos.');
    }

    final delimiter = _detectDelimiter(lines.first);
    final headers =
        _parseLine(
          lines.first,
          delimiter,
        ).map(TransactionImportRules.normalize).toList();
    final descriptionIndex = _column(headers, const [
      'descripcion',
      'detalle',
      'concepto',
      'description',
      'merchant',
      'comercio',
    ]);
    final dateIndex = _column(headers, const [
      'fecha',
      'fecha transaccion',
      'date',
      'transaction date',
    ]);
    final amountIndex = _column(headers, const [
      'monto',
      'importe',
      'valor',
      'amount',
    ]);
    final debitIndex = _column(headers, const ['debito', 'cargo', 'debit']);
    final creditIndex = _column(headers, const ['credito', 'abono', 'credit']);
    final typeIndex = _column(headers, const ['tipo', 'type', 'movimiento']);
    final categoryIndex = _column(headers, const ['categoria', 'category']);

    if (descriptionIndex == null ||
        (amountIndex == null && debitIndex == null && creditIndex == null)) {
      throw const FormatException(
        'No se reconocieron las columnas. Incluye Descripción y Monto, o columnas Débito/Crédito.',
      );
    }

    final result = <ImportedTransaction>[];
    for (final line in lines.skip(1)) {
      final values = _parseLine(line, delimiter);
      String valueAt(int? index) =>
          index != null && index < values.length ? values[index].trim() : '';

      final description = valueAt(descriptionIndex);
      if (description.isEmpty) continue;

      int? signedAmount;
      TransactionType? forcedType;
      final debit = TransactionImportRules.parseSignedMinor(
        valueAt(debitIndex),
      );
      final credit = TransactionImportRules.parseSignedMinor(
        valueAt(creditIndex),
      );
      if (credit != null && credit != 0) {
        signedAmount = credit.abs();
        forcedType = TransactionType.income;
      } else if (debit != null && debit != 0) {
        signedAmount = debit.abs();
        forcedType = TransactionType.expense;
      } else {
        signedAmount = TransactionImportRules.parseSignedMinor(
          valueAt(amountIndex),
        );
      }
      if (signedAmount == null || signedAmount == 0) continue;

      final type =
          forcedType ??
          TransactionImportRules.inferType(
            valueAt(typeIndex),
            signedAmount,
            description,
          );
      final amountMinor = signedAmount.abs();
      final importedCategory = valueAt(categoryIndex);
      final category = TransactionImportRules.categoryFor(
        type,
        description,
        sourceCategory: importedCategory,
      );
      result.add(
        ImportedTransaction(
          description:
              description.length > 100
                  ? description.substring(0, 100)
                  : description,
          amountMinor: amountMinor,
          occurredAt:
              TransactionImportRules.parseDate(valueAt(dateIndex)) ??
              DateTime.now(),
          type: type,
          category: category,
        ),
      );
    }
    if (result.isEmpty) {
      throw const FormatException('No se encontraron movimientos válidos.');
    }
    return result;
  }

  Uint8List exportBytes(
    List<FinanceTransaction> transactions, {
    Map<String, String> memberNames = const {},
  }) {
    final includeMember = memberNames.isNotEmpty;
    final buffer = StringBuffer(
      includeMember
          ? '\ufeffIntegrante,Fecha,Tipo,Categoría,Descripción,Monto\r\n'
          : '\ufeffFecha,Tipo,Categoría,Descripción,Monto\r\n',
    );
    final ordered = [...transactions]..sort((left, right) {
      if (includeMember) {
        final byMember = (memberNames[left.createdBy] ?? 'Integrante')
            .compareTo(memberNames[right.createdBy] ?? 'Integrante');
        if (byMember != 0) return byMember;
      }
      return left.occurredAt.compareTo(right.occurredAt);
    });
    for (final transaction in ordered) {
      final date = transaction.occurredAt.toIso8601String().split('T').first;
      final type = switch (transaction.type) {
        TransactionType.income => 'Ingreso',
        TransactionType.expense => 'Gasto',
        TransactionType.saving => 'Ahorro',
      };
      if (includeMember) {
        buffer
          ..write(_quote(memberNames[transaction.createdBy] ?? 'Integrante'))
          ..write(',');
      }
      buffer
        ..write(_quote(date))
        ..write(',')
        ..write(_quote(type))
        ..write(',')
        ..write(_quote(transaction.category))
        ..write(',')
        ..write(_quote(transaction.description))
        ..write(',')
        ..write((transaction.amountMinor / 100).toStringAsFixed(2))
        ..write('\r\n');
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static String _quote(String value) => '"${value.replaceAll('"', '""')}"';

  static String _detectDelimiter(String line) {
    final counts = <String, int>{
      ',': ','.allMatches(line).length,
      ';': ';'.allMatches(line).length,
      '\t': '\t'.allMatches(line).length,
    };
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<String> _parseLine(String line, String delimiter) {
    final fields = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (character == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          current.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == delimiter && !quoted) {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(character);
      }
    }
    fields.add(current.toString());
    return fields;
  }

  static int? _column(List<String> headers, List<String> aliases) {
    for (final alias in aliases) {
      final index = headers.indexOf(alias);
      if (index >= 0) return index;
    }
    return null;
  }
}
