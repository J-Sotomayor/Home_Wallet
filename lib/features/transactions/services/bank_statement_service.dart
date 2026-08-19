import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:excel2003/excel2003.dart';
import 'package:read_pdf_text/read_pdf_text.dart';

import '../domain/finance_models.dart';
import '../domain/transaction_categories.dart';
import 'transaction_csv_service.dart';
import 'transaction_import_rules.dart';

enum BankStatementFormat { csv, xls, xlsx, pdf }

class BankStatementImportResult {
  const BankStatementImportResult({
    required this.bankName,
    required this.format,
    required this.items,
    required this.totalsVerified,
    this.declaredIncomeMinor,
    this.declaredExpenseMinor,
  });

  final String bankName;
  final BankStatementFormat format;
  final List<ImportedTransaction> items;
  final bool totalsVerified;
  final int? declaredIncomeMinor;
  final int? declaredExpenseMinor;

  int totalFor(TransactionType type) => items
      .where((item) => item.type == type)
      .fold(0, (sum, item) => sum + item.amountMinor);

  String get formatLabel => switch (format) {
    BankStatementFormat.csv => 'CSV',
    BankStatementFormat.xls => 'Excel 97-2003',
    BankStatementFormat.xlsx => 'Excel',
    BankStatementFormat.pdf => 'PDF',
  };
}

class BankStatementService {
  const BankStatementService({this.csvService = const TransactionCsvService()});

  final TransactionCsvService csvService;

  Future<BankStatementImportResult> importFile({
    required String fileName,
    required Uint8List bytes,
    String? path,
  }) async {
    final extension = _extension(fileName);
    return switch (extension) {
      'csv' => _csv(fileName, bytes),
      'xls' => _spreadsheet(fileName, bytes, legacy: true),
      'xlsx' => _spreadsheet(fileName, bytes, legacy: false),
      'pdf' => _pdf(fileName, path),
      _ =>
        throw const FormatException(
          'Formato no compatible. Selecciona un archivo CSV, XLS, XLSX o PDF.',
        ),
    };
  }

  BankStatementImportResult parsePdfPages(String fileName, List<String> pages) {
    final allText = pages.join('\n');
    final normalized = TransactionImportRules.normalize(allText);
    if (normalized.contains('homewallet')) {
      if (!normalized.contains('detalle de movimientos')) {
        throw const FormatException(
          'Este reporte de HomeWallet contiene solo el análisis y no incluye movimientos para importar. Exporta un reporte con detalle o usa el archivo Excel o CSV.',
        );
      }
      return _parseHomeWalletPdf(pages, allText);
    }
    if (normalized.contains('banco guayaquil') &&
        normalized.contains('resumen de movimientos')) {
      return _parseGuayaquilPdf(pages, allText);
    }
    if (!normalized.contains('banco pichincha') &&
        !normalized.contains('detalle de movimientos')) {
      throw const FormatException(
        'No se reconoció la estructura de este PDF. Usa el PDF digital original de Banco Pichincha o importa el Excel del banco.',
      );
    }

    final lines =
        pages
            .expand((page) => page.split(RegExp(r'\r?\n')))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
    final statementEnd = _valueAfterLabelDate(lines, const [
      'fecha este corte',
      'fecha este corte (factura)',
    ]);
    if (statementEnd == null) {
      throw const FormatException(
        'No se pudo identificar el periodo del estado de cuenta PDF.',
      );
    }

    final items = <ImportedTransaction>[];
    for (final page in pages) {
      items.addAll(_parsePichinchaPdfPage(page, statementEnd));
    }
    if (items.isEmpty) {
      throw const FormatException(
        'El PDF no contiene movimientos bancarios legibles. Comprueba que sea el archivo digital original y no una fotografía.',
      );
    }

    final declaredIncome = _moneyAfterLabel(lines, const [
      'deposito / creditos',
      'depositos / creditos',
    ]);
    final declaredExpense = _moneyAfterLabel(lines, const [
      'cheques / debitos',
      'cheques/debitos',
    ]);
    return _validatedResult(
      bankName: 'Banco Pichincha',
      format: BankStatementFormat.pdf,
      items: items,
      declaredIncomeMinor: declaredIncome,
      declaredExpenseMinor: declaredExpense,
    );
  }

