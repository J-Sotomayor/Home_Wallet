import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/finance_models.dart';

enum TransactionExportScope { homeWallet, imported, all }

List<FinanceTransaction> transactionsForExport(
  Iterable<FinanceTransaction> transactions,
  TransactionExportScope scope,
) => switch (scope) {
  TransactionExportScope.homeWallet =>
    transactions
        .where((item) => item.origin == TransactionOrigin.manual)
        .toList(),
  TransactionExportScope.imported =>
    transactions
        .where((item) => item.origin == TransactionOrigin.imported)
        .toList(),
  TransactionExportScope.all => transactions.toList(),
};

class TransactionExportService {
  const TransactionExportService();

  Uint8List exportExcel(List<FinanceTransaction> transactions) {
    final sorted = _sorted(transactions);
    final totals = _totals(sorted);
    final period = _period(sorted);
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Movimientos');
    final sheet = excel['Movimientos'];

    final blue = ExcelColor.fromHexString('FF2563EB');
    final dark = ExcelColor.fromHexString('FF111827');
    final paleBlue = ExcelColor.fromHexString('FFEFF6FF');
    final paleGray = ExcelColor.fromHexString('FFF8FAFC');
    final gray = ExcelColor.fromHexString('FFE5E7EB');
    final green = ExcelColor.fromHexString('FF15803D');
    final red = ExcelColor.fromHexString('FFB91C1C');
    final white = ExcelColor.white;
    final thinGray = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: gray,
    );
    final currency = NumFormat.custom(
      formatCode: r'$#,##0.00;[Red]($#,##0.00);-',
    );
    final dateFormat = NumFormat.custom(formatCode: 'dd/mm/yyyy');

