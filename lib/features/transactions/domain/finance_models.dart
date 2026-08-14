enum TransactionType { expense, income, saving }

enum TransactionOrigin { manual, imported }

enum ExpenseFundingSource {
  general,
  savings,
  goal;

  String get label => switch (this) {
    ExpenseFundingSource.general => 'Saldo disponible',
    ExpenseFundingSource.savings => 'Ahorros',
    ExpenseFundingSource.goal => 'Meta de ahorro',
  };

  static ExpenseFundingSource parse(Object? value) => switch (value) {
    'savings' => ExpenseFundingSource.savings,
    'goal' => ExpenseFundingSource.goal,
    _ => ExpenseFundingSource.general,
  };
}

enum ExpenseSplitMode {
  equal,
  percentage,
  income,
  custom;

  String get label => switch (this) {
    ExpenseSplitMode.equal => 'Partes iguales',
    ExpenseSplitMode.percentage => 'Por porcentaje',
    ExpenseSplitMode.income => 'Proporcional a los ingresos',
    ExpenseSplitMode.custom => 'Valores personalizados',
  };

  static ExpenseSplitMode parse(Object? value) => switch (value) {
    'percentage' => ExpenseSplitMode.percentage,
    'income' => ExpenseSplitMode.income,
    'custom' => ExpenseSplitMode.custom,
    _ => ExpenseSplitMode.equal,
  };
}

/// A bill split is intentionally separate from the household cash flow.
///
/// It answers "who paid and how much does each person owe?" without changing
/// income, available balance, savings, goals, or financial reports.
class SharedExpense {
  const SharedExpense({
    required this.id,
    required this.description,
    required this.category,
    required this.totalMinor,
    required this.occurredAt,
    required this.createdBy,
    required this.paidByUid,
    required this.splitMode,
    required this.participantSharesMinor,
    this.sourceTransactionId,
    this.settledParticipantIds = const {},
    this.includesVat = false,
    this.includesService = false,
  });

  final String id;
  final String description;
  final String category;
  final int totalMinor;
  final DateTime occurredAt;
  final String createdBy;
  final String paidByUid;
  final ExpenseSplitMode splitMode;
  final Map<String, int> participantSharesMinor;

  /// Present when this division was created from an existing movement.
  /// The movement remains the source of truth for cash flow; this record only
  /// tracks who owes whom.
  final String? sourceTransactionId;
  final Set<String> settledParticipantIds;
  final bool includesVat;
  final bool includesService;

  int get pendingMinor => participantSharesMinor.entries
      .where(
        (entry) =>
            entry.key != paidByUid &&
            !settledParticipantIds.contains(entry.key),
      )
      .fold(0, (sum, entry) => sum + entry.value);

  int confirmedPaidMinorFor(
    String participantUid,
    Iterable<SharedExpensePayment> payments,
  ) {
    final share = participantSharesMinor[participantUid] ?? 0;
    if (participantUid == paidByUid ||
        settledParticipantIds.contains(participantUid)) {
      return share;
    }
    final paid = payments
        .where(
          (payment) =>
              payment.expenseId == id &&
              payment.participantUid == participantUid &&
              payment.status == SharedExpensePaymentStatus.confirmed,
        )
        .fold<int>(0, (sum, payment) => sum + payment.amountMinor);
    return paid.clamp(0, share);
  }

  int reportedPaidMinorFor(
    String participantUid,
    Iterable<SharedExpensePayment> payments,
  ) => payments
      .where(
        (payment) =>
            payment.expenseId == id &&
            payment.participantUid == participantUid &&
            payment.status == SharedExpensePaymentStatus.reported,
      )
      .fold<int>(0, (sum, payment) => sum + payment.amountMinor);

  int remainingMinorFor(
    String participantUid,
    Iterable<SharedExpensePayment> payments,
  ) => ((participantSharesMinor[participantUid] ?? 0) -
          confirmedPaidMinorFor(participantUid, payments))
      .clamp(0, participantSharesMinor[participantUid] ?? 0);

