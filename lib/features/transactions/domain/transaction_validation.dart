import '../../../core/errors/app_exception.dart';
import 'finance_models.dart';

void validateTransactionDraft(
  FinanceTransactionDraft transaction, {
  bool enforceHistoryWindow = true,
  DateTime? now,
}) {
  final cleanDescription = transaction.description.trim();
  if (cleanDescription.isEmpty || cleanDescription.length > 100) {
    throw const AppException(
      'La descripción debe tener entre 1 y 100 caracteres.',
    );
  }
  if (transaction.amountMinor <= 0 || transaction.amountMinor > 99999999999) {
    throw const AppException('El monto ingresado no es válido.');
  }
  if (enforceHistoryWindow) {
    final occurredDay = DateTime(
      transaction.occurredAt.year,
      transaction.occurredAt.month,
      transaction.occurredAt.day,
    );
    final reference = now ?? DateTime.now();
    final currentDay = DateTime(reference.year, reference.month, reference.day);
    final cutoff = currentDay.subtract(const Duration(days: 364));
    if (occurredDay.isBefore(cutoff) || occurredDay.isAfter(currentDay)) {
      throw const AppException(
        'HomeWallet conserva únicamente movimientos de los últimos 365 días.',
      );
    }
  }
  final cleanCategory = transaction.category.trim();
  if (cleanCategory.isEmpty || cleanCategory.length > 40) {
    throw const AppException('La categoría seleccionada no es válida.');
  }
  if (transaction.shared &&
      transaction.type == TransactionType.expense &&
      transaction.participantSharesMinor.isNotEmpty) {
    if (transaction.participantSharesMinor.values.any((value) => value < 0) ||
        transaction.participantSharesMinor.values.fold<int>(
              0,
              (total, value) => total + value,
            ) !=
            transaction.amountMinor) {
      throw const AppException(
        'La distribución del gasto debe sumar exactamente el monto total.',
      );
    }
    if (transaction.paidByUid == null ||
        !transaction.participantSharesMinor.containsKey(
          transaction.paidByUid,
        )) {
      throw const AppException(
        'Selecciona quién pagó y los participantes del gasto.',
      );
    }
  }
}
