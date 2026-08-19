import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/finance_models.dart';
import '../services/bank_statement_service.dart';
import '../services/transaction_csv_service.dart';
import '../services/transaction_import_identity.dart';

class DataToolsScreen extends StatefulWidget {
  const DataToolsScreen({
    super.key,
    required this.user,
    required this.householdId,
    required this.services,
    this.canImport = true,
    this.onImportCommitted,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;
  final bool canImport;
  final VoidCallback? onImportCommitted;

  @override
  State<DataToolsScreen> createState() => _DataToolsScreenState();
}

class _DataToolsScreenState extends State<DataToolsScreen> {
  static const _statements = BankStatementService();
  static const _identity = TransactionImportIdentity();
  bool _busy = false;
  double? _progress;
  String? _status;
  BankStatementImportResult? _preview;
  Set<int> _selectedImportIndexes = {};
  Set<int> _duplicateImportIndexes = {};
  Map<int, String> _importHashes = {};
  String? _importBatchHash;
  int? _completedCount;
  String? _completedBankName;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _completedCount != null
              ? 'Importación completada'
              : preview != null
              ? 'Revisar estado de cuenta'
              : 'Importar estado de cuenta',
        ),
      ),
      body: SafeArea(
        child:
            _completedCount != null
                ? _buildCompletion(context)
                : preview != null
                ? _buildPreview(context, preview)
                : _buildPicker(context),
      ),
    );
  }

  Widget _buildPicker(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
    children: [
      Text(
        'Trae tus movimientos del banco',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Revisa el archivo antes de guardarlo. HomeWallet identificará estos movimientos como importados para que puedas separarlos en tus reportes.',
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
                'Acepta CSV, XLS, XLSX, PDF bancario digital y reportes con detalle exportados por HomeWallet. Comprueba los totales declarados y conserva la categoría cuando existe.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || !widget.canImport ? null : _selectStatement,
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
      if (_busy || _status != null) ...[
        const SizedBox(height: 20),
        if (_busy)
          LinearProgressIndicator(value: _progress)
        else
          const Icon(Icons.check_circle_outline, color: AppColors.deepMint),
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
          title: Text('Archivos compatibles'),
          subtitle: Text(
            'Reconoce estados de Banco Pichincha y Banco Guayaquil, además de reportes de movimientos generados por HomeWallet. Todo se procesa sin solicitar credenciales bancarias.',
          ),
        ),
      ),
    ],
  );

  Widget _buildPreview(
    BuildContext context,
    BankStatementImportResult result,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
    children: [
      Text(
        'Revisa antes de guardar',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      const Text(
        'Confirma el banco, los totales y la clasificación. Nada se guardará hasta que confirmes.',
      ),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _ImportPreviewContent(result: result),
        ),
      ),
      if (_duplicateImportIndexes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: Text(
              '${_duplicateImportIndexes.length} movimiento${_duplicateImportIndexes.length == 1 ? '' : 's'} ya importado${_duplicateImportIndexes.length == 1 ? '' : 's'}',
            ),
            subtitle: const Text(
              'HomeWallet los bloqueó para que el saldo y el análisis no se dupliquen.',
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          key: const Key('select_import_movements'),
          leading: const Icon(Icons.checklist_outlined),
          title: Text(
            '${_selectedImportIndexes.length} de ${result.items.length} seleccionados',
          ),
          subtitle: Text(
            _duplicateImportIndexes.isEmpty
                ? 'Puedes elegir exactamente qué movimientos guardar.'
                : '${_duplicateImportIndexes.length} duplicado${_duplicateImportIndexes.length == 1 ? '' : 's'} bloqueado${_duplicateImportIndexes.length == 1 ? '' : 's'}.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => _chooseImportedMovements(result),
        ),
      ),
      if (_busy || _status != null) ...[
        const SizedBox(height: 18),
        if (_busy) LinearProgressIndicator(value: _progress),
        const SizedBox(height: 8),
        Text(_status ?? 'Procesando…', textAlign: TextAlign.center),
      ],
      const SizedBox(height: 18),
      FilledButton.icon(
        key: const Key('confirm_bank_import'),
        onPressed: _busy ? null : _confirmImport,
        icon: const Icon(Icons.lock_outline),
        label: Text('Importar ${_selectedImportIndexes.length} movimientos'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _discardPreview,
        icon: const Icon(Icons.insert_drive_file_outlined),
        label: const Text('Elegir otro archivo'),
      ),
    ],
  );

  Widget _buildCompletion(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 40, 20, 36),
    children: [
      Icon(
        Icons.check_circle,
        size: 76,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 18),
      Text(
        'Tus movimientos ya están disponibles',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
      Text(
        'Se importaron $_completedCount movimientos de $_completedBankName. Ya cuentan en tu saldo, actividad y reportes, y puedes filtrarlos por origen.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const Key('view_imported_transactions'),
        onPressed: () => Navigator.of(context).pop(true),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Ver movimientos importados'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () {
          setState(() {
            _completedCount = null;
            _completedBankName = null;
            _selectedImportIndexes = {};
            _duplicateImportIndexes = {};
            _importHashes = {};
            _importBatchHash = null;
            _status = null;
          });
        },
        child: const Text('Importar otro archivo'),
      ),
    ],
  );

  Future<void> _selectStatement() async {
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
      final batchHash = await _identity.forFile(bytes);

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
      final duplicateScan = await _findDuplicates(
        imported,
        batchHash: batchHash,
      );
      final hashes = duplicateScan.hashes;
      final duplicates = duplicateScan.duplicates;
      if (!mounted) return;
      if (duplicateScan.batchAlreadyImported ||
          duplicates.length == imported.items.length) {
        setState(() {
          _busy = false;
          _status = null;
          _preview = null;
          _selectedImportIndexes = {};
          _duplicateImportIndexes = duplicates;
          _importHashes = hashes;
          _importBatchHash = batchHash;
        });
        await _showAlreadyImportedDialog(imported);
        return;
      }
      setState(() {
        _busy = false;
        _status = null;
        _preview = imported;
        _importHashes = hashes;
        _importBatchHash = batchHash;
        _duplicateImportIndexes = duplicates;
        _selectedImportIndexes = {
          for (var index = 0; index < imported.items.length; index++)
            if (!duplicates.contains(index)) index,
        };
      });
    } on FormatException catch (error) {
      _showError(error.message);
    } on AppException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('No se pudo leer el archivo. Revisa que no esté protegido.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _confirmImport() async {
    final imported = _preview;
    if (imported == null || _busy) return;
    var selectedIndexes = _selectedImportIndexes.toList()..sort();
    if (selectedIndexes.isEmpty) {
      _showError('Selecciona al menos un movimiento que no esté duplicado.');
      return;
    }
    try {
      setState(() {
        _busy = true;
        _progress = null;
        _status = 'Comprobando que la importación no esté repetida…';
      });
      final duplicateScan = await _findDuplicates(
        imported,
        batchHash: _importBatchHash,
      );
      final duplicates = duplicateScan.duplicates;
      selectedIndexes =
          selectedIndexes
              .where((index) => !duplicates.contains(index))
              .toList();
      if (duplicateScan.batchAlreadyImported || selectedIndexes.isEmpty) {
        if (mounted) {
          setState(() {
            _busy = false;
            _status = null;
            _duplicateImportIndexes = duplicates;
            _selectedImportIndexes = {};
          });
          await _showAlreadyImportedDialog(imported);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _importHashes = duplicateScan.hashes;
        _duplicateImportIndexes = duplicates;
        _selectedImportIndexes = selectedIndexes.toSet();
        _status = 'Cifrando y guardando ${selectedIndexes.length} movimientos…';
      });
      await widget.services.finance.addTransactions(
        householdId: widget.householdId,
        uid: widget.user.uid,
        transactions:
            selectedIndexes
                .map((index) => (index, imported.items[index]))
                .map(
                  (entry) => FinanceTransactionDraft(
                    importHash: _importHashes[entry.$1],
                    importBatchHash: _importBatchHash,
                    description: entry.$2.description,
                    category: entry.$2.category,
                    amountMinor: entry.$2.amountMinor,
                    occurredAt: entry.$2.occurredAt,
                    type: entry.$2.type,
                    // Bank movements are regular household cash flow. Marking
                    // them as shared hid them from balances and reports.
                    shared: false,
                    origin: TransactionOrigin.imported,
                    sourceName:
                        '${imported.bankName} · ${imported.formatLabel}',
                    sourceVerified: imported.totalsVerified,
                  ),
                )
                .toList(),
      );
      widget.onImportCommitted?.call();
      if (mounted) {
        setState(() {
          _preview = null;
          _status = null;
          _completedCount = selectedIndexes.length;
          _completedBankName = imported.bankName;
        });
      }
    } on AppException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('No se pudo guardar la importación. Inténtalo nuevamente.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<
    ({Map<int, String> hashes, Set<int> duplicates, bool batchAlreadyImported})
  >
  _findDuplicates(
    BankStatementImportResult imported, {
    String? batchHash,
  }) async {
    final existing =
        await widget.services.finance
            .watchTransactions(widget.householdId)
            .first;
    final existingHashes = <String>{};
    var batchAlreadyImported = false;
    for (final transaction in existing) {
      existingHashes.add(await _identity.forExisting(transaction));
      if (batchHash != null && transaction.importBatchHash == batchHash) {
        batchAlreadyImported = true;
      }
    }
    final hashes = <int, String>{};
    final duplicates = <int>{};
    final seenInFile = <String>{};
    for (var index = 0; index < imported.items.length; index++) {
      final hash = await _identity.forImported(imported.items[index]);
      hashes[index] = hash;
      if (existingHashes.contains(hash) || !seenInFile.add(hash)) {
        duplicates.add(index);
      }
    }
    return (
      hashes: hashes,
      duplicates: duplicates,
      batchAlreadyImported: batchAlreadyImported,
    );
  }

  Future<void> _showAlreadyImportedDialog(
    BankStatementImportResult imported,
  ) async {
    if (!mounted) return;
    final viewImported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            icon: const Icon(Icons.fact_check_outlined),
            title: const Text('Esta importación ya se realizó'),
            content: Text(
              'Los ${imported.items.length} movimientos de ${imported.bankName} ya existen en HomeWallet. No se guardó nada para evitar duplicar tu saldo y tus reportes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Elegir otro archivo'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Ver importados'),
              ),
            ],
          ),
    );
    if (viewImported == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _discardPreview() {
    setState(() {
      _preview = null;
      _selectedImportIndexes = {};
      _duplicateImportIndexes = {};
      _importHashes = {};
      _importBatchHash = null;
      _status = null;
    });
  }

  Future<void> _chooseImportedMovements(
    BankStatementImportResult imported,
  ) async {
    final selected = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        builder:
            (_) => _ImportSelectionScreen(
              items: imported.items,
              selectedIndexes: _selectedImportIndexes,
              duplicateIndexes: _duplicateImportIndexes,
            ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedImportIndexes = selected);
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

class _ImportSelectionScreen extends StatefulWidget {
  const _ImportSelectionScreen({
    required this.items,
    required this.selectedIndexes,
    required this.duplicateIndexes,
  });

  final List<ImportedTransaction> items;
  final Set<int> selectedIndexes;
  final Set<int> duplicateIndexes;

  @override
  State<_ImportSelectionScreen> createState() => _ImportSelectionScreenState();
}

class _ImportSelectionScreenState extends State<_ImportSelectionScreen> {
  late final Set<int> _selected = {...widget.selectedIndexes};

  Set<int> get _available => {
    for (var index = 0; index < widget.items.length; index++)
      if (!widget.duplicateIndexes.contains(index)) index,
  };

  @override
  Widget build(BuildContext context) {
    final allAvailable = _available;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar movimientos'),
        actions: [
          TextButton(
            onPressed:
                () => setState(() {
                  if (_selected.length == allAvailable.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(allAvailable);
                  }
                }),
            child: Text(
              _selected.length == allAvailable.length ? 'Ninguno' : 'Todos',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.builder(
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final duplicate = widget.duplicateIndexes.contains(index);
            return CheckboxListTile(
              value: !duplicate && _selected.contains(index),
              onChanged:
                  duplicate
                      ? null
                      : (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(index);
                        } else {
                          _selected.remove(index);
                        }
                      }),
              title: Text(item.description),
              subtitle: Text(
                duplicate
                    ? 'Duplicado: ya existe o se repite en el archivo'
                    : '${DateFormat('dd/MM/yyyy').format(item.occurredAt)} · ${item.category}',
              ),
              secondary: Text(
                NumberFormat.currency(
                  locale: 'es_EC',
                  symbol: r'$',
                  decimalDigits: 2,
                ).format(item.amountMinor / 100),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: () => Navigator.pop(context, _selected),
          icon: const Icon(Icons.check),
          label: Text('Usar ${_selected.length} movimientos'),
        ),
      ),
    );
  }
}

class _ImportPreviewContent extends StatelessWidget {
  const _ImportPreviewContent({required this.result});

  final BankStatementImportResult result;

  @override
  Widget build(BuildContext context) {
    final categories = <String, int>{};
    final now = DateTime.now();
    final currentMonthCount =
        result.items
            .where(
              (item) =>
                  item.occurredAt.year == now.year &&
                  item.occurredAt.month == now.month,
            )
            .length;
    final historicalCount = result.items.length - currentMonthCount;
    for (final item in result.items) {
      categories.update(item.category, (count) => count + 1, ifAbsent: () => 1);
    }
    final mostUsed =
        categories.entries.toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.verified_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Estado de cuenta válido',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 16),
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
              color: AppColors.deepMint,
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
        if (result.format == BankStatementFormat.pdf) ...[
          const SizedBox(height: 16),
          _FinancialHealthPreview(result: result),
        ],
        const SizedBox(height: 14),
        Text('Clasificación', style: Theme.of(context).textTheme.titleSmall),
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
        if (historicalCount > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.history,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '$historicalCount movimiento${historicalCount == 1 ? '' : 's'} de meses anteriores se guardará${historicalCount == 1 ? '' : 'n'} en el historial por mes, sin modificar el saldo ni los presupuestos actuales.${currentMonthCount > 0 ? ' Los $currentMonthCount del mes actual sí se reflejarán ahora.' : ''}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'La importación no elimina movimientos existentes. Todos los datos se cifran antes de guardarse.',
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

class _FinancialHealthPreview extends StatelessWidget {
  const _FinancialHealthPreview({required this.result});

  final BankStatementImportResult result;

  @override
  Widget build(BuildContext context) {
    final income = result.totalFor(TransactionType.income);
    final expenses = result.totalFor(TransactionType.expense);
    final savings = result.totalFor(TransactionType.saving);
    final expenseRatio = income <= 0 ? 1.0 : expenses / income;
    final savingRatio = income <= 0 ? 0.0 : savings / income;
    final (status, icon, color) =
        income <= 0
            ? (
              'Sin ingresos suficientes para evaluar',
              Icons.help_outline,
              Theme.of(context).colorScheme.onSurfaceVariant,
            )
            : expenseRatio > 1
            ? (
              'Atención: tus gastos superan tus ingresos',
              Icons.warning_amber_rounded,
              Theme.of(context).colorScheme.error,
            )
            : expenseRatio > .8
            ? (
              'Salud financiera ajustada',
              Icons.monitor_heart_outlined,
              AppColors.warningAmber,
            )
            : savingRatio >= .1
            ? (
              'Salud financiera favorable',
              Icons.favorite_outline,
              AppColors.deepMint,
            )
            : (
              'Flujo estable; puedes reforzar el ahorro',
              Icons.trending_up,
              Theme.of(context).colorScheme.primary,
            );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Salud financiera',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 13),
          _HealthBar(
            label: 'Gastos frente a ingresos',
            ratio: expenseRatio,
            color:
                expenseRatio > 1
                    ? Theme.of(context).colorScheme.error
                    : AppColors.deepMint,
          ),
          const SizedBox(height: 10),
          _HealthBar(
            label: 'Ahorro frente a ingresos',
            ratio: savingRatio,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'Lectura orientativa basada en los movimientos detectados en este PDF.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({
    required this.label,
    required this.ratio,
    required this.color,
  });

  final String label;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '${(ratio * 100).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      const SizedBox(height: 5),
      LinearProgressIndicator(
        value: ratio.clamp(0, 1),
        minHeight: 9,
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
    ],
  );
}
