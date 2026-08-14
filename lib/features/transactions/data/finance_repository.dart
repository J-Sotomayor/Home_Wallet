import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/firebase_error_mapper.dart';
import '../../../core/security/household_crypto_service.dart';
import '../../../core/security/secure_key_store.dart';
import '../domain/finance_models.dart';
import '../domain/transaction_categories.dart';
import '../domain/transaction_validation.dart';

abstract interface class FinanceRepository {
  Stream<List<FinanceTransaction>> watchTransactions(String householdId);
  Stream<List<FinancePlan>> watchPlans(String householdId);
  Stream<List<FinanceCategory>> watchCategories(String householdId);
  Stream<List<RecurringTransaction>> watchRecurring(String householdId);
  Stream<List<SharedExpense>> watchSharedExpenses(String householdId);
  Future<void> addTransaction({
    required String householdId,
    required String uid,
    required String description,
    required String category,
    required int amountMinor,
    required TransactionType type,
    required bool shared,
    DateTime? occurredAt,
    FinancePlan? linkedPlan,
    ExpenseFundingSource fundingSource = ExpenseFundingSource.general,
    String? paidByUid,
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, int> participantSharesMinor = const {},
  });
  Future<void> updateTransaction({
    required String householdId,
    required FinanceTransaction original,
    required String description,
    required String category,
    required int amountMinor,
    required DateTime occurredAt,
    required TransactionType type,
    required bool shared,
    FinancePlan? linkedPlan,
    ExpenseFundingSource fundingSource = ExpenseFundingSource.general,
    String? paidByUid,
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, int> participantSharesMinor = const {},
  });
  Future<void> addTransactions({
    required String householdId,
    required String uid,
    required List<FinanceTransactionDraft> transactions,
  });
  Future<void> deleteTransaction(
    String householdId,
    FinanceTransaction transaction,
  );
  Future<void> addPlan({
    required String householdId,
    required String uid,
    required String name,
    required FinancePlanKind kind,
    required int targetMinor,
    String? category,
    DateTime? deadline,
    double alertThreshold = 0.8,
  });
  Future<void> updatePlan({
    required String householdId,
    required FinancePlan plan,
    required String name,
    required int targetMinor,
    required bool isActive,
    String? category,
    DateTime? deadline,
    double alertThreshold = 0.8,
  });
  Future<void> deletePlan(String householdId, FinancePlan plan);
  Future<void> addCategory({
    required String householdId,
    required String uid,
    required String name,
    required TransactionType type,
  });
  Future<void> updateCategory({
    required String householdId,
    required FinanceCategory category,
    required String name,
  });
  Future<void> deleteCategory(String householdId, FinanceCategory category);
  Future<void> addRecurring({
    required String householdId,
    required String uid,
    required FinanceTransactionDraft template,
    required RecurrenceFrequency frequency,
    required DateTime nextDueAt,
    bool confirmBeforePosting = true,
  });
  Future<void> updateRecurring({
    required String householdId,
    required RecurringTransaction recurring,
  });
  Future<void> deleteRecurring(
    String householdId,
    RecurringTransaction recurring,
  );
  Future<void> confirmRecurring({
    required String householdId,
    required String uid,
    required RecurringTransaction recurring,
  });
  Future<void> addSharedExpense({
    required String householdId,
    required String uid,
    required SharedExpenseDraft expense,
  });
  Future<void> settleSharedParticipant({
    required String householdId,
    required SharedExpense expense,
    required String participantUid,
  });
}

class FirebaseFinanceRepository implements FinanceRepository {
  FirebaseFinanceRepository({
    required SecureKeyStore keyStore,
    required HouseholdCryptoService crypto,
    FirebaseFirestore? firestore,
  }) : _keyStore = keyStore,
       _crypto = crypto,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final SecureKeyStore _keyStore;
  final HouseholdCryptoService _crypto;
  final FirebaseFirestore _firestore;

