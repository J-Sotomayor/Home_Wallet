import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/finance_repository.dart';
import '../domain/finance_balances.dart';
import '../domain/finance_models.dart';

class SavingsScreen extends StatelessWidget {
  const SavingsScreen({
    super.key,
    required this.householdId,
    required this.repository,
    required this.canContribute,
    required this.onAddSaving,
    required this.onOpenPlans,
  });

  final String householdId;
  final FinanceRepository repository;
  final bool canContribute;
  final VoidCallback onAddSaving;
  final VoidCallback onOpenPlans;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinancePlan>>(
      stream: repository.watchPlans(householdId),
      builder:
          (context, planSnapshot) => StreamBuilder<List<FinanceTransaction>>(
            stream: repository.watchTransactions(householdId),
            builder: (context, transactionSnapshot) {
              if (planSnapshot.hasError || transactionSnapshot.hasError) {
                return const Center(
                  child: Text('No se pudieron cargar tus ahorros.'),
                );
              }
              if (!planSnapshot.hasData || !transactionSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final plans = planSnapshot.data!;
              final transactions = transactionSnapshot.data!;
              final savings =
                  transactions
                      .where((item) => item.type == TransactionType.saving)
                      .toList();
              final balances = FinanceBalances.calculate(transactions, plans);
              final goals =
                  plans
                      .where(
                        (item) =>
                            item.kind == FinancePlanKind.goal && item.isActive,
                      )
                      .toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
                children: [
                  Text(
                    'Ahorros',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Aparta dinero hoy y sigue el avance de tus metas.',
                  ),
                  const SizedBox(height: 18),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ahorro disponible',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _money(balances.savings),
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 14),
                          if (canContribute)
                            FilledButton.icon(
                              onPressed: onAddSaving,
                              icon: const Icon(Icons.add),
                              label: const Text('Registrar ahorro'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Metas activas',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: onOpenPlans,
                        child: const Text('Ver planes'),
                      ),
                    ],
                  ),
                  if (goals.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.flag_outlined),
                        title: Text('Aún no hay metas'),
                        subtitle: Text(
                          'Crea una meta en Planes para asignarle tus próximos ahorros.',
                        ),
                      ),
                    )
                  else
                    ...goals.map((goal) {
                      final current = automaticPlanProgress(
                        goal,
                        transactions,
                        DateTime.now(),
                      );
                      final progress =
                          goal.targetMinor == 0
                              ? 0.0
                              : current / goal.targetMinor;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      goal.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(progress * 100).clamp(0, 999).round()}%',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: progress.clamp(0, 1),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_money(current)} de ${_money(goal.targetMinor)}',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  Text(
                    'Aportes recientes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (savings.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.savings_outlined),
                        title: Text('Todavía no has apartado dinero'),
                      ),
                    )
                  else
                    ...savings
                        .take(12)
                        .map(
                          (item) => Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.savings_outlined),
                              ),
                              title: Text(item.description),
                              subtitle: Text(
                                '${item.category} · ${DateFormat('dd/MM/yyyy').format(item.occurredAt)}',
                              ),
                              trailing: Text(
                                _money(item.amountMinor),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                ],
              );
            },
          ),
    );
  }
}

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);
