import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../domain/finance_models.dart';
import 'transaction_csv_service.dart';
import 'transaction_import_rules.dart';

class TransactionImportIdentity {
  const TransactionImportIdentity();

  Future<String> forImported(ImportedTransaction transaction) => _hash(
    description: transaction.description,
    amountMinor: transaction.amountMinor,
    occurredAt: transaction.occurredAt,
    type: transaction.type,
  );

  Future<String> forExisting(FinanceTransaction transaction) async =>
      transaction.importHash ??
      _hash(
        description: transaction.description,
        amountMinor: transaction.amountMinor,
        occurredAt: transaction.occurredAt,
        type: transaction.type,
      );

  Future<String> _hash({
    required String description,
    required int amountMinor,
    required DateTime occurredAt,
    required TransactionType type,
  }) async {
    final date =
        '${occurredAt.year.toString().padLeft(4, '0')}-'
        '${occurredAt.month.toString().padLeft(2, '0')}-'
        '${occurredAt.day.toString().padLeft(2, '0')}';
    final canonical = [
      date,
      type.name,
      amountMinor.toString(),
      TransactionImportRules.normalize(description),
    ].join('|');
    final digest = await Sha256().hash(utf8.encode(canonical));
    return digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