  int pendingMinorWith(Iterable<SharedExpensePayment> payments) =>
      participantSharesMinor.entries
          .where((entry) => entry.key != paidByUid)
          .fold<int>(
            0,
            (sum, entry) => sum + remainingMinorFor(entry.key, payments),
          );
}

class SharedExpenseDraft {
  const SharedExpenseDraft({
    required this.description,
    required this.category,
    required this.totalMinor,
    required this.occurredAt,
    required this.paidByUid,
    required this.splitMode,
    required this.participantSharesMinor,
    this.sourceTransactionId,
    this.settledParticipantIds = const {},
    this.includesVat = false,
    this.includesService = false,
  });

  final String description;
  final String category;
  final int totalMinor;
  final DateTime occurredAt;
  final String paidByUid;
  final ExpenseSplitMode splitMode;
  final Map<String, int> participantSharesMinor;
  final String? sourceTransactionId;
  final Set<String> settledParticipantIds;
  final bool includesVat;
  final bool includesService;
}

enum SharedExpensePaymentStatus {
  reported,
  confirmed,
  rejected,
  cancelled;

  static SharedExpensePaymentStatus parse(Object? value) => switch (value) {
    'confirmed' => SharedExpensePaymentStatus.confirmed,
    'rejected' => SharedExpensePaymentStatus.rejected,
    'cancelled' => SharedExpensePaymentStatus.cancelled,
    _ => SharedExpensePaymentStatus.reported,
  };
}

/// A reimbursement report. It is separate from the financial movement and
/// requires confirmation by the person who paid the original bill.
class SharedExpensePayment {
  const SharedExpensePayment({
    required this.id,
    required this.expenseId,
    required this.participantUid,
    required this.payerUid,
    required this.amountMinor,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.note,
    this.updatedAt,
    this.resolvedBy,
  });

  final String id;
  final String expenseId;
  final String participantUid;
  final String payerUid;
  final int amountMinor;
  final DateTime createdAt;
  final String createdBy;
  final SharedExpensePaymentStatus status;
  final String? note;
  final DateTime? updatedAt;
  final String? resolvedBy;
}

abstract final class SharedExpenseCategories {
  static const values = <String>[
    'Comida y restaurantes',
    'Supermercado',
    'Servicios básicos',
    'Arriendo',
    'Transporte',
    'Viaje',
    'Salud',
    'Entretenimiento',
    'Otro',
  ];
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.occurredAt,
    required this.type,
    required this.createdBy,
    required this.shared,
    this.origin = TransactionOrigin.manual,
    this.importHash,
    this.sourceName,
    this.sourceVerified = false,
    this.linkedPlanId,
    this.linkedPlanName,
    this.planDeltaMinor = 0,
    this.fundingSource = ExpenseFundingSource.general,
    this.paidByUid,
    this.splitMode = ExpenseSplitMode.equal,
    this.participantSharesMinor = const {},
    this.settledParticipantIds = const {},
  });

  final String id;
  final String description;
  final String category;
  final int amountMinor;
  final DateTime occurredAt;
  final TransactionType type;
  final String createdBy;
  final bool shared;
  final TransactionOrigin origin;
  final String? importHash;
  final String? sourceName;
  final bool sourceVerified;
  final String? linkedPlanId;
  final String? linkedPlanName;
  final int planDeltaMinor;
  final ExpenseFundingSource fundingSource;
  final String? paidByUid;
  final ExpenseSplitMode splitMode;
  final Map<String, int> participantSharesMinor;
  final Set<String> settledParticipantIds;

  /// Whether this transaction belongs in the household cash flow.
  ///
  /// Older bank imports were accidentally stored as `shared`. They are still
  /// real bank movements, so keeping this compatibility rule makes those
  /// already-imported records visible without a data migration.
  bool get countsInHouseholdFinances =>
      !shared || origin == TransactionOrigin.imported;

  bool occursInMonth(DateTime reference) =>
      occurredAt.year == reference.year && occurredAt.month == reference.month;

  /// Historical bank statements remain visible in Movimientos and historical
  /// reports, but only imports from the active month affect the live balance.
  bool affectsLiveBalanceAt(DateTime reference) =>
      countsInHouseholdFinances &&
      (origin != TransactionOrigin.imported || occursInMonth(reference));
}