  @override
  Stream<List<FinanceTransaction>> watchTransactions(
    String householdId,
  ) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('transactions')
      .where(
        'occurredAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_transactionCutoff()),
      )
      .orderBy('occurredAt', descending: true)
      .limit(1000)
      .snapshots()
      .asyncMap((snapshot) async {
        final key = await _requireKey(householdId);
        final result = <FinanceTransaction>[];
        for (final document in snapshot.docs) {
          final data = document.data();
          final clear = await _crypto.decryptJson(
            payload: _asMap(data['payload']),
            keyBytes: key,
            context: 'households/$householdId/transactions/${document.id}',
          );
          final type = switch (data['type']) {
            'income' => TransactionType.income,
            'saving' => TransactionType.saving,
            _ => TransactionType.expense,
          };
          final description = clear['description'] as String;
          result.add(
            FinanceTransaction(
              id: document.id,
              description: description,
              category: TransactionCategories.normalizeExisting(
                type,
                clear['category'] as String,
                description,
              ),
              amountMinor: (clear['amountMinor'] as num).toInt(),
              occurredAt:
                  (data['occurredAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              type: type,
              createdBy: data['createdBy'] as String? ?? '',
              shared: clear['shared'] as bool? ?? true,
              origin:
                  clear['origin'] == 'imported'
                      ? TransactionOrigin.imported
                      : TransactionOrigin.manual,
              importHash: clear['importHash'] as String?,
              sourceName: clear['sourceName'] as String?,
              sourceVerified: clear['sourceVerified'] as bool? ?? false,
              linkedPlanId: clear['linkedPlanId'] as String?,
              linkedPlanName: clear['linkedPlanName'] as String?,
              planDeltaMinor: (clear['planDeltaMinor'] as num?)?.toInt() ?? 0,
              fundingSource: ExpenseFundingSource.parse(clear['fundingSource']),
              paidByUid: clear['paidByUid'] as String?,
              splitMode: ExpenseSplitMode.parse(clear['splitMode']),
              participantSharesMinor: _asIntMap(
                clear['participantSharesMinor'],
              ),
              settledParticipantIds:
                  (clear['settledParticipantIds'] as List?)
                      ?.map((value) => value.toString())
                      .toSet() ??
                  const {},
            ),
          );
        }
        return result;
      });

  @override
  Stream<List<FinancePlan>> watchPlans(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('plans')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .asyncMap((snapshot) async {
        final key = await _requireKey(householdId);
        final result = <FinancePlan>[];
        for (final document in snapshot.docs) {
          final data = document.data();
          final clear = await _crypto.decryptJson(
            payload: _asMap(data['payload']),
            keyBytes: key,
            context: 'households/$householdId/plans/${document.id}',
          );
          result.add(
            FinancePlan(
              id: document.id,
              name: clear['name'] as String,
              kind:
                  data['kind'] == 'goal'
                      ? FinancePlanKind.goal
                      : FinancePlanKind.budget,
              targetMinor: (clear['targetMinor'] as num).toInt(),
              currentMinor: (clear['currentMinor'] as num?)?.toInt() ?? 0,
              createdBy: data['createdBy'] as String? ?? '',
              isActive: clear['isActive'] as bool? ?? true,
              category: clear['category'] as String?,
              deadline: _dateFromValue(clear['deadline']),
              alertThreshold:
                  (clear['alertThreshold'] as num?)?.toDouble() ?? 0.8,
            ),
          );
        }
        return result;
      });

  @override
  Stream<List<FinanceCategory>> watchCategories(String householdId) =>
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('categories')
          .orderBy('createdAt')
          .limit(100)
          .snapshots()
          .asyncMap((snapshot) async {
            final key = await _requireKey(householdId);
            final result = <FinanceCategory>[];
            for (final document in snapshot.docs) {
              final data = document.data();
              final clear = await _crypto.decryptJson(
                payload: _asMap(data['payload']),
                keyBytes: key,
                context: 'households/$householdId/categories/${document.id}',
              );
              result.add(
                FinanceCategory(
                  id: document.id,
                  name: clear['name'] as String,
                  type: _typeFromValue(data['type']),
                  createdBy: data['createdBy'] as String? ?? '',
                ),
              );
            }
            return result;
          });

  @override
  Stream<List<RecurringTransaction>> watchRecurring(String householdId) =>
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('recurring')
          .orderBy('nextDueAt')
          .limit(100)
          .snapshots()
          .asyncMap((snapshot) async {
            final key = await _requireKey(householdId);
            final result = <RecurringTransaction>[];
            for (final document in snapshot.docs) {
              final data = document.data();
              final clear = await _crypto.decryptJson(
                payload: _asMap(data['payload']),
                keyBytes: key,
                context: 'households/$householdId/recurring/${document.id}',
              );
              result.add(
                RecurringTransaction(
                  id: document.id,
                  template: _draftFromClear(clear),
                  frequency: RecurrenceFrequency.parse(data['frequency']),
                  nextDueAt:
                      (data['nextDueAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                  createdBy: data['createdBy'] as String? ?? '',
                  active: data['active'] as bool? ?? true,
                  confirmBeforePosting:
                      data['confirmBeforePosting'] as bool? ?? true,
                ),
              );
            }
            return result;
          });

  @override
  Stream<List<SharedExpense>> watchSharedExpenses(String householdId) =>
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('sharedExpenses')
          .orderBy('occurredAt', descending: true)
          .limit(500)
          .snapshots()
          .asyncMap((snapshot) async {
            final key = await _requireKey(householdId);
            final result = <SharedExpense>[];
            for (final document in snapshot.docs) {
              final data = document.data();
              final clear = await _crypto.decryptJson(
                payload: _asMap(data['payload']),
                keyBytes: key,
                context:
                    'households/$householdId/sharedExpenses/${document.id}',
              );
              result.add(
                SharedExpense(
                  id: document.id,
                  description: clear['description'] as String,
                  category: clear['category'] as String? ?? 'Otro',
                  totalMinor: (clear['totalMinor'] as num).toInt(),
                  occurredAt:
                      (data['occurredAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                  createdBy: data['createdBy'] as String? ?? '',
                  paidByUid: clear['paidByUid'] as String,
                  splitMode: ExpenseSplitMode.parse(clear['splitMode']),
                  participantSharesMinor: _asIntMap(
                    clear['participantSharesMinor'],
                  ),
                  settledParticipantIds:
                      (clear['settledParticipantIds'] as List?)
                          ?.map((value) => value.toString())
                          .toSet() ??
                      const {},
                  includesVat: clear['includesVat'] as bool? ?? false,
                  includesService: clear['includesService'] as bool? ?? false,
                ),
              );
            }
            return result;
          });

  @override
  Future<void> addTransaction({
    required String householdId,
    required String uid,
    required String description,
    required String category,
    required int amountMinor,
    required TransactionType type,
    required bool shared,
    DateTime? occurredAt,
    FinancePlan? linkedPlan,
    ExpenseFundingSource fundingSource = ExpenseFundingSource.general,
    String? paidByUid,
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, int> participantSharesMinor = const {},
  }) async {
    final planDelta = switch (type) {
      TransactionType.expense => -amountMinor,
      TransactionType.income || TransactionType.saving => amountMinor,
    };
    final draft = FinanceTransactionDraft(
      description: description,
      category: category,
      amountMinor: amountMinor,
      occurredAt: occurredAt ?? DateTime.now(),
      type: type,
      shared: shared,
      linkedPlanId: linkedPlan?.id,
      linkedPlanName: linkedPlan?.name,
      planDeltaMinor: linkedPlan == null ? 0 : planDelta,
      fundingSource:
          type == TransactionType.expense
              ? fundingSource
              : ExpenseFundingSource.general,
      paidByUid: paidByUid ?? uid,
      splitMode: splitMode,
      participantSharesMinor: shared ? participantSharesMinor : const {},
    );
    validateTransactionDraft(draft);
    if (linkedPlan != null) {
      if (linkedPlan.kind != FinancePlanKind.goal || !linkedPlan.isActive) {
        throw const AppException('Selecciona una meta activa.');
      }
      if (linkedPlan.currentMinor + planDelta < 0) {
        throw AppException(
          'La meta ${linkedPlan.name} no tiene saldo suficiente para este gasto.',
        );
      }
    }
    if (type == TransactionType.expense &&
        fundingSource == ExpenseFundingSource.goal &&
        linkedPlan == null) {
      throw const AppException('Selecciona la meta de la que salió el dinero.');
    }
    try {
      final key = await _requireKey(householdId);
      final batch = _firestore.batch();
      final transactionReference =
          _firestore
              .collection('households')
              .doc(householdId)
              .collection('transactions')
              .doc();
      final payload = await _encryptTransactionPayload(
        householdId: householdId,
        referenceId: transactionReference.id,
        transaction: draft,
        key: key,
      );
      batch.set(
        transactionReference,
        _transactionDocument(draft, uid, payload),
      );
      if (linkedPlan != null) {
        final nextPlan = FinancePlan(
          id: linkedPlan.id,
          name: linkedPlan.name,
          kind: linkedPlan.kind,
          targetMinor: linkedPlan.targetMinor,
          currentMinor: linkedPlan.currentMinor + planDelta,
          createdBy: linkedPlan.createdBy,
          isActive: linkedPlan.isActive,
          category: linkedPlan.category,
          deadline: linkedPlan.deadline,
          alertThreshold: linkedPlan.alertThreshold,
        );
        final planPayload = await _encryptPlanPayload(
          householdId: householdId,
          plan: nextPlan,
          key: key,
        );
        batch.update(_planReference(householdId, linkedPlan.id), {
          'payload': planPayload,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateTransaction({
    required String householdId,
    required FinanceTransaction original,
    required String description,
    required String category,
    required int amountMinor,
    required DateTime occurredAt,
    required TransactionType type,
    required bool shared,
    FinancePlan? linkedPlan,
    ExpenseFundingSource fundingSource = ExpenseFundingSource.general,
    String? paidByUid,
    ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
    Map<String, int> participantSharesMinor = const {},
  }) async {
    final planDelta = switch (type) {
      TransactionType.expense => -amountMinor,
      TransactionType.income || TransactionType.saving => amountMinor,
    };
    final updated = FinanceTransactionDraft(
      description: description,
      category: category,
      amountMinor: amountMinor,
      occurredAt: occurredAt,
      type: type,
      shared: shared,
      origin: original.origin,
      importHash: original.importHash,
      sourceName: original.sourceName,
      // Any manual correction breaks the exact match with the source file.
      sourceVerified: false,
      linkedPlanId: linkedPlan?.id,
      linkedPlanName: linkedPlan?.name,
      planDeltaMinor: linkedPlan == null ? 0 : planDelta,
      fundingSource:
          type == TransactionType.expense
              ? fundingSource
              : ExpenseFundingSource.general,
      paidByUid: paidByUid,
      splitMode: splitMode,
      participantSharesMinor: shared ? participantSharesMinor : const {},
      settledParticipantIds: original.settledParticipantIds,
    );
    validateTransactionDraft(updated);
    if (updated.fundingSource == ExpenseFundingSource.goal &&
        linkedPlan == null) {
      throw const AppException('Selecciona la meta de la que salió el dinero.');
    }
    try {
      final key = await _requireKey(householdId);
      final batch = _firestore.batch();
      final transactionReference = _firestore
          .collection('households')
          .doc(householdId)
          .collection('transactions')
          .doc(original.id);
      final payload = await _encryptTransactionPayload(
        householdId: householdId,
        referenceId: original.id,
        transaction: updated,
        key: key,
      );
      batch.update(transactionReference, {
        'type': type.name,
        'occurredAt': Timestamp.fromDate(occurredAt),
        'updatedAt': FieldValue.serverTimestamp(),
        'payload': payload,
      });

      final planChanges = <String, int>{};
      if (original.linkedPlanId != null && original.planDeltaMinor != 0) {
        planChanges.update(
          original.linkedPlanId!,
          (value) => value - original.planDeltaMinor,
          ifAbsent: () => -original.planDeltaMinor,
        );
      }
      if (linkedPlan != null && updated.planDeltaMinor != 0) {
        planChanges.update(
          linkedPlan.id,
          (value) => value + updated.planDeltaMinor,
          ifAbsent: () => updated.planDeltaMinor,
        );
      }
      for (final change in planChanges.entries) {
        final plan =
            linkedPlan?.id == change.key
                ? linkedPlan
                : await _readPlan(householdId, change.key, key);
        if (plan == null) continue;
        final nextCurrent = plan.currentMinor + change.value;
        if (nextCurrent < 0) {
          throw AppException('La meta ${plan.name} no tiene saldo suficiente.');
        }
        final changedPlan = FinancePlan(
          id: plan.id,
          name: plan.name,
          kind: plan.kind,
          targetMinor: plan.targetMinor,
          currentMinor: nextCurrent,
          createdBy: plan.createdBy,
          isActive: plan.isActive,
          category: plan.category,
          deadline: plan.deadline,
          alertThreshold: plan.alertThreshold,
        );
        batch.update(_planReference(householdId, plan.id), {
          'payload': await _encryptPlanPayload(
            householdId: householdId,
            plan: changedPlan,
            key: key,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> addRecurring({
    required String householdId,
    required String uid,
    required FinanceTransactionDraft template,
    required RecurrenceFrequency frequency,
    required DateTime nextDueAt,
    bool confirmBeforePosting = true,
  }) async {
    validateTransactionDraft(template, enforceHistoryWindow: false);
    if (!nextDueAt.isAfter(
      DateTime.now().subtract(const Duration(minutes: 1)),
    )) {
      throw const AppException('Selecciona una fecha futura.');
    }
    try {
      final key = await _requireKey(householdId);
      final reference =
          _firestore
              .collection('households')
              .doc(householdId)
              .collection('recurring')
              .doc();
      await reference.set({
        'schemaVersion': 1,
        'frequency': frequency.name,
        'nextDueAt': Timestamp.fromDate(nextDueAt),
        'active': true,
        'confirmBeforePosting': confirmBeforePosting,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'payload': await _encryptRecurringPayload(
          householdId: householdId,
          referenceId: reference.id,
          transaction: template,
          key: key,
        ),
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateRecurring({
    required String householdId,
    required RecurringTransaction recurring,
  }) async {
    validateTransactionDraft(recurring.template, enforceHistoryWindow: false);
    try {
      final key = await _requireKey(householdId);
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('recurring')
          .doc(recurring.id)
          .update({
            'frequency': recurring.frequency.name,
            'nextDueAt': Timestamp.fromDate(recurring.nextDueAt),
            'active': recurring.active,
            'confirmBeforePosting': recurring.confirmBeforePosting,
            'updatedAt': FieldValue.serverTimestamp(),
            'payload': await _encryptRecurringPayload(
              householdId: householdId,
              referenceId: recurring.id,
              transaction: recurring.template,
              key: key,
            ),
          });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> deleteRecurring(
    String householdId,
    RecurringTransaction recurring,
  ) async {
    try {
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('recurring')
          .doc(recurring.id)
          .delete();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> confirmRecurring({
    required String householdId,
    required String uid,
    required RecurringTransaction recurring,
  }) async {
    final template = recurring.template;
    validateTransactionDraft(template, enforceHistoryWindow: false);
    final postedAt = DateTime.now();
    final posted = FinanceTransactionDraft(
      description: template.description,
      category: template.category,
      amountMinor: template.amountMinor,
      occurredAt: postedAt,
      type: template.type,
      shared: template.shared,
      fundingSource: template.fundingSource,
      paidByUid: template.paidByUid ?? uid,
      splitMode: template.splitMode,
      participantSharesMinor: template.participantSharesMinor,
    );
    validateTransactionDraft(posted);
    try {
      final key = await _requireKey(householdId);
      final dueId = recurring.nextDueAt.millisecondsSinceEpoch;
      final transactionReference = _firestore
          .collection('households')
          .doc(householdId)
          .collection('transactions')
          .doc('recurring_${recurring.id}_$dueId');
      final recurringReference = _firestore
          .collection('households')
          .doc(householdId)
          .collection('recurring')
          .doc(recurring.id);
      final transactionPayload = await _encryptTransactionPayload(
        householdId: householdId,
        referenceId: transactionReference.id,
        transaction: posted,
        key: key,
      );
      final recurringPayload = await _encryptRecurringPayload(
        householdId: householdId,
        referenceId: recurring.id,
        transaction: template,
        key: key,
      );
      final batch = _firestore.batch();
      batch.set(
        transactionReference,
        _transactionDocument(posted, uid, transactionPayload),
      );
      batch.update(recurringReference, {
        'frequency': recurring.frequency.name,
        'nextDueAt': Timestamp.fromDate(
          recurring.frequency.next(recurring.nextDueAt),
        ),
        'active': recurring.active,
        'confirmBeforePosting': recurring.confirmBeforePosting,
        'updatedAt': FieldValue.serverTimestamp(),
        'payload': recurringPayload,
      });
      await batch.commit();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> addSharedExpense({
    required String householdId,
    required String uid,
    required SharedExpenseDraft expense,
  }) async {
    _validateSharedExpense(expense);
    try {
      final key = await _requireKey(householdId);
      final reference =
          _firestore
              .collection('households')
              .doc(householdId)
              .collection('sharedExpenses')
              .doc();
      await reference.set({
        'schemaVersion': 1,
        'occurredAt': Timestamp.fromDate(expense.occurredAt),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'payload': await _encryptSharedExpensePayload(
          householdId: householdId,
          referenceId: reference.id,
          expense: expense,
          key: key,
        ),
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> settleSharedParticipant({
    required String householdId,
    required SharedExpense expense,
    required String participantUid,
  }) async {
    if (!expense.participantSharesMinor.containsKey(participantUid)) {
      throw const AppException('Este integrante no participa en el gasto.');
    }
    try {
      final key = await _requireKey(householdId);
      final settled = {...expense.settledParticipantIds, participantUid};
      final draft = SharedExpenseDraft(
        description: expense.description,
        category: expense.category,
        totalMinor: expense.totalMinor,
        occurredAt: expense.occurredAt,
        paidByUid: expense.paidByUid,
        splitMode: expense.splitMode,
        participantSharesMinor: expense.participantSharesMinor,
        settledParticipantIds: settled,
        includesVat: expense.includesVat,
        includesService: expense.includesService,
      );
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('sharedExpenses')
          .doc(expense.id)
          .update({
            'payload': await _encryptSharedExpensePayload(
              householdId: householdId,
              referenceId: expense.id,
              expense: draft,
              key: key,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> addTransactions({
    required String householdId,
    required String uid,
    required List<FinanceTransactionDraft> transactions,
  }) async {
    if (transactions.isEmpty || transactions.length > 500) {
      throw const AppException(
        'La importación debe contener entre 1 y 500 movimientos.',
      );
    }
    for (final transaction in transactions) {
      validateTransactionDraft(transaction);
    }
    try {
      final key = await _requireKey(householdId);
      final batch = _firestore.batch();
      for (final transaction in transactions) {
        final reference =
            _firestore
                .collection('households')
                .doc(householdId)
                .collection('transactions')
                .doc();
        final payload = await _encryptTransactionPayload(
          householdId: householdId,
          referenceId: reference.id,
          transaction: transaction,
          key: key,
        );
        batch.set(reference, _transactionDocument(transaction, uid, payload));
      }
      await batch.commit();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  static void _validateSharedExpense(SharedExpenseDraft expense) {
    final description = expense.description.trim();
    if (description.isEmpty || description.length > 100) {
      throw const AppException(
        'La descripción debe tener entre 1 y 100 caracteres.',
      );
    }
    if (expense.totalMinor <= 0 || expense.totalMinor > 99999999999) {
      throw const AppException('El total de la cuenta no es válido.');
    }
    if (expense.participantSharesMinor.length < 2 ||
        !expense.participantSharesMinor.containsKey(expense.paidByUid)) {
      throw const AppException(
        'Elige al menos dos participantes e indica quién pagó.',
      );
    }
    if (expense.participantSharesMinor.values.any((value) => value < 0) ||
        expense.participantSharesMinor.values.fold<int>(
              0,
              (total, value) => total + value,
            ) !=
            expense.totalMinor) {
      throw const AppException(
        'La división debe sumar exactamente el total de la cuenta.',
      );
    }
  }

  @override
  Future<void> deleteTransaction(
    String householdId,
    FinanceTransaction transaction,
  ) async {
    try {
      final batch = _firestore.batch();
      batch.delete(
        _firestore
            .collection('households')
            .doc(householdId)
            .collection('transactions')
            .doc(transaction.id),
      );
      if (transaction.linkedPlanId != null && transaction.planDeltaMinor != 0) {
        final key = await _requireKey(householdId);
        final plan = await _readPlan(
          householdId,
          transaction.linkedPlanId!,
          key,
        );
        if (plan != null) {
          final restored = FinancePlan(
            id: plan.id,
            name: plan.name,
            kind: plan.kind,
            targetMinor: plan.targetMinor,
            currentMinor: (plan.currentMinor - transaction.planDeltaMinor)
                .clamp(0, 99999999999),
            createdBy: plan.createdBy,
            isActive: plan.isActive,
            category: plan.category,
            deadline: plan.deadline,
            alertThreshold: plan.alertThreshold,
          );
          final payload = await _encryptPlanPayload(
            householdId: householdId,
            plan: restored,
            key: key,
          );
          batch.update(_planReference(householdId, plan.id), {
            'payload': payload,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> addPlan({
    required String householdId,
    required String uid,
    required String name,
    required FinancePlanKind kind,
    required int targetMinor,
    String? category,
    DateTime? deadline,
    double alertThreshold = 0.8,
  }) async {
    final cleanName = _validatePlanInput(
      name: name,
      kind: kind,
      targetMinor: targetMinor,
      category: category,
      deadline: deadline,
      alertThreshold: alertThreshold,
    );
    try {
      final key = await _requireKey(householdId);
      final reference =
          _firestore
              .collection('households')
              .doc(householdId)
              .collection('plans')
              .doc();
      final payload = await _crypto.encryptJson(
        value: {
          'name': cleanName,
          'targetMinor': targetMinor,
          'currentMinor': 0,
          'isActive': true,
          if (kind == FinancePlanKind.budget) 'category': category,
          if (deadline != null) 'deadline': deadline.toIso8601String(),
          'alertThreshold': alertThreshold,
        },
        keyBytes: key,
        context: 'households/$householdId/plans/${reference.id}',
      );
      await reference.set({
        'schemaVersion': 1,
        'kind': kind.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'payload': payload,
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updatePlan({
    required String householdId,
    required FinancePlan plan,
    required String name,
    required int targetMinor,
    required bool isActive,
    String? category,
    DateTime? deadline,
    double alertThreshold = 0.8,
  }) async {
    final cleanName = _validatePlanInput(
      name: name,
      kind: plan.kind,
      targetMinor: targetMinor,
      category: category,
      deadline: deadline,
      alertThreshold: alertThreshold,
      requireFutureDeadline: isActive,
    );
    final updated = FinancePlan(
      id: plan.id,
      name: cleanName,
      kind: plan.kind,
      targetMinor: targetMinor,
      currentMinor: plan.currentMinor,
      createdBy: plan.createdBy,
      isActive: isActive,
      category: plan.kind == FinancePlanKind.budget ? category : null,
      deadline: plan.kind == FinancePlanKind.goal ? deadline : null,
      alertThreshold: alertThreshold,
    );
    try {
      final key = await _requireKey(householdId);
      await _planReference(householdId, plan.id).update({
        'payload': await _encryptPlanPayload(
          householdId: householdId,
          plan: updated,
          key: key,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> deletePlan(String householdId, FinancePlan plan) async {
    if (plan.kind == FinancePlanKind.goal && plan.currentMinor > 0) {
      throw const AppException(
        'Una meta con aportes no se elimina para no perder su trazabilidad. Márcala como completada o inactiva.',
      );
    }
    try {
      await _planReference(householdId, plan.id).delete();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> addCategory({
    required String householdId,
    required String uid,
    required String name,
    required TransactionType type,
  }) async {
    final cleanName = _validateCategoryName(name);
    if (TransactionCategories.all.any(
      (value) => value.toLowerCase() == cleanName.toLowerCase(),
    )) {
      throw const AppException('Esa categoría ya viene incluida en la app.');
    }
    try {
      final key = await _requireKey(householdId);
      final reference =
          _firestore
              .collection('households')
              .doc(householdId)
              .collection('categories')
              .doc();
      await reference.set({
        'schemaVersion': 1,
        'type': type.name,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'payload': await _crypto.encryptJson(
          value: {'name': cleanName},
          keyBytes: key,
          context: 'households/$householdId/categories/${reference.id}',
        ),
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateCategory({
    required String householdId,
    required FinanceCategory category,
    required String name,
  }) async {
    final cleanName = _validateCategoryName(name);
    try {
      final key = await _requireKey(householdId);
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('categories')
          .doc(category.id)
          .update({
            'updatedAt': FieldValue.serverTimestamp(),
            'payload': await _crypto.encryptJson(
              value: {'name': cleanName},
              keyBytes: key,
              context: 'households/$householdId/categories/${category.id}',
            ),
          });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> deleteCategory(
    String householdId,
    FinanceCategory category,
  ) async {
    try {
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('categories')
          .doc(category.id)
          .delete();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  Future<List<int>> _requireKey(String householdId) async {
    final key = await _keyStore.readHouseholdKey(householdId);
    if (key == null) {
      throw const AppException(
        'No se encontró la clave de cifrado de este espacio.',
        code: 'missing-household-key',
      );
    }
    return key;
  }

  static TransactionType _typeFromValue(Object? value) => switch (value) {
    'income' => TransactionType.income,
    'saving' => TransactionType.saving,
    _ => TransactionType.expense,
  };

  static String _validatePlanInput({
    required String name,
    required FinancePlanKind kind,
    required int targetMinor,
    required String? category,
    required DateTime? deadline,
    required double alertThreshold,
    bool requireFutureDeadline = true,
  }) {
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty ||
        cleanName.length > 80 ||
        targetMinor <= 0 ||
        alertThreshold < 0.5 ||
        alertThreshold > 1) {
      throw const AppException('Completa un nombre y un objetivo válidos.');
    }
    if (kind == FinancePlanKind.budget &&
        (category == null ||
            !TransactionCategories.expenses.contains(category))) {
      throw const AppException('Selecciona la categoría del presupuesto.');
    }
    if (kind == FinancePlanKind.goal) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (deadline == null ||
          (requireFutureDeadline && deadline.isBefore(today))) {
        throw const AppException(
          'Selecciona una fecha límite válida para la meta.',
        );
      }
    }
    return cleanName;
  }

  static String _validateCategoryName(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length < 2 || clean.length > 40) {
      throw const AppException(
        'El nombre de la categoría debe tener entre 2 y 40 caracteres.',
      );
    }
    return clean;
  }

  DocumentReference<Map<String, dynamic>> _planReference(
    String householdId,
    String planId,
  ) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('plans')
      .doc(planId);

  Future<Map<String, dynamic>> _encryptTransactionPayload({
    required String householdId,
    required String referenceId,
    required FinanceTransactionDraft transaction,
    required List<int> key,
  }) => _crypto.encryptJson(
    value: {
      'description': transaction.description.trim(),
      'category': transaction.category.trim(),
      'amountMinor': transaction.amountMinor,
      'shared': transaction.shared,
      'origin': transaction.origin.name,
      if (transaction.importHash != null) 'importHash': transaction.importHash,
      if (transaction.sourceName?.trim().isNotEmpty ?? false)
        'sourceName': transaction.sourceName!.trim(),
      'sourceVerified': transaction.sourceVerified,
      if (transaction.linkedPlanId != null)
        'linkedPlanId': transaction.linkedPlanId,
      if (transaction.linkedPlanName != null)
        'linkedPlanName': transaction.linkedPlanName,
      'planDeltaMinor': transaction.planDeltaMinor,
      'fundingSource': transaction.fundingSource.name,
      if (transaction.paidByUid != null) 'paidByUid': transaction.paidByUid,
      'splitMode': transaction.splitMode.name,
      if (transaction.participantSharesMinor.isNotEmpty)
        'participantSharesMinor': transaction.participantSharesMinor,
      if (transaction.settledParticipantIds.isNotEmpty)
        'settledParticipantIds': transaction.settledParticipantIds.toList(),
    },
    keyBytes: key,
    context: 'households/$householdId/transactions/$referenceId',
  );

  Future<Map<String, dynamic>> _encryptRecurringPayload({
    required String householdId,
    required String referenceId,
    required FinanceTransactionDraft transaction,
    required List<int> key,
  }) => _crypto.encryptJson(
    value: {
      'description': transaction.description.trim(),
      'category': transaction.category.trim(),
      'amountMinor': transaction.amountMinor,
      'occurredAt': transaction.occurredAt.toIso8601String(),
      'type': transaction.type.name,
      'shared': transaction.shared,
      'fundingSource': transaction.fundingSource.name,
      if (transaction.paidByUid != null) 'paidByUid': transaction.paidByUid,
      'splitMode': transaction.splitMode.name,
      if (transaction.participantSharesMinor.isNotEmpty)
        'participantSharesMinor': transaction.participantSharesMinor,
    },
    keyBytes: key,
    context: 'households/$householdId/recurring/$referenceId',
  );

  Future<Map<String, dynamic>> _encryptSharedExpensePayload({
    required String householdId,
    required String referenceId,
    required SharedExpenseDraft expense,
    required List<int> key,
  }) => _crypto.encryptJson(
    value: {
      'description': expense.description.trim(),
      'category': expense.category.trim(),
      'totalMinor': expense.totalMinor,
      'paidByUid': expense.paidByUid,
      'splitMode': expense.splitMode.name,
      'participantSharesMinor': expense.participantSharesMinor,
      if (expense.settledParticipantIds.isNotEmpty)
        'settledParticipantIds': expense.settledParticipantIds.toList(),
      'includesVat': expense.includesVat,
      'includesService': expense.includesService,
    },
    keyBytes: key,
    context: 'households/$householdId/sharedExpenses/$referenceId',
  );

  static Map<String, dynamic> _transactionDocument(
    FinanceTransactionDraft transaction,
    String uid,
    Map<String, dynamic> payload,
  ) => {
    'schemaVersion': 1,
    'type': transaction.type.name,
    'occurredAt': Timestamp.fromDate(transaction.occurredAt),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'createdBy': uid,
    'payload': payload,
  };

  Future<Map<String, dynamic>> _encryptPlanPayload({
    required String householdId,
    required FinancePlan plan,
    required List<int> key,
  }) => _crypto.encryptJson(
    value: {
      'name': plan.name,
      'targetMinor': plan.targetMinor,
      'currentMinor': plan.currentMinor,
      'isActive': plan.isActive,
      if (plan.category != null) 'category': plan.category,
      if (plan.deadline != null) 'deadline': plan.deadline!.toIso8601String(),
      'alertThreshold': plan.alertThreshold,
    },
    keyBytes: key,
    context: 'households/$householdId/plans/${plan.id}',
  );

  Future<FinancePlan?> _readPlan(
    String householdId,
    String planId,
    List<int> key,
  ) async {
    final snapshot = await _planReference(householdId, planId).get();
    if (!snapshot.exists) return null;
    final data = snapshot.data()!;
    final clear = await _crypto.decryptJson(
      payload: _asMap(data['payload']),
      keyBytes: key,
      context: 'households/$householdId/plans/$planId',
    );
    return FinancePlan(
      id: planId,
      name: clear['name'] as String,
      kind:
          data['kind'] == 'goal'
              ? FinancePlanKind.goal
              : FinancePlanKind.budget,
      targetMinor: (clear['targetMinor'] as num).toInt(),
      currentMinor: (clear['currentMinor'] as num?)?.toInt() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
      isActive: clear['isActive'] as bool? ?? true,
      category: clear['category'] as String?,
      deadline: _dateFromValue(clear['deadline']),
      alertThreshold: (clear['alertThreshold'] as num?)?.toDouble() ?? 0.8,
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const FormatException('El documento cifrado no es válido.');
  }

  static Map<String, int> _asIntMap(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, item) => MapEntry(key.toString(), (item as num).toInt()),
    );
  }

  static DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static FinanceTransactionDraft _draftFromClear(Map<String, dynamic> clear) {
    final type = switch (clear['type']) {
      'income' => TransactionType.income,
      'saving' => TransactionType.saving,
      _ => TransactionType.expense,
    };
    return FinanceTransactionDraft(
      description: clear['description'] as String,
      category: TransactionCategories.normalizeExisting(
        type,
        clear['category'] as String,
        clear['description'] as String,
      ),
      amountMinor: (clear['amountMinor'] as num).toInt(),
      occurredAt: _dateFromValue(clear['occurredAt']) ?? DateTime.now(),
      type: type,
      shared: clear['shared'] as bool? ?? false,
      origin:
          clear['origin'] == 'imported'
              ? TransactionOrigin.imported
              : TransactionOrigin.manual,
      importHash: clear['importHash'] as String?,
      sourceName: clear['sourceName'] as String?,
      sourceVerified: clear['sourceVerified'] as bool? ?? false,
      fundingSource: ExpenseFundingSource.parse(clear['fundingSource']),
      paidByUid: clear['paidByUid'] as String?,
      splitMode: ExpenseSplitMode.parse(clear['splitMode']),
      participantSharesMinor: _asIntMap(clear['participantSharesMinor']),
    );
  }
}

DateTime _transactionCutoff() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(const Duration(days: 364));
}