  BankStatementImportResult _parseHomeWalletPdf(
    List<String> pages,
    String allText,
  ) {
    final items = <ImportedTransaction>[];
    for (final page in pages) {
      items.addAll(_parseHomeWalletPdfPage(page));
    }
    if (items.isEmpty) {
      throw const FormatException(
        'El reporte de HomeWallet no contiene movimientos legibles. Exporta nuevamente el reporte con el detalle de movimientos o usa Excel o CSV.',
      );
    }

    final declaredIncome = _homeWalletTotal(allText, 'total creditos');
    final declaredDebits = _homeWalletTotal(allText, 'total debitos');
    final saving = items
        .where((item) => item.type == TransactionType.saving)
        .fold<int>(0, (sum, item) => sum + item.amountMinor);
    final declaredExpense =
        declaredDebits == null || declaredDebits < saving
            ? null
            : declaredDebits - saving;
    return _validatedResult(
      bankName: 'HomeWallet',
      format: BankStatementFormat.pdf,
      items: items,
      declaredIncomeMinor: declaredIncome,
      declaredExpenseMinor: declaredExpense,
    );
  }

  List<ImportedTransaction> _parseHomeWalletPdfPage(String page) {
    final lines =
        page
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
    if (lines.isEmpty) return const [];

    var tableStart = lines.indexWhere(
      (line) =>
          TransactionImportRules.normalize(line) == 'detalle de movimientos',
    );
    if (tableStart < 0) {
      tableStart = lines.indexWhere(
        (line) => TransactionImportRules.normalize(line) == 'fecha',
      );
    }
    if (tableStart < 0) return const [];

    final rowBased = <ImportedTransaction>[];
    for (final line in lines.skip(tableStart + 1)) {
      final match = RegExp(
        r'^(\d{1,2}/\d{1,2}/\d{2,4})\s+(Ingreso|Gasto|Ahorro)\s+(.+?)\s+([-\u0024€£]?\s*\d[\d.,]*[.,]\d{2})\s*$',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;
      final occurredAt = _homeWalletDate(match.group(1)!);
      final type = _homeWalletType(match.group(2)!);
      final amount = TransactionImportRules.parseSignedMinor(match.group(4)!);
      if (occurredAt == null || type == null || amount == null || amount == 0) {
        continue;
      }
      final parsedText = _homeWalletRowText(type, match.group(3)!);
      final category = parsedText.category;
      final description = parsedText.description;
      if (description.isEmpty) continue;
      rowBased.add(
        ImportedTransaction(
          description: description,
          amountMinor: amount.abs(),
          occurredAt: occurredAt,
          type: type,
          category: TransactionImportRules.categoryFor(
            type,
            description,
            sourceCategory: category,
          ),
        ),
      );
    }
    if (rowBased.isNotEmpty) return rowBased;

    final datePositions = <int>[];
    for (var index = tableStart + 1; index < lines.length; index++) {
      if (_homeWalletDate(lines[index]) != null) datePositions.add(index);
    }
    if (datePositions.isEmpty) return const [];

    final drafts = <_HomeWalletPdfDraft>[];
    final sharedAmounts = <int>[];
    for (var index = 0; index < datePositions.length; index++) {
      final start = datePositions[index];
      final end =
          index + 1 < datePositions.length
              ? datePositions[index + 1]
              : lines.length;
      final segment = lines.sublist(start + 1, end);
      final sharedHeader = segment.indexWhere((line) {
        final value = TransactionImportRules.normalize(line);
        return value == 'debito' || value == 'credito';
      });
      final metadata =
          sharedHeader < 0 ? segment : segment.sublist(0, sharedHeader);
      if (sharedHeader >= 0) {
        for (final line in segment.skip(sharedHeader + 1)) {
          if (!_isStandaloneMoney(line)) continue;
          final amount = TransactionImportRules.parseSignedMinor(line);
          if (amount != null && amount != 0) sharedAmounts.add(amount.abs());
        }
      }

      final typePosition = metadata.indexWhere(
        (line) => _homeWalletType(line) != null,
      );
      if (typePosition < 0) continue;
      final type = _homeWalletType(metadata[typePosition])!;
      final content =
          metadata
              .skip(typePosition + 1)
              .where((line) => !_isHomeWalletPdfNoise(line))
              .toList();
      final ownMoneyPosition = content.indexWhere(_isStandaloneMoney);
      final ownAmount =
          ownMoneyPosition < 0
              ? null
              : TransactionImportRules.parseSignedMinor(
                content[ownMoneyPosition],
              )?.abs();
      final textContent =
          ownMoneyPosition < 0 ? content : content.sublist(0, ownMoneyPosition);
      if (textContent.isEmpty) continue;
      final category = textContent.first;
      final description = TransactionImportRules.cleanDescription(
        textContent.length == 1 ? category : textContent.sublist(1).join(' '),
      );
      drafts.add(
        _HomeWalletPdfDraft(
          occurredAt: _homeWalletDate(lines[start])!,
          type: type,
          category: category,
          description: description,
          amountMinor: ownAmount,
        ),
      );
    }

    var sharedAmountIndex = 0;
    final result = <ImportedTransaction>[];
    for (final draft in drafts) {
      var amount = draft.amountMinor;
      if ((amount == null || amount == 0) &&
          sharedAmountIndex < sharedAmounts.length) {
        amount = sharedAmounts[sharedAmountIndex++];
      }
      if (amount == null || amount == 0 || draft.description.isEmpty) continue;
      result.add(
        ImportedTransaction(
          description: draft.description,
          amountMinor: amount,
          occurredAt: draft.occurredAt,
          type: draft.type,
          category: TransactionImportRules.categoryFor(
            draft.type,
            draft.description,
            sourceCategory: draft.category,
          ),
        ),
      );
    }
    return result;
  }

  static int? _homeWalletTotal(String text, String normalizedLabel) {
    final normalized = TransactionImportRules.normalize(text);
    final match = RegExp(
      '${RegExp.escape(normalizedLabel)}\\s*:\\s*[-\u0024€£]?\\s*(\\d[\\d.,]*[.,]\\d{2})',
    ).firstMatch(normalized);
    return match == null
        ? null
        : TransactionImportRules.parseSignedMinor(match.group(1)!)?.abs();
  }

  static DateTime? _homeWalletDate(String value) {
    if (!RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(value.trim())) {
      return null;
    }
    return TransactionImportRules.parseDate(value);
  }

  static TransactionType? _homeWalletType(String value) {
    return switch (TransactionImportRules.normalize(value)) {
      'ingreso' => TransactionType.income,
      'gasto' => TransactionType.expense,
      'ahorro' => TransactionType.saving,
      _ => null,
    };
  }

  static _HomeWalletRowText _homeWalletRowText(
    TransactionType type,
    String value,
  ) {
    final words = value.trim().split(RegExp(r'\s+'));
    final categories =
        TransactionCategories.forType(type).toList()..sort(
          (left, right) => right
              .split(RegExp(r'\s+'))
              .length
              .compareTo(left.split(RegExp(r'\s+')).length),
        );
    for (final category in categories) {
      final wordCount = category.split(RegExp(r'\s+')).length;
      if (words.length <= wordCount) continue;
      final sourceCategory = words.take(wordCount).join(' ');
      if (TransactionImportRules.normalize(sourceCategory) !=
          TransactionImportRules.normalize(category)) {
        continue;
      }
      return _HomeWalletRowText(
        category: sourceCategory,
        description: TransactionImportRules.cleanDescription(
          words.skip(wordCount).join(' '),
        ),
      );
    }
    return _HomeWalletRowText(
      category: words.first,
      description: TransactionImportRules.cleanDescription(
        words.length == 1 ? words.first : words.skip(1).join(' '),
      ),
    );
  }

  static bool _isHomeWalletPdfNoise(String value) {
    final normalized = TransactionImportRules.normalize(value);
    return const {
          'fecha',
          'tipo',
          'categoria',
          'descripcion',
          'debito',
          'credito',
          'detalle de movimientos',
        }.contains(normalized) ||
        normalized.startsWith('integrante ·') ||
        normalized.startsWith('total debitos:') ||
        normalized.startsWith('generado por homewallet') ||
        normalized.startsWith('pagina ');
  }

  BankStatementImportResult _parseGuayaquilPdf(
    List<String> pages,
    String allText,
  ) {
    final periodLine = allText
        .split(RegExp(r'\r?\n'))
        .where(
          (line) => TransactionImportRules.normalize(
            line,
          ).contains('fecha de corte:'),
        );
    final dates =
        periodLine.isEmpty
            ? const <RegExpMatch>[]
            : RegExp(
              r'(\d{4})/([A-Za-zÁÉÍÓÚÑáéíóúñ]{3})/(\d{1,2})',
              caseSensitive: false,
            ).allMatches(periodLine.first).toList();
    if (dates.length < 2) {
      throw const FormatException(
        'No se pudo identificar el periodo del estado de cuenta de Banco Guayaquil.',
      );
    }
    final periodEnd = dates.last;
    final year = int.parse(periodEnd.group(1)!);
    final month = _monthNumber(periodEnd.group(2)!);
    final day = int.parse(periodEnd.group(3)!);
    if (month == null) {
      throw const FormatException('El mes del estado de cuenta no es válido.');
    }
    final statementEnd = DateTime(year, month, day);
    final rowPattern = RegExp(
      r'^(\d{1,2}/[A-Za-zÁÉÍÓÚÑáéíóúñ]{3})\s+\S+\s+\d+\s+\S+\s+(N/[CD])\s+(.+?)\s+(\d[\d.,]*[.,]\d{2})\s+(\d[\d.,]*[.,]\d{2})(?:\s+\d[\d.,]*[.,]\d{2})?\s*$',
      caseSensitive: false,
    );
    final items = <ImportedTransaction>[];
    for (final line in pages.expand((page) => page.split(RegExp(r'\r?\n')))) {
      final match = rowPattern.firstMatch(line.trim());
      if (match == null) continue;
      final occurredAt = _shortDate(match.group(1)!, statementEnd);
      final amount = TransactionImportRules.parseSignedMinor(match.group(4)!);
      final description = TransactionImportRules.cleanDescription(
        match.group(3)!,
      );
      if (occurredAt == null ||
          amount == null ||
          amount == 0 ||
          description.isEmpty) {
        continue;
      }
      final type =
          match.group(2)!.toUpperCase() == 'N/C'
              ? TransactionType.income
              : TransactionType.expense;
      items.add(
        ImportedTransaction(
          description: description,
          amountMinor: amount.abs(),
          occurredAt: occurredAt,
          type: type,
          category: TransactionImportRules.categoryFor(type, description),
        ),
      );
    }
    if (items.isEmpty) {
      throw const FormatException(
        'El PDF de Banco Guayaquil no contiene movimientos legibles.',
      );
    }
    final credit = _summaryMoney(allText, 'NOTAS DE CREDITO');
    final debit = _summaryMoney(allText, 'NOTAS DE DEBITO');
    return _validatedResult(
      bankName: 'Banco Guayaquil',
      format: BankStatementFormat.pdf,
      items: items,
      declaredIncomeMinor: credit,
      declaredExpenseMinor: debit,
    );
  }

  static int? _summaryMoney(String text, String label) {
    final match = RegExp(
      '${RegExp.escape(label)}\\s+(-?\\d[\\d.,]*[.,]\\d{2})',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null
        ? null
        : TransactionImportRules.parseSignedMinor(match.group(1)!)?.abs();
  }

  static int? _monthNumber(String value) {
    const months = <String, int>{
      'ene': 1,
      'feb': 2,
      'mar': 3,
      'abr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'ago': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dic': 12,
    };
    final normalized = TransactionImportRules.normalize(value);
    return normalized.length < 3 ? null : months[normalized.substring(0, 3)];
  }

  Future<BankStatementImportResult> _pdf(String fileName, String? path) async {
    if (path == null || path.isEmpty) {
      throw const FormatException(
        'No se pudo acceder al PDF seleccionado. Descárgalo en el dispositivo y vuelve a intentarlo.',
      );
    }
    try {
      final pages = await ReadPdfText.getPDFtextPaginated(path);
      return parsePdfPages(fileName, pages);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException(
        'No se pudo leer el PDF. Comprueba que no tenga contraseña y que contenga texto seleccionable.',
      );
    }
  }

  BankStatementImportResult _csv(String fileName, Uint8List bytes) {
    final items = csvService.importBytes(bytes);
    return BankStatementImportResult(
      bankName: _bankFromName(fileName),
      format: BankStatementFormat.csv,
      items: items,
      totalsVerified: false,
    );
  }

  BankStatementImportResult _spreadsheet(
    String fileName,
    Uint8List bytes, {
    required bool legacy,
  }) {
    final sheets = <_StatementSheet>[];
    try {
      if (legacy) {
        final workbook = XlsReader.fromBytes(bytes);
        for (var index = 0; index < workbook.sheetCount; index++) {
          final sheet = workbook.sheet(index);
          sheets.add(_StatementSheet(name: sheet.name, rows: sheet.rows));
        }
      } else {
        final workbook = Excel.decodeBytes(bytes);
        for (final entry in workbook.tables.entries) {
          sheets.add(
            _StatementSheet(
              name: entry.key,
              rows:
                  entry.value.rows
                      .map(
                        (row) =>
                            row
                                .map((cell) => _excelValue(cell?.value))
                                .toList(),
                      )
                      .toList(),
            ),
          );
        }
      }
    } catch (_) {
      throw FormatException(
        legacy
            ? 'El archivo XLS está dañado, protegido o no corresponde a Excel 97-2003.'
            : 'El archivo XLSX está dañado o protegido con contraseña.',
      );
    }

    for (final sheet in sheets) {
      final header = _findHeader(sheet.rows);
      if (header == null) continue;
      final bankName = _detectBank(fileName, sheet, header);
      final items = _parseSpreadsheetRows(sheet.rows, header);
      if (items.isEmpty) continue;
      final totals = _declaredTotals(sheet.rows);
      return _validatedResult(
        bankName: bankName,
        format: legacy ? BankStatementFormat.xls : BankStatementFormat.xlsx,
        items: items,
        declaredIncomeMinor: totals.$1,
        declaredExpenseMinor: totals.$2,
      );
    }
    throw const FormatException(
      'No se reconocieron movimientos. El archivo debe incluir Fecha y Descripción, más Monto o columnas Débito/Crédito.',
    );
  }

  List<ImportedTransaction> _parseSpreadsheetRows(
    List<List<Object?>> rows,
    _HeaderMatch header,
  ) {
    final result = <ImportedTransaction>[];
    for (final row in rows.skip(header.rowIndex + 1)) {
      Object? valueAt(int? index) =>
          index != null && index < row.length ? row[index] : null;
      final occurredAt = _dateValue(valueAt(header.date));
      if (occurredAt == null) continue;

      final mainDescription = _stringValue(valueAt(header.description));
      final beneficiary = _stringValue(valueAt(header.beneficiary));
      final description = TransactionImportRules.cleanDescription(
        [
          mainDescription,
          if (beneficiary.isNotEmpty) beneficiary,
        ].where((value) => value.isNotEmpty).join(' · '),
      );
      if (description.isEmpty) continue;

      final debit = _minorValue(valueAt(header.debit));
      final credit = _minorValue(valueAt(header.credit));
      final rawAmount = _minorValue(valueAt(header.amount));
      final rawType = _stringValue(valueAt(header.type));
      TransactionType type;
      int amountMinor;
      if (credit != null && credit != 0) {
        type = TransactionType.income;
        amountMinor = credit.abs();
      } else if (debit != null && debit != 0) {
        type =
            TransactionImportRules.normalize(rawType).contains('ahorro')
                ? TransactionType.saving
                : TransactionType.expense;
        amountMinor = debit.abs();
      } else if (rawAmount != null && rawAmount != 0) {
        type = TransactionImportRules.inferType(
          rawType,
          rawAmount,
          description,
        );
        amountMinor = rawAmount.abs();
      } else {
        continue;
      }

      final sourceCategory = _stringValue(valueAt(header.category));
      result.add(
        ImportedTransaction(
          description: description,
          amountMinor: amountMinor,
          occurredAt: occurredAt,
          type: type,
          category: TransactionImportRules.categoryFor(
            type,
            description,
            sourceCategory: sourceCategory,
          ),
        ),
      );
    }
    return result;
  }

  List<ImportedTransaction> _parsePichinchaPdfPage(
    String page,
    DateTime statementEnd,
  ) {
    final lines =
        page
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
    final rowBased = _parsePichinchaPdfRows(lines, statementEnd);
    if (rowBased.isNotEmpty) return rowBased;

    final starts = <int>[];
    for (var index = 0; index < lines.length; index++) {
      if (_shortDateMatch(lines[index]) != null) starts.add(index);
    }
    final result = <ImportedTransaction>[];
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final end = index + 1 < starts.length ? starts[index + 1] : lines.length;
      final segment = lines.sublist(start, end);
      final occurredAt = _shortDate(segment.first, statementEnd);
      if (occurredAt == null) continue;

      var descriptionStart = -1;
      for (var part = 1; part < segment.length; part++) {
        if (RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(segment[part])) {
          descriptionStart = part;
          break;
        }
      }
      if (descriptionStart < 0) continue;

      final moneyPositions = <int>[];
      for (var part = descriptionStart + 1; part < segment.length; part++) {
        if (_isStandaloneMoney(segment[part])) moneyPositions.add(part);
        if (moneyPositions.length == 3) break;
      }
      if (moneyPositions.length < 3) continue;
      final description = TransactionImportRules.cleanDescription(
        segment
            .sublist(descriptionStart, moneyPositions.first)
            .where((line) => !_isRepeatedPdfHeader(line))
            .join(' '),
      );
      if (description.isEmpty) continue;

      final debit = TransactionImportRules.parseSignedMinor(
        segment[moneyPositions[0]],
      );
      final credit = TransactionImportRules.parseSignedMinor(
        segment[moneyPositions[1]],
      );
      if ((debit == null || debit == 0) && (credit == null || credit == 0)) {
        continue;
      }
      final type =
          credit != null && credit != 0
              ? TransactionType.income
              : TransactionType.expense;
      final amountMinor =
          type == TransactionType.income ? credit!.abs() : debit!.abs();
      result.add(
        ImportedTransaction(
          description: description,
          amountMinor: amountMinor,
          occurredAt: occurredAt,
          type: type,
          category: TransactionImportRules.categoryFor(type, description),
        ),
      );
    }
    return result;
  }

  List<ImportedTransaction> _parsePichinchaPdfRows(
    List<String> lines,
    DateTime statementEnd,
  ) {
    final starts = <int>[];
    for (var index = 0; index < lines.length; index++) {
      if (_shortDatePrefixMatch(lines[index]) != null) starts.add(index);
    }
    final result = <ImportedTransaction>[];
    final rowPattern = RegExp(
      r'^(\d{1,2}[-/ ][A-Za-zÁÉÍÓÚÑáéíóúñ]{3,}\.?)\s+\S+\s+\S+\s+(.+?)\s+(-?\d[\d.,]*[.,]\d{2})\s+(-?\d[\d.,]*[.,]\d{2})\s+(-?\d[\d.,]*[.,]\d{2})(?:\s|$)',
    );
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final end = index + 1 < starts.length ? starts[index + 1] : lines.length;
      final row = lines.sublist(start, end).join(' ');
      final match = rowPattern.firstMatch(row);
      if (match == null) continue;
      final occurredAt = _shortDate(match.group(1)!, statementEnd);
      final description = TransactionImportRules.cleanDescription(
        match.group(2)!,
      );
      final debit = TransactionImportRules.parseSignedMinor(match.group(3)!);
      final credit = TransactionImportRules.parseSignedMinor(match.group(4)!);
      if (occurredAt == null ||
          description.isEmpty ||
          ((debit == null || debit == 0) && (credit == null || credit == 0))) {
        continue;
      }
      final type =
          credit != null && credit != 0
              ? TransactionType.income
              : TransactionType.expense;
      final amountMinor =
          type == TransactionType.income ? credit!.abs() : debit!.abs();
      result.add(
        ImportedTransaction(
          description: description,
          amountMinor: amountMinor,
          occurredAt: occurredAt,
          type: type,
          category: TransactionImportRules.categoryFor(type, description),
        ),
      );
    }
    return result;
  }