class FinanceTransactionDraft {
  const FinanceTransactionDraft({
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.occurredAt,
    required this.type,
    required this.shared,
    this.origin = TransactionOrigin.manual,
    this.importHash,
    this.sourceName,
    this.sourceVerified = false,
    this.linkedPlanId,
    this.linkedPlanName,
    this.planDeltaMinor = 0,
    this.fundingSource = ExpenseFundingSource.general,
    this.paidByUid,
    this.splitMode = ExpenseSplitMode.equal,
    this.participantSharesMinor = const {},
    this.settledParticipantIds = const {},
  });

  final String description;
  final String category;
  final int amountMinor;
  final DateTime occurredAt;
  final TransactionType type;
  final bool shared;
  final TransactionOrigin origin;
  final String? importHash;
  final String? sourceName;
  final bool sourceVerified;
  final String? linkedPlanId;
  final String? linkedPlanName;
  final int planDeltaMinor;
  final ExpenseFundingSource fundingSource;
  final String? paidByUid;
  final ExpenseSplitMode splitMode;
  final Map<String, int> participantSharesMinor;
  final Set<String> settledParticipantIds;
}

enum FinancePlanKind { budget, goal }

class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.createdBy,
  });

  final String id;
  final String name;
  final TransactionType type;
  final String createdBy;
}

class FinancePlan {
  const FinancePlan({
    required this.id,
    required this.name,
    required this.kind,
    required this.targetMinor,
    required this.currentMinor,
    required this.createdBy,
    this.isActive = true,
    this.category,
    this.deadline,
    this.alertThreshold = 0.8,
  });

  final String id;
  final String name;
  final FinancePlanKind kind;
  final int targetMinor;
  final int currentMinor;
  final String createdBy;
  final bool isActive;
  final String? category;
  final DateTime? deadline;
  final double alertThreshold;
}

enum RecurrenceFrequency {
  weekly,
  biweekly,
  monthly,
  yearly;

  String get label => switch (this) {
    RecurrenceFrequency.weekly => 'Semanal',
    RecurrenceFrequency.biweekly => 'Quincenal',
    RecurrenceFrequency.monthly => 'Mensual',
    RecurrenceFrequency.yearly => 'Anual',
  };

  static RecurrenceFrequency parse(Object? value) => switch (value) {
    'weekly' => RecurrenceFrequency.weekly,
    'biweekly' => RecurrenceFrequency.biweekly,
    'yearly' => RecurrenceFrequency.yearly,
    _ => RecurrenceFrequency.monthly,
  };

  DateTime next(DateTime from) => switch (this) {
    RecurrenceFrequency.weekly => from.add(const Duration(days: 7)),
    RecurrenceFrequency.biweekly => from.add(const Duration(days: 15)),
    RecurrenceFrequency.monthly => _addMonths(from, 1),
    RecurrenceFrequency.yearly => _addMonths(from, 12),
  };
}

class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.template,
    required this.frequency,
    required this.nextDueAt,
    required this.createdBy,
    this.active = true,
    this.confirmBeforePosting = true,
  });

  final String id;
  final FinanceTransactionDraft template;
  final RecurrenceFrequency frequency;
  final DateTime nextDueAt;
  final String createdBy;
  final bool active;
  final bool confirmBeforePosting;

  bool get isDue => !nextDueAt.isAfter(DateTime.now());
}

DateTime _addMonths(DateTime source, int months) {
  final targetMonth = source.month - 1 + months;
  final year = source.year + targetMonth ~/ 12;
  final month = targetMonth % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(
    year,
    month,
    source.day.clamp(1, lastDay),
    source.hour,
    source.minute,
  );
}
