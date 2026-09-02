import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/widgets/app_page_header.dart';
import '../domain/finance_balances.dart';
import '../domain/finance_models.dart';

class SavingsScreen extends StatelessWidget {
  const SavingsScreen({
    super.key,
    required this.plans,
    required this.transactions,
    required this.canContribute,
    required this.onAddSaving,
    required this.onOpenPlans,
  });

  final Stream<List<FinancePlan>> plans;
  final Stream<List<FinanceTransaction>> transactions;
  final bool canContribute;
  final VoidCallback onAddSaving;
  final VoidCallback onOpenPlans;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<FinancePlan>>(
        stream: plans,
        builder:
            (context, planSnapshot) => StreamBuilder<List<FinanceTransaction>>(
              stream: transactions,
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
                              item.kind == FinancePlanKind.goal &&
                              item.isActive,
                        )
                        .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                  children: [
                    const AppPageHeader(
                      icon: Icons.savings_outlined,
                      title: 'Ahorros',
                      subtitle:
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
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: onAddSaving,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Agregar a mis ahorros'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.shield_outlined),
                            title: Text('Ahorro para el futuro'),
                            subtitle: Text(
                              'Es dinero separado sin una fecha obligatoria, pensado como respaldo de largo plazo.',
                            ),
                          ),
                          Divider(height: 1),
                          ListTile(
                            leading: Icon(Icons.flag_outlined),
                            title: Text('Meta con propósito'),
                            subtitle: Text(
                              'Tiene un objetivo y una fecha, por ejemplo vacaciones, estudios o una compra.',
                            ),
                          ),
                        ],
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
                      Card(
                        child: ListTile(
                          onTap: onOpenPlans,
                          leading: const Icon(Icons.flag_outlined),
                          title: const Text('Aún no hay metas'),
                          subtitle: const Text(
                            'Crea una meta en Planes para asignarle tus próximos ahorros.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      )
                    else
                      ...goals.map((goal) {
                        final goalProgress = calculatePlanProgress(
                          goal,
                          transactions,
                          DateTime.now(),
                        );
                        final current = goalProgress.currentMinor;
                        final progress = goalProgress.ratio;
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
                                if (goal.deadline != null) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    'Fecha objetivo: ${DateFormat('dd/MM/yyyy').format(goal.deadline!)}${goalProgress.recommendedMonthlyMinor == null ? '' : ' · Aporte sugerido ${_money(goalProgress.recommendedMonthlyMinor!)} al mes'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
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
                      Card(
                        child: ListTile(
                          onTap: canContribute ? onAddSaving : null,
                          leading: const Icon(Icons.savings_outlined),
                          title: const Text('Todavía no has apartado dinero'),
                          subtitle:
                              canContribute
                                  ? const Text('Toca aquí para comenzar')
                                  : null,
                          trailing:
                              canContribute
                                  ? const Icon(Icons.add_circle_outline)
                                  : null,
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
                                  '${item.linkedPlanName == null ? 'Ahorro a futuro' : 'Meta: ${item.linkedPlanName}'} · ${DateFormat('dd/MM/yyyy').format(item.occurredAt)}',
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
      ),
    );
  }
}

String _money(int minor) => NumberFormat.currency(
  locale: 'es_EC',
  symbol: r'$',
  decimalDigits: 2,
).format(minor / 100);