    final titleStyle = CellStyle(
      backgroundColorHex: blue,
      fontColorHex: white,
      fontSize: 20,
      bold: true,
      verticalAlign: VerticalAlign.Center,
    );
    final subtitleStyle = CellStyle(
      backgroundColorHex: paleBlue,
      fontColorHex: dark,
      fontSize: 11,
      verticalAlign: VerticalAlign.Center,
    );
    final summaryLabelStyle = CellStyle(
      backgroundColorHex: dark,
      fontColorHex: white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final summaryValueStyle = CellStyle(
      backgroundColorHex: paleBlue,
      fontColorHex: dark,
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      numberFormat: currency,
    );
    final sectionStyle = CellStyle(
      backgroundColorHex: blue,
      fontColorHex: white,
      bold: true,
      fontSize: 12,
      verticalAlign: VerticalAlign.Center,
    );
    final headerStyle = CellStyle(
      backgroundColorHex: dark,
      fontColorHex: white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      leftBorder: thinGray,
      rightBorder: thinGray,
      topBorder: thinGray,
      bottomBorder: thinGray,
    );

    _mergeAndWrite(sheet, 'A1', 'F1', 'HOMEWALLET · ESTADO DE MOVIMIENTOS');
    _styleRange(sheet, 0, 0, 0, 5, titleStyle);
    sheet.setRowHeight(0, 34);
    _mergeAndWrite(
      sheet,
      'A2',
      'F2',
      'Periodo: $period  •  Generado ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
    );
    _styleRange(sheet, 1, 0, 1, 5, subtitleStyle);
    sheet.setRowHeight(1, 24);

    const summaryLabels = ['Ingresos', 'Gastos', 'Ahorros'];
    final summaryValues = [totals.income, totals.expense, totals.saving];
    for (var index = 0; index < 3; index++) {
      final startColumn = index * 2;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: startColumn, rowIndex: 3),
        CellIndex.indexByColumnRow(columnIndex: startColumn + 1, rowIndex: 3),
        customValue: TextCellValue(summaryLabels[index]),
      );
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: startColumn, rowIndex: 4),
        CellIndex.indexByColumnRow(columnIndex: startColumn + 1, rowIndex: 4),
        customValue: DoubleCellValue(summaryValues[index] / 100),
      );
      _styleRange(sheet, 3, startColumn, 3, startColumn + 1, summaryLabelStyle);
      _styleRange(sheet, 4, startColumn, 4, startColumn + 1, summaryValueStyle);
    }
    sheet.setRowHeight(3, 23);
    sheet.setRowHeight(4, 29);

    _mergeAndWrite(
      sheet,
      'A6',
      'F6',
      'Balance neto del periodo: ${_money(totals.net)}',
    );
    final netStyle = summaryLabelStyle.copyWith(
      backgroundColorHexVal: totals.net >= 0 ? green : red,
      fontSizeVal: 12,
    );
    _styleRange(sheet, 5, 0, 5, 5, netStyle);
    sheet.setRowHeight(5, 25);

    _mergeAndWrite(sheet, 'A8', 'F8', 'DETALLE DE MOVIMIENTOS');
    _styleRange(sheet, 7, 0, 7, 5, sectionStyle);
    sheet.setRowHeight(7, 25);

    const headers = [
      'Fecha',
      'Tipo',
      'Categoría',
      'Descripción',
      'Débito',
      'Crédito',
    ];
    for (var column = 0; column < headers.length; column++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 8),
        TextCellValue(headers[column]),
        cellStyle: headerStyle,
      );
    }
    sheet.setRowHeight(8, 26);

    for (var index = 0; index < sorted.length; index++) {
      final transaction = sorted[index];
      final row = index + 9;
      final baseStyle = CellStyle(
        backgroundColorHex: index.isOdd ? paleGray : white,
        fontColorHex: dark,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: thinGray,
        rightBorder: thinGray,
        topBorder: thinGray,
        bottomBorder: thinGray,
      );
      final amountStyle = baseStyle.copyWith(
        horizontalAlignVal: HorizontalAlign.Right,
        fontColorHexVal:
            transaction.type == TransactionType.income ? green : red,
        numberFormat: currency,
      );
      final values = <CellValue?>[
        DateCellValue.fromDateTime(transaction.occurredAt),
        TextCellValue(_typeLabel(transaction.type)),
        TextCellValue(transaction.category),
        TextCellValue(transaction.description),
        transaction.type == TransactionType.income
            ? null
            : DoubleCellValue(transaction.amountMinor / 100),
        transaction.type == TransactionType.income
            ? DoubleCellValue(transaction.amountMinor / 100)
            : null,
      ];
      for (var column = 0; column < values.length; column++) {
        final style =
            column == 0
                ? baseStyle.copyWith(
                  horizontalAlignVal: HorizontalAlign.Center,
                  numberFormat: dateFormat,
                )
                : column >= 4
                ? amountStyle
                : baseStyle;
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
          values[column],
          cellStyle: style,
        );
      }
      sheet.setRowHeight(row, 24);
    }

    final totalRow = sorted.length + 10;
    _mergeAndWrite(sheet, 'A${totalRow + 1}', 'D${totalRow + 1}', 'TOTALES');
    _styleRange(sheet, totalRow, 0, totalRow, 3, headerStyle);
    final debitTotal = totals.expense + totals.saving;
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: totalRow),
      DoubleCellValue(debitTotal / 100),
      cellStyle: headerStyle.copyWith(numberFormat: currency),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow),
      DoubleCellValue(totals.income / 100),
      cellStyle: headerStyle.copyWith(numberFormat: currency),
    );

    sheet
      ..setColumnWidth(0, 14)
      ..setColumnWidth(1, 14)
      ..setColumnWidth(2, 22)
      ..setColumnWidth(3, 48)
      ..setColumnWidth(4, 16)
      ..setColumnWidth(5, 16);

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('No se pudo generar el archivo Excel.');
    }
    return Uint8List.fromList(encoded);
  }

  Future<Uint8List> exportPdf(List<FinanceTransaction> transactions) async {
    final sorted = _sorted(transactions);
    final totals = _totals(sorted);
    final period = _period(sorted);
    final blue = PdfColor.fromHex('#2563EB');
    final dark = PdfColor.fromHex('#111827');
    final paleBlue = PdfColor.fromHex('#EFF6FF');
    final paleGray = PdfColor.fromHex('#F8FAFC');
    final gray = PdfColor.fromHex('#D1D5DB');
    final green = PdfColor.fromHex('#15803D');
    final red = PdfColor.fromHex('#B91C1C');
    final regularData = await rootBundle.load(
      'assets/fonts/Roboto-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final regularFont = pw.Font.ttf(regularData);
    final boldFont = pw.Font.ttf(boldData);
    final document = pw.Document(
      title: 'Estado de movimientos HomeWallet',
      author: 'HomeWallet',
      creator: 'HomeWallet',
      subject: 'Movimientos financieros del hogar',
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 30),
        maxPages: 60,
        header:
            (context) => pw.Column(
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 30,
                      height: 30,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: blue,
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: pw.Text(
                        'H',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 9),
                    pw.Text(
                      'HOMEWALLET',
                      style: pw.TextStyle(
                        color: dark,
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      'ESTADO DE MOVIMIENTOS',
                      style: pw.TextStyle(color: dark, fontSize: 13),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Divider(color: blue, thickness: 2),
              ],
            ),
        footer:
            (context) => pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Divider(color: gray, thickness: .5),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Generado por HomeWallet. Tus datos permanecen bajo tu control.',
                        style: pw.TextStyle(
                          color: PdfColors.grey700,
                          fontSize: 7,
                        ),
                      ),
                    ),
                    pw.Text(
                      'Página ${context.pageNumber} de ${context.pagesCount}',
                      style: pw.TextStyle(
                        color: PdfColors.grey700,
                        fontSize: 7,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        build:
            (context) => [
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: paleBlue,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Resumen del periodo',
                            style: pw.TextStyle(
                              color: blue,
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            period,
                            style: pw.TextStyle(color: dark, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    pw.Text(
                      '${sorted.length} movimientos',
                      style: pw.TextStyle(
                        color: dark,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  _pdfSummaryCard('Ingresos', totals.income, green, paleBlue),
                  pw.SizedBox(width: 8),
                  _pdfSummaryCard('Gastos', totals.expense, red, paleBlue),
                  pw.SizedBox(width: 8),
                  _pdfSummaryCard('Ahorros', totals.saving, blue, paleBlue),
                  pw.SizedBox(width: 8),
                  _pdfSummaryCard(
                    'Balance neto',
                    totals.net,
                    totals.net >= 0 ? green : red,
                    paleBlue,
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 7,
                  horizontal: 9,
                ),
                color: blue,
                child: pw.Text(
                  'DETALLE DE MOVIMIENTOS',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.TableHelper.fromTextArray(
                headers: const [
                  'FECHA',
                  'TIPO',
                  'CATEGORÍA',
                  'DESCRIPCIÓN',
                  'DÉBITO',
                  'CRÉDITO',
                ],
                data:
                    sorted
                        .map(
                          (transaction) => [
                            DateFormat(
                              'dd/MM/yyyy',
                            ).format(transaction.occurredAt),
                            _typeLabel(transaction.type),
                            transaction.category,
                            transaction.description,
                            transaction.type == TransactionType.income
                                ? ''
                                : _money(transaction.amountMinor),
                            transaction.type == TransactionType.income
                                ? _money(transaction.amountMinor)
                                : '',
                          ],
                        )
                        .toList(),
                headerDecoration: pw.BoxDecoration(color: dark),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: pw.TextStyle(color: dark, fontSize: 7),
                oddCellStyle: pw.TextStyle(color: dark, fontSize: 7),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 5,
                ),
                cellAlignments: const {
                  0: pw.Alignment.center,
                  1: pw.Alignment.center,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.2),
                  1: pw.FlexColumnWidth(1.0),
                  2: pw.FlexColumnWidth(1.5),
                  3: pw.FlexColumnWidth(3.2),
                  4: pw.FlexColumnWidth(1.2),
                  5: pw.FlexColumnWidth(1.2),
                },
                border: pw.TableBorder(
                  bottom: pw.BorderSide(color: gray, width: .5),
                  horizontalInside: pw.BorderSide(color: gray, width: .35),
                ),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration: pw.BoxDecoration(color: paleGray),
              ),
              pw.SizedBox(height: 10),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: pw.BoxDecoration(
                    color: dark,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text(
                    'Total débitos: ${_money(totals.expense + totals.saving)}    Total créditos: ${_money(totals.income)}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
      ),
    );
    return document.save();
  }

  static pw.Widget _pdfSummaryCard(
    String label,
    int value,
    PdfColor color,
    PdfColor background,
  ) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(color: PdfColors.grey700, fontSize: 7),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            _money(value),
            style: pw.TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );

  static void _mergeAndWrite(
    Sheet sheet,
    String start,
    String end,
    String value,
  ) => sheet.merge(
    CellIndex.indexByString(start),
    CellIndex.indexByString(end),
    customValue: TextCellValue(value),
  );

  static void _styleRange(
    Sheet sheet,
    int startRow,
    int startColumn,
    int endRow,
    int endColumn,
    CellStyle style,
  ) {
    for (var row = startRow; row <= endRow; row++) {
      for (var column = startColumn; column <= endColumn; column++) {
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
            )
            .cellStyle = style;
      }
    }
  }

  static List<FinanceTransaction> _sorted(
    List<FinanceTransaction> transactions,
  ) =>
      [...transactions]
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));

  static _ExportTotals _totals(List<FinanceTransaction> transactions) {
    int sum(TransactionType type) => transactions
        .where((transaction) => transaction.type == type)
        .fold(0, (total, transaction) => total + transaction.amountMinor);
    return _ExportTotals(
      income: sum(TransactionType.income),
      expense: sum(TransactionType.expense),
      saving: sum(TransactionType.saving),
    );
  }

  static String _period(List<FinanceTransaction> transactions) {
    if (transactions.isEmpty) return 'Sin movimientos';
    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(transactions.first.occurredAt)} al ${formatter.format(transactions.last.occurredAt)}';
  }

  static String _typeLabel(TransactionType type) => switch (type) {
    TransactionType.income => 'Ingreso',
    TransactionType.expense => 'Gasto',
    TransactionType.saving => 'Ahorro',
  };

  static String _money(int minor) {
    final formatter = NumberFormat('#,##0.00', 'es_EC');
    final sign = minor < 0 ? '-' : '';
    return '$sign\$${formatter.format(minor.abs() / 100)}';
  }
}

class _ExportTotals {
  const _ExportTotals({
    required this.income,
    required this.expense,
    required this.saving,
  });

  final int income;
  final int expense;
  final int saving;

  int get net => income - expense - saving;
}
