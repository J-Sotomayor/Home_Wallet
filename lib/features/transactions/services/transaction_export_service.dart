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

  Uint8List exportExcel(
    List<FinanceTransaction> transactions, {
    Map<String, String> memberNames = const {},
    bool analysisOnly = false,
    String reportTitle = 'Estado de movimientos',
  }) {
    final sorted = _sorted(transactions, memberNames: memberNames);
    final totals = _totals(sorted);
    final period = _period(sorted);
    final excel = Excel.createExcel();
    final sheetName = analysisOnly ? 'Análisis' : 'Movimientos';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

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

    _mergeAndWrite(
      sheet,
      'A1',
      'F1',
      'HOMEWALLET · ${reportTitle.toUpperCase()}',
    );
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

    if (analysisOnly) {
      final categoryTotals = _expenseTotals(sorted);
      final advice = _financialAdvice(totals, categoryTotals);
      _mergeAndWrite(sheet, 'A8', 'F8', 'ANÁLISIS DE GASTOS POR CATEGORÍA');
      _styleRange(sheet, 7, 0, 7, 5, sectionStyle);
      const analysisHeaders = [
        'Categoría',
        'Monto',
        'Participación',
        'Gráfico',
        '',
        '',
      ];
      for (var column = 0; column < analysisHeaders.length; column++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 8),
          TextCellValue(analysisHeaders[column]),
          cellStyle: headerStyle,
        );
      }
      var row = 9;
      final ranked =
          categoryTotals.entries.toList()
            ..sort((left, right) => right.value.compareTo(left.value));
      for (final entry in ranked.take(10)) {
        final ratio = totals.expense == 0 ? 0.0 : entry.value / totals.expense;
        final blocks = (ratio * 20).round().clamp(1, 20);
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          TextCellValue(entry.key),
        );
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
          DoubleCellValue(entry.value / 100),
          cellStyle: CellStyle(numberFormat: currency),
        );
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row),
          TextCellValue('${(ratio * 100).toStringAsFixed(1)}%'),
        );
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
          customValue: TextCellValue(List.filled(blocks, '█').join()),
        );
        _styleRange(
          sheet,
          row,
          3,
          row,
          5,
          CellStyle(fontColorHex: blue, bold: true),
        );
        row++;
      }
      if (ranked.isEmpty) {
        _mergeAndWrite(
          sheet,
          'A10',
          'F10',
          'No hay gastos para analizar en este período.',
        );
        row = 10;
      }
      row += 2;
      _mergeAndWrite(
        sheet,
        'A${row + 1}',
        'F${row + 1}',
        'RECOMENDACIONES DE SALUD FINANCIERA',
      );
      _styleRange(sheet, row, 0, row, 5, sectionStyle);
      row++;
      for (final recommendation in advice) {
        _mergeAndWrite(
          sheet,
          'A${row + 1}',
          'F${row + 1}',
          '• $recommendation',
        );
        _styleRange(sheet, row, 0, row, 5, subtitleStyle);
        sheet.setRowHeight(row, 32);
        row++;
      }
      sheet
        ..setColumnWidth(0, 26)
        ..setColumnWidth(1, 17)
        ..setColumnWidth(2, 16)
        ..setColumnWidth(3, 14)
        ..setColumnWidth(4, 14)
        ..setColumnWidth(5, 14);
      final encoded = excel.encode();
      if (encoded == null) {
        throw StateError('No se pudo generar el análisis Excel.');
      }
      return Uint8List.fromList(encoded);
    }

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

    var row = 9;
    String? previousMember;
    for (var index = 0; index < sorted.length; index++) {
      final transaction = sorted[index];
      if (memberNames.isNotEmpty && transaction.createdBy != previousMember) {
        final memberName = memberNames[transaction.createdBy] ?? 'Integrante';
        _mergeAndWrite(
          sheet,
          'A${row + 1}',
          'F${row + 1}',
          'INTEGRANTE · $memberName',
        );
        _styleRange(
          sheet,
          row,
          0,
          row,
          5,
          subtitleStyle.copyWith(boldVal: true),
        );
        sheet.setRowHeight(row, 23);
        row++;
        previousMember = transaction.createdBy;
      }
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
      row++;
    }

    final totalRow = row + 1;
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

  Future<Uint8List> exportPdf(
    List<FinanceTransaction> transactions, {
    Map<String, String> memberNames = const {},
    bool analysisOnly = false,
    String reportTitle = 'Estado de movimientos',
  }) async {
    final sorted = _sorted(transactions, memberNames: memberNames);
    final totals = _totals(sorted);
    final period = _period(sorted);
    final blue = PdfColor.fromHex('#8FC9C2');
    final dark = PdfColor.fromHex('#292B2E');
    final paleBlue = PdfColor.fromHex('#DDEFEA');
    final paleGray = PdfColor.fromHex('#FAFAF8');
    final gray = PdfColor.fromHex('#E8E6E2');
    final green = PdfColor.fromHex('#3F706B');
    final red = PdfColor.fromHex('#9B5049');
    final regularData = await rootBundle.load(
      'assets/fonts/Roboto-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final regularFont = pw.Font.ttf(regularData);
    final boldFont = pw.Font.ttf(boldData);
    final document = pw.Document(
      title: '$reportTitle · HomeWallet',
      author: 'HomeWallet',
      creator: 'HomeWallet',
      subject:
          analysisOnly
              ? 'Análisis de salud financiera'
              : 'Movimientos del espacio financiero',
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
                      reportTitle.toUpperCase(),
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
              pw.SizedBox(height: 12),
              _pdfFinancialHealth(
                totals: totals,
                dark: dark,
                green: green,
                red: red,
                blue: blue,
                background: paleBlue,
              ),
              pw.SizedBox(height: 12),
              _pdfExpenseAnalysis(
                transactions: sorted,
                totals: totals,
                dark: dark,
                blue: blue,
                red: red,
                green: green,
                background: paleBlue,
              ),
              if (!analysisOnly) ...[
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
                ..._pdfTransactionSections(
                  sorted,
                  memberNames: memberNames,
                  dark: dark,
                  blue: blue,
                  gray: gray,
                  paleGray: paleGray,
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
            ],
      ),
    );
    return document.save();
  }

  static pw.Widget _pdfFinancialHealth({
    required _ExportTotals totals,
    required PdfColor dark,
    required PdfColor green,
    required PdfColor red,
    required PdfColor blue,
    required PdfColor background,
  }) {
    final income = totals.income;
    final expenseRatio = income <= 0 ? 1.0 : totals.expense / income;
    final savingRatio = income <= 0 ? 0.0 : totals.saving / income;
    final status =
        income <= 0
            ? 'Sin ingresos suficientes para evaluar'
            : expenseRatio > 1
            ? 'Atención: los gastos superan los ingresos'
            : expenseRatio > .8
            ? 'Salud financiera ajustada'
            : savingRatio >= .1
            ? 'Salud financiera favorable'
            : 'Flujo estable; conviene reforzar el ahorro';
    pw.Widget bar(String label, double ratio, PdfColor color) {
      final active = (ratio.clamp(0, 1) * 100).round();
      final remaining = 100 - active;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 5),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 58,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
            ),
            pw.Expanded(
              child: pw.Container(
                height: 8,
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  children: [
                    if (active > 0)
                      pw.Expanded(
                        flex: active,
                        child: pw.Container(color: color),
                      ),
                    if (remaining > 0)
                      pw.Expanded(
                        flex: remaining,
                        child: pw.Container(color: PdfColors.grey300),
                      ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 7),
            pw.SizedBox(
              width: 30,
              child: pw.Text(
                '${(ratio * 100).round()}%',
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 7),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SALUD FINANCIERA · $status',
            style: pw.TextStyle(
              color: dark,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          bar('Gastos/ingresos', expenseRatio, expenseRatio > 1 ? red : green),
          bar('Ahorro/ingresos', savingRatio, blue),
        ],
      ),
    );
  }

  static pw.Widget _pdfExpenseAnalysis({
    required List<FinanceTransaction> transactions,
    required _ExportTotals totals,
    required PdfColor dark,
    required PdfColor blue,
    required PdfColor red,
    required PdfColor green,
    required PdfColor background,
  }) {
    final categories = _expenseTotals(transactions);
    final ranked =
        categories.entries.toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    final advice = _financialAdvice(totals, categories);
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '¿EN QUÉ SE FUE EL DINERO?',
            style: pw.TextStyle(
              color: dark,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 7),
          if (ranked.isEmpty)
            pw.Text(
              'No hay gastos para analizar en este período.',
              style: pw.TextStyle(color: dark, fontSize: 8),
            )
          else
            ...ranked.take(7).map((entry) {
              final ratio =
                  totals.expense == 0 ? 0.0 : entry.value / totals.expense;
              final active = (ratio.clamp(0, 1) * 100).round();
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            entry.key,
                            style: pw.TextStyle(color: dark, fontSize: 8),
                          ),
                        ),
                        pw.Text(
                          '${(ratio * 100).toStringAsFixed(0)}% · ${_money(entry.value)}',
                          style: pw.TextStyle(
                            color: dark,
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      children: [
                        if (active > 0)
                          pw.Expanded(
                            flex: active,
                            child: pw.Container(height: 7, color: blue),
                          ),
                        if (active < 100)
                          pw.Expanded(
                            flex: 100 - active,
                            child: pw.Container(
                              height: 7,
                              color: PdfColors.grey300,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          pw.SizedBox(height: 5),
          pw.Text(
            'RECOMENDACIONES',
            style: pw.TextStyle(
              color: dark,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          ...advice.map(
            (text) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('• ', style: pw.TextStyle(color: blue, fontSize: 8)),
                  pw.Expanded(
                    child: pw.Text(
                      text,
                      style: pw.TextStyle(
                        color:
                            totals.expense > totals.income &&
                                    text.startsWith('Tus gastos')
                                ? red
                                : dark,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            totals.net >= 0
                ? 'Balance del período favorable: ${_money(totals.net)}.'
                : 'Déficit del período: ${_money(totals.net.abs())}.',
            style: pw.TextStyle(
              color: totals.net >= 0 ? green : red,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _pdfTransactionSections(
    List<FinanceTransaction> transactions, {
    required Map<String, String> memberNames,
    required PdfColor dark,
    required PdfColor blue,
    required PdfColor gray,
    required PdfColor paleGray,
  }) {
    if (memberNames.isEmpty) {
      return [_pdfTransactionTable(transactions, dark, gray, paleGray)];
    }
    final grouped = <String, List<FinanceTransaction>>{};
    for (final transaction in transactions) {
      grouped.putIfAbsent(transaction.createdBy, () => []).add(transaction);
    }
    final widgets = <pw.Widget>[];
    for (final entry in grouped.entries) {
      widgets.add(
        pw.Container(
          width: double.infinity,
          color: PdfColor.fromHex('#EFF6FF'),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: pw.Text(
            'INTEGRANTE · ${memberNames[entry.key] ?? 'Integrante'}',
            style: pw.TextStyle(
              color: blue,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
      widgets.add(_pdfTransactionTable(entry.value, dark, gray, paleGray));
      widgets.add(pw.SizedBox(height: 9));
    }
    return widgets;
  }

  static pw.Widget _pdfTransactionTable(
    List<FinanceTransaction> transactions,
    PdfColor dark,
    PdfColor gray,
    PdfColor paleGray,
  ) => pw.TableHelper.fromTextArray(
    headers: const [
      'FECHA',
      'TIPO',
      'CATEGORÍA',
      'DESCRIPCIÓN',
      'DÉBITO',
      'CRÉDITO',
    ],
    data:
        transactions
            .map(
              (transaction) => [
                DateFormat('dd/MM/yyyy').format(transaction.occurredAt),
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
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
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
  );

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
    List<FinanceTransaction> transactions, {
    Map<String, String> memberNames = const {},
  }) {
    final memberOrder = <String, int>{};
    var index = 0;
    for (final uid in memberNames.keys) {
      memberOrder[uid] = index++;
    }
    return [...transactions]..sort((left, right) {
      if (memberNames.isNotEmpty) {
        final byMember = (memberOrder[left.createdBy] ?? 9999).compareTo(
          memberOrder[right.createdBy] ?? 9999,
        );
        if (byMember != 0) return byMember;
      }
      return left.occurredAt.compareTo(right.occurredAt);
    });
  }

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

  static Map<String, int> _expenseTotals(
    Iterable<FinanceTransaction> transactions,
  ) {
    final result = <String, int>{};
    for (final transaction in transactions.where(
      (item) => item.type == TransactionType.expense,
    )) {
      result.update(
        transaction.category,
        (value) => value + transaction.amountMinor,
        ifAbsent: () => transaction.amountMinor,
      );
    }
    return result;
  }

  static List<String> _financialAdvice(
    _ExportTotals totals,
    Map<String, int> categoryTotals,
  ) {
    final ranked =
        categoryTotals.entries.toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    final advice = <String>[];
    if (totals.income <= 0) {
      advice.add(
        'No hay ingresos en el período; confirma que el estado de cuenta esté completo antes de tomar decisiones.',
      );
    } else if (totals.expense > totals.income) {
      advice.add(
        'Tus gastos superan tus ingresos. Prioriza pagos esenciales y define un límite semanal para gastos variables.',
      );
    } else if (totals.expense * 100 >= totals.income * 80) {
      advice.add(
        'Usaste al menos el 80% de tus ingresos. Intenta reservar primero entre 10% y 20% para ahorro o emergencias.',
      );
    } else {
      advice.add(
        'El flujo del período es positivo. Separa una parte del excedente para ahorro y metas antes de aumentar gastos.',
      );
    }
    if (ranked.isNotEmpty) {
      final top = ranked.first;
      final share = totals.expense == 0 ? 0 : top.value / totals.expense * 100;
      advice.add(
        '${top.key} concentra ${share.toStringAsFixed(0)}% de tus gastos. Revísala primero para encontrar oportunidades de ajuste.',
      );
    }
    final other =
        (categoryTotals['Otro'] ?? 0) + (categoryTotals['Otros'] ?? 0);
    if (other > 0) {
      advice.add(
        'Clasifica los consumos marcados como “Otros”; una categoría precisa hace que las recomendaciones sean más útiles.',
      );
    }
    advice.add(
      'Compara este análisis con el siguiente período para detectar tendencias, cobros repetidos y aumentos inusuales.',
    );
    return advice;
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
