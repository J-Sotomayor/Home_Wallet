import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services/app_services.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/finance_models.dart';
import '../services/bank_statement_service.dart';
import '../services/transaction_csv_service.dart';
import '../services/transaction_export_service.dart';

class DataToolsScreen extends StatefulWidget {
  const DataToolsScreen({
    super.key,
    required this.user,
    required this.householdId,
    required this.services,
    this.canImport = true,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final bool canImport;

  @override
  State<DataToolsScreen> createState() => _DataToolsScreenState();
}

class _DataToolsScreenState extends State<DataToolsScreen> {
  static const _csv = TransactionCsvService();
  static const _statements = BankStatementService();
  static const _exports = TransactionExportService();
  bool _busy = false;
  double? _progress;
  String? _status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar y exportar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Text(
              'Tus datos, bajo tu control',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Importa estados de cuenta de Pichincha, Guayaquil y archivos bancarios compatibles. También puedes descargar un reporte profesional.',
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.account_balance_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      'Importar estado de cuenta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Acepta CSV, XLS, XLSX y PDF digital. Reconoce cada formato, comprueba los totales declarados y usa la categoría del banco cuando existe; si está vacía, la asigna automáticamente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          _busy || !widget.canImport ? null : _importStatement,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Seleccionar Excel, PDF o CSV'),
                    ),
                    if (!widget.canImport) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Tu rol permite exportar y consultar, pero no importar movimientos.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 17),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'El archivo se procesa en tu dispositivo.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.download_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      'Exportar movimientos',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Genera un estado de movimientos con periodo, resumen de ingresos, gastos, ahorros, categorías y detalle completo.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _exportExcel,
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Guardar reporte Excel'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Guardar estado en PDF'),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _busy ? null : _exportCsv,
                      icon: const Icon(Icons.data_object_outlined, size: 19),
                      label: const Text('Guardar también como CSV'),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy || _status != null) ...[
              const SizedBox(height: 20),
              if (_busy)
                LinearProgressIndicator(value: _progress)
              else
                const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(height: 10),
              Text(
                _status ?? 'Procesando…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 22),
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Formatos bancarios'),
                subtitle: Text(
                  'Pichincha y Guayaquil envían estructuras diferentes. HomeWallet las detecta sin solicitar ni almacenar tus credenciales bancarias.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importStatement() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Selecciona el estado de cuenta',
        // Android's document picker can hide valid files when unrelated MIME
        // families (Excel and PDF) are combined in one custom filter. Keep the
        // picker broad and enforce the supported extensions in the parser.
        type: FileType.any,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('No se pudo leer el archivo seleccionado.');
      }

      if (mounted) {
        setState(() {
          _busy = true;
          _progress = null;
          _status = 'Leyendo y validando ${file.name}…';
        });
      }
      final imported = await _statements.importFile(
        fileName: file.name,
        bytes: bytes,
        path: file.path,
      );
      if (imported.items.length > 500) {
        throw const FormatException(
          'El archivo supera 500 movimientos. Divídelo en varios periodos.',
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _ImportPreviewDialog(result: imported),
      );
      if (confirmed != true || !mounted) return;

      setState(() {
        _busy = true;
        _progress = null;
        _status = 'Cifrando y guardando ${imported.items.length} movimientos…';
      });
      await widget.services.finance.addTransactions(
        householdId: widget.householdId,
        uid: widget.user.uid,
        transactions:
            imported.items
                .map(
                  (item) => FinanceTransactionDraft(
                    description: item.description,
                    category: item.category,
                    amountMinor: item.amountMinor,
                    occurredAt: item.occurredAt,
                    type: item.type,
                    shared: true,
                    origin: TransactionOrigin.imported,
                    sourceName:
                        '${imported.bankName} · ${imported.formatLabel}',
                    sourceVerified: imported.totalsVerified,
                  ),
                )
                .toList(),
      );
      if (mounted) {
        setState(
          () =>
              _status =
                  '${imported.items.length} movimientos de ${imported.bankName} importados, clasificados y cifrados.',
        );
      }
    } on FormatException catch (error) {
      _showError(error.message);
    } on AppException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('No se pudo completar la importación. Revisa el archivo.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _exportExcel() async {
    await _export(
      extension: 'xlsx',
      preparingMessage: 'Preparando el reporte Excel…',
      createBytes: (transactions) async => _exports.exportExcel(transactions),
    );
  }

  Future<void> _exportPdf() async {
    await _export(
      extension: 'pdf',
      preparingMessage: 'Diseñando el estado de movimientos PDF…',
      createBytes: _exports.exportPdf,
    );
  }

  Future<void> _exportCsv() async {
    await _export(
      extension: 'csv',
      preparingMessage: 'Preparando el archivo CSV…',
      createBytes: (transactions) async => _csv.exportBytes(transactions),
    );
  }

  Future<void> _export({
    required String extension,
    required String preparingMessage,
    required Future<Uint8List> Function(List<FinanceTransaction>) createBytes,
  }) async {
    setState(() {
      _busy = true;
      _progress = null;
      _status = preparingMessage;
    });
    try {
      final transactions =
          await widget.services.finance
              .watchTransactions(widget.householdId)
              .first;
      if (transactions.isEmpty) {
        throw const AppException('Todavía no hay movimientos para exportar.');
      }
      final bytes = await createBytes(transactions);
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final path = await FilePicker.saveFile(
        dialogTitle: 'Guardar reporte de HomeWallet',
        fileName: 'homewallet_estado_$date.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (mounted) {
        setState(() {
          _status =
              path == null
                  ? 'Exportación finalizada.'
                  : 'Reporte ${extension.toUpperCase()} guardado correctamente.';
        });
      }
    } on AppException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('No se pudo generar el reporte ${extension.toUpperCase()}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _status = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({required this.result});

  final BankStatementImportResult result;

  @override
  Widget build(BuildContext context) {
    final categories = <String, int>{};
    for (final item in result.items) {
      categories.update(item.category, (count) => count + 1, ifAbsent: () => 1);
    }
    final mostUsed =
        categories.entries.toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    return AlertDialog(
      title: const Text('Estado de cuenta válido'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.bankName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(result.formatLabel)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.totalsVerified
                      ? Icons.verified_outlined
                      : Icons.fact_check_outlined,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.totalsVerified
                        ? 'Los movimientos cuadran con los totales declarados por el banco.'
                        : 'La estructura y los movimientos son válidos. Este archivo no declara totales para conciliarlos.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('${result.items.length} movimientos encontrados.'),
            const SizedBox(height: 12),
            _PreviewTotal(
              label: 'Ingresos',
              value: result.totalFor(TransactionType.income),
            ),
            _PreviewTotal(
              label: 'Gastos',
              value: result.totalFor(TransactionType.expense),
            ),
            _PreviewTotal(
              label: 'Ahorros',
              value: result.totalFor(TransactionType.saving),
            ),
            const SizedBox(height: 14),
            Text(
              'Clasificación',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children:
                  mostUsed
                      .take(5)
                      .map(
                        (entry) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${entry.key} · ${entry.value}'),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 12),
            const Text(
              'La importación no elimina movimientos existentes. Todos los datos se cifran antes de guardarse.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Importar'),
        ),
      ],
    );
  }
}

class _PreviewTotal extends StatelessWidget {
  const _PreviewTotal({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          NumberFormat.currency(
            locale: 'es_EC',
            symbol: r'$',
            decimalDigits: 2,
          ).format(value / 100),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
