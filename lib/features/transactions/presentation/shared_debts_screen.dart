import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../households/data/household_repository.dart';
import '../../households/domain/household_models.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';

class SharedDebtsScreen extends StatelessWidget {
  const SharedDebtsScreen({
    super.key,
    required this.householdId,
    required this.repository,
    required this.households,
    required this.canContribute,
  });

  final String householdId;
  final FinanceRepository repository;
  final HouseholdRepository households;
  final bool canContribute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos compartidos y deudas')),
      body: StreamBuilder<List<HouseholdMember>>(
        stream: households.watchMembers(householdId),
        builder: (context, memberSnapshot) {
          return StreamBuilder<List<FinanceTransaction>>(
            stream: repository.watchTransactions(householdId),
            builder: (context, transactionSnapshot) {
              if (memberSnapshot.hasError || transactionSnapshot.hasError) {
                return const Center(
                  child: Text('No se pudieron cargar las deudas.'),
                );
              }
              if (!memberSnapshot.hasData || !transactionSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final names = {
                for (final member in memberSnapshot.data!)
                  member.uid: member.displayName,
              };
              final debts = <_Debt>[];
              for (final transaction in transactionSnapshot.data!.where(
                (item) =>
                    item.type == TransactionType.expense &&
                    item.shared &&
                    item.participantSharesMinor.isNotEmpty,
              )) {
                for (final share
                    in transaction.participantSharesMinor.entries) {
                  if (share.key == transaction.paidByUid) continue;
                  debts.add(
                    _Debt(
                      transaction: transaction,
                      participantUid: share.key,
                      amountMinor: share.value,
                      settled: transaction.settledParticipantIds.contains(
                        share.key,
                      ),
                    ),
                  );
                }
              }
              debts.sort((a, b) {
                if (a.settled != b.settled) return a.settled ? 1 : -1;
                return b.transaction.occurredAt.compareTo(
                  a.transaction.occurredAt,
                );
              });
              if (debts.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aún no hay deudas. Registra un gasto compartido y elige participantes para calcularlas.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final pending = debts
                  .where((debt) => !debt.settled)
                  .fold<int>(0, (sum, debt) => sum + debt.amountMinor);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Total pendiente'),
                      subtitle: const Text(
                        'Suma de participaciones todavía no pagadas',
                      ),
                      trailing: Text(
                        _money(pending),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...debts.map(
                    (debt) => Card(
                      child: ListTile(
                        leading: Icon(
                          debt.settled
                              ? Icons.check_circle
                              : Icons.account_balance_wallet_outlined,
                          color:
                              debt.settled
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(debt.transaction.description),
                        subtitle: Text(
                          '${names[debt.participantUid] ?? 'Integrante'} debe ${_money(debt.amountMinor)} a ${names[debt.transaction.paidByUid] ?? 'quien pagó'}\n${DateFormat('dd/MM/yyyy').format(debt.transaction.occurredAt)} · ${debt.transaction.splitMode.label}',
                        ),
                        isThreeLine: true,
                        trailing:
                            debt.settled
                                ? const Text('Pagada')
                                : IconButton.filledTonal(
                                  tooltip: 'Marcar como pagada',
                                  onPressed:
                                      canContribute
                                          ? () => _settle(context, debt)
                                          : null,
                                  icon: const Icon(Icons.done),
                                ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _settle(BuildContext context, _Debt debt) async {
    try {
      await repository.settleSharedParticipant(
        householdId: householdId,
        transaction: debt.transaction,
        participantUid: debt.participantUid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deuda marcada como pagada.')),
        );
      }
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _Debt {
  const _Debt({
    required this.transaction,
    required this.participantUid,
    required this.amountMinor,
    required this.settled,
  });

  final FinanceTransaction transaction;
  final String participantUid;
  final int amountMinor;
  final bool settled;
}

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);
