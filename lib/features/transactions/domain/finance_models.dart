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
  custom;

  String get label => switch (this) {
    ExpenseSplitMode.equal => 'Partes iguales',
    ExpenseSplitMode.percentage => 'Por porcentaje',
    ExpenseSplitMode.custom => 'Valores personalizados',
  };

  static ExpenseSplitMode parse(Object? value) => switch (value) {
    'percentage' => ExpenseSplitMode.percentage,
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
  final Set<String> settledParticipantIds;
  final bool includesVat;
  final bool includesService;
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

class FinanceTransactionDraft {
  const FinanceTransactionDraft({
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.occurredAt,
    required this.type,
    required this.shared,
    this.origin = TransactionOrigin.manual,
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