  BankStatementImportResult _validatedResult({
    required String bankName,
    required BankStatementFormat format,
    required List<ImportedTransaction> items,
    required int? declaredIncomeMinor,
    required int? declaredExpenseMinor,
  }) {
    int total(TransactionType type) => items
        .where((item) => item.type == type)
        .fold(0, (sum, item) => sum + item.amountMinor);
    final income = total(TransactionType.income);
    final expense = total(TransactionType.expense);
    final incomeMatches =
        declaredIncomeMinor == null ||
        (income - declaredIncomeMinor).abs() <= 1;
    final expenseMatches =
        declaredExpenseMinor == null ||
        (expense - declaredExpenseMinor).abs() <= 1;
    if (!incomeMatches || !expenseMatches) {
      throw const FormatException(
        'El archivo se pudo leer, pero sus movimientos no cuadran con los totales declarados. No se importó nada para evitar datos incompletos.',
      );
    }
    return BankStatementImportResult(
      bankName: bankName,
      format: format,
      items: List.unmodifiable(items),
      totalsVerified:
          declaredIncomeMinor != null || declaredExpenseMinor != null,
      declaredIncomeMinor: declaredIncomeMinor,
      declaredExpenseMinor: declaredExpenseMinor,
    );
  }

  static _HeaderMatch? _findHeader(List<List<Object?>> rows) {
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final headers =
          rows[rowIndex]
              .map(
                (value) =>
                    TransactionImportRules.normalize(_stringValue(value)),
              )
              .toList();
      final date = _column(headers, const [
        'fecha',
        'fecha transaccion',
        'transaction date',
      ]);
      final description = _column(headers, const [
        'descripcion',
        'detalle',
        'concepto',
        'description',
        'merchant',
        'comercio',
      ]);
      final amount = _column(headers, const [
        'monto',
        'importe',
        'valor',
        'amount',
      ]);
      final debit = _column(headers, const ['debito', 'cargo', 'debit']);
      final credit = _column(headers, const ['credito', 'abono', 'credit']);
      if (date == null ||
          description == null ||
          (amount == null && debit == null && credit == null)) {
        continue;
      }
      return _HeaderMatch(
        rowIndex: rowIndex,
        date: date,
        description: description,
        amount: amount,
        debit: debit,
        credit: credit,
        type: _column(headers, const ['tipo', 'type', 'movimiento']),
        category: _column(headers, const ['categoria', 'category']),
        beneficiary: _column(headers, const [
          'beneficiario',
          'destinatario',
          'beneficiary',
        ]),
      );
    }
    return null;
  }

  static int? _column(List<String> headers, List<String> aliases) {
    for (final alias in aliases) {
      final index = headers.indexOf(alias);
      if (index >= 0) return index;
    }
    return null;
  }

  static (int?, int?) _declaredTotals(List<List<Object?>> rows) {
    int? income;
    int? expense;
    for (final row in rows) {
      for (var index = 0; index < row.length; index++) {
        final label = TransactionImportRules.normalize(
          _stringValue(row[index]),
        );
        if (label == 'ingresos' ||
            label.contains('depositos/creditos') ||
            label.contains('depositos / creditos')) {
          income ??= _nextMoneyInRow(row, index + 1);
        }
        if (label == 'egresos' ||
            label.contains('cheques/debitos') ||
            label.contains('cheques / debitos')) {
          expense ??= _nextMoneyInRow(row, index + 1);
        }
      }
    }
    return (income, expense);
  }

  static int? _nextMoneyInRow(List<Object?> row, int start) {
    for (var index = start; index < row.length; index++) {
      final value = _minorValue(row[index]);
      if (value != null) return value.abs();
    }
    return null;
  }

  static int? _moneyAfterLabel(List<String> lines, List<String> labels) {
    for (var index = 0; index < lines.length; index++) {
      final line = TransactionImportRules.normalize(lines[index]);
      final label = labels.where(
        (candidate) => line == candidate || line.contains(candidate),
      );
      if (label.isEmpty) continue;
      final inlineValues =
          RegExp(r'-?\d[\d.,]*[.,]\d{2}').allMatches(line).toList();
      if (inlineValues.isNotEmpty) {
        return TransactionImportRules.parseSignedMinor(
          inlineValues.last.group(0)!,
        )?.abs();
      }
      for (
        var next = index + 1;
        next < lines.length && next <= index + 5;
        next++
      ) {
        if (!_isStandaloneMoney(lines[next])) continue;
        return TransactionImportRules.parseSignedMinor(lines[next])?.abs();
      }
    }
    return null;
  }

  static DateTime? _valueAfterLabelDate(
    List<String> lines,
    List<String> labels,
  ) {
    for (var index = 0; index < lines.length; index++) {
      final line = TransactionImportRules.normalize(lines[index]);
      final label = labels.where(
        (candidate) => line == candidate || line.contains(candidate),
      );
      if (label.isEmpty) continue;
      // Some Pichincha statements print "FECHA ESTE CORTE (FACTURA)".
      // Prefer the most specific match so "(factura)" is not left in front
      // of the date and the real PDF can be parsed in both text orders.
      final matchedLabel = label.reduce(
        (current, candidate) =>
            candidate.length > current.length ? candidate : current,
      );
      final labelStart = line.indexOf(matchedLabel);
      final valueStart = labelStart + matchedLabel.length;
      if (line.length > valueStart) {
        final inlineDate = TransactionImportRules.parseDate(
          line.substring(valueStart).trim(),
        );
        if (inlineDate != null) return inlineDate;
      }
      for (
        var next = index + 1;
        next < lines.length && next <= index + 3;
        next++
      ) {
        final date = TransactionImportRules.parseDate(lines[next]);
        if (date != null) return date;
      }
    }
    return null;
  }

  static RegExpMatch? _shortDateMatch(String input) => RegExp(
    r'^(\d{1,2})[-/ ]([A-Za-zÁÉÍÓÚÑáéíóúñ]{3,})\.?$',
  ).firstMatch(input.trim());

  static RegExpMatch? _shortDatePrefixMatch(String input) => RegExp(
    r'^(\d{1,2})[-/ ]([A-Za-zÁÉÍÓÚÑáéíóúñ]{3,})\.?(?:\s|$)',
  ).firstMatch(input.trim());

  static DateTime? _shortDate(String input, DateTime statementEnd) {
    final match = _shortDateMatch(input);
    if (match == null) return null;
    const months = <String, int>{
      'ene': 1,
      'feb': 2,
      'mar': 3,
      'abr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'ago': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dic': 12,
    };
    final day = int.tryParse(match.group(1)!);
    final monthName = TransactionImportRules.normalize(match.group(2)!);
    final month = months[monthName.substring(0, 3)];
    if (day == null || month == null) return null;
    final year =
        month > statementEnd.month ? statementEnd.year - 1 : statementEnd.year;
    final date = DateTime(year, month, day);
    return date.month == month && date.day == day ? date : null;
  }

  static bool _isStandaloneMoney(String input) =>
      RegExp(
        r'^[-$€£\s]*\d[\d.,]*\d(?:\s*[A-Z]{3})?$',
        caseSensitive: false,
      ).hasMatch(input.trim()) &&
      (input.contains('.') || input.contains(','));

  static bool _isRepeatedPdfHeader(String input) {
    final value = TransactionImportRules.normalize(input);
    return const {
      'fecha',
      'ofic.',
      'ofic',
      'n.doc.',
      'n.doc',
      'descripcion',
      'debito',
      'credito',
      'saldo',
      'detalle de movimientos',
    }.contains(value);
  }

  static DateTime? _dateValue(Object? value) {
    if (value is DateTime) return value;
    return TransactionImportRules.parseDate(_stringValue(value));
  }

  static int? _minorValue(Object? value) {
    if (value == null) return null;
    if (value is num) return (value * 100).round();
    return TransactionImportRules.parseSignedMinor(_stringValue(value));
  }

  static Object? _excelValue(CellValue? value) => switch (value) {
    null => null,
    IntCellValue() => value.value,
    DoubleCellValue() => value.value,
    DateCellValue() => value.asDateTimeLocal(),
    DateTimeCellValue() => value.asDateTimeLocal(),
    BoolCellValue() => value.value,
    _ => value.toString(),
  };

  static String _stringValue(Object? value) => switch (value) {
    null => '',
    DateTime() => value.toIso8601String().split('T').first,
    num() => value.toString(),
    _ => value.toString().trim(),
  };

  static String _detectBank(
    String fileName,
    _StatementSheet sheet,
    _HeaderMatch header,
  ) {
    final headerText = sheet.rows[header.rowIndex]
        .map((value) => TransactionImportRules.normalize(_stringValue(value)))
        .join(' ');
    final allText = TransactionImportRules.normalize(
      '${sheet.name} ${sheet.rows.take(header.rowIndex + 1).expand((row) => row).map(_stringValue).join(' ')}',
    );
    if (headerText.contains('beneficiario') ||
        headerText.contains('saldo efectivo') ||
        allText.contains('resumen del periodo')) {
      return 'Banco Guayaquil';
    }
    if (headerText.contains('ofic') ||
        headerText.contains('n.doc') ||
        allText.contains('depositos/creditos')) {
      return 'Banco Pichincha';
    }
    return _bankFromName(fileName);
  }

  static String _bankFromName(String fileName) {
    final value = TransactionImportRules.normalize(fileName);
    if (value.contains('pichincha')) return 'Banco Pichincha';
    if (value.contains('guayaquil')) return 'Banco Guayaquil';
    return 'Extracto bancario compatible';
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }
}

class _StatementSheet {
  const _StatementSheet({required this.name, required this.rows});

  final String name;
  final List<List<Object?>> rows;
}

class _HomeWalletPdfDraft {
  const _HomeWalletPdfDraft({
    required this.occurredAt,
    required this.type,
    required this.category,
    required this.description,
    required this.amountMinor,
  });

  final DateTime occurredAt;
  final TransactionType type;
  final String category;
  final String description;
  final int? amountMinor;
}

class _HomeWalletRowText {
  const _HomeWalletRowText({required this.category, required this.description});

  final String category;
  final String description;
}

class _HeaderMatch {
  const _HeaderMatch({
    required this.rowIndex,
    required this.date,
    required this.description,
    required this.amount,
    required this.debit,
    required this.credit,
    required this.type,
    required this.category,
    required this.beneficiary,
  });

  final int rowIndex;
  final int date;
  final int description;
  final int? amount;
  final int? debit;
  final int? credit;
  final int? type;
  final int? category;
  final int? beneficiary;
}
