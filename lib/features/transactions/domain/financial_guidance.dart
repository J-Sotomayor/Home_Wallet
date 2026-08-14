import 'finance_balances.dart';
import 'finance_models.dart';

enum FinancialGuidanceTone { positive, informative, caution, critical }

class FinancialGuidance {
  const FinancialGuidance({
    required this.tone,
    required this.title,
    required this.message,
  });

  final FinancialGuidanceTone tone;
  final String title;
  final String message;
}

FinancialGuidance evaluateTransactionGuidance({
  required TransactionType type,
  required String description,
  required String category,
  required int amountMinor,
  required DateTime occurredAt,
  required ExpenseFundingSource fundingSource,
  required List<FinanceTransaction> transactions,
  required List<FinancePlan> plans,
  FinancePlan? linkedPlan,
}) {
  if (type == TransactionType.expense) {
    final budgets =
        plans
            .where(
              (plan) =>
                  plan.isActive &&
                  plan.kind == FinancePlanKind.budget &&
                  (plan.category == null || plan.category == category),
            )
            .toList();
    if (budgets.isNotEmpty) {
      budgets.sort((left, right) {
        final leftAfter =
            automaticPlanProgress(left, transactions, occurredAt) + amountMinor;
        final rightAfter =
            automaticPlanProgress(right, transactions, occurredAt) +
            amountMinor;
        return (rightAfter / right.targetMinor).compareTo(
          leftAfter / left.targetMinor,
        );
      });
      final budget = budgets.first;
      final current = automaticPlanProgress(budget, transactions, occurredAt);
      final after = current + amountMinor;
      final remaining = (budget.targetMinor - after).clamp(0, 99999999999);
      if (after > budget.targetMinor) {
        return FinancialGuidance(
          tone: FinancialGuidanceTone.critical,
          title: 'Superarás tu presupuesto',
          message:
              '${budget.name} quedará sobre el límite por ${_money(after - budget.targetMinor)}. ${_expenseAdvice(category, description)}',
        );
      }
      if (after == budget.targetMinor) {
        return FinancialGuidance(
          tone: FinancialGuidanceTone.critical,
          title: 'Este presupuesto quedará en \$0',
          message:
              'Usarás el 100% de ${budget.name}. Confirma solo si es necesario y cuida tu salud financiera para el resto del mes.',
        );
      }
      final ratio = after / budget.targetMinor;
      if (ratio >= budget.alertThreshold) {
        return FinancialGuidance(
          tone: FinancialGuidanceTone.caution,
          title: 'Te acercas al límite',
          message:
              'Después de este gasto quedarán ${_money(remaining)} en ${budget.name}. ${_expenseAdvice(category, description)}',
        );
      }
    }

    final balances = FinanceBalances.calculate(
      transactions,
      plans,
      currentPeriod: occurredAt,
    );
    final available = switch (fundingSource) {
      ExpenseFundingSource.general => balances.available,
      ExpenseFundingSource.savings => balances.savings,
      ExpenseFundingSource.goal => linkedPlan?.currentMinor ?? 0,
    };
    if (amountMinor >= available && available > 0) {
      return FinancialGuidance(
        tone: FinancialGuidanceTone.critical,
        title:
            amountMinor == available
                ? 'Este saldo quedará en \$0'
                : 'El gasto supera este saldo',
        message:
            amountMinor == available
                ? 'No quedará dinero en la fuente elegida. Revisa tus próximos pagos antes de confirmar.'
                : 'Faltan ${_money(amountMinor - available)} para cubrirlo. Elige el origen real del dinero.',
      );
    }
    return FinancialGuidance(
      tone: FinancialGuidanceTone.informative,
      title: 'Gasto bajo control',
      message: _expenseAdvice(category, description),
    );
  }

  if (linkedPlan != null) {
    final after = linkedPlan.currentMinor + amountMinor;
    if (after >= linkedPlan.targetMinor) {
      return FinancialGuidance(
        tone: FinancialGuidanceTone.positive,
        title: '¡Con este movimiento completas tu meta!',
        message:
            '${linkedPlan.name} llegará al 100%. HomeWallet te avisará cuando el aporte quede guardado.',
      );
    }
    final percent =
        (after * 100 / linkedPlan.targetMinor).clamp(0, 100).round();
    return FinancialGuidance(
      tone: FinancialGuidanceTone.positive,
      title: 'Tu meta sigue avanzando',
      message:
          '${linkedPlan.name} llegará al $percent%. Cada aporte constante acerca el objetivo.',
    );
  }

  final messages =
      type == TransactionType.income
          ? const [
            'Registrar tus ingresos mantiene tus decisiones basadas en datos reales.',
            'Buen paso: ahora tu saldo y tus reportes representan mejor el mes.',
            'Ingreso identificado. Considera separar una parte para ahorro o una meta.',
          ]
          : const [
            'Separar dinero hoy protege tus próximos gastos importantes.',
            'Buen hábito: la constancia suele importar más que el tamaño de un solo aporte.',
            'Tu ahorro fortalece el respaldo financiero del espacio.',
          ];
  return FinancialGuidance(
    tone: FinancialGuidanceTone.positive,
    title:
        type == TransactionType.income
            ? 'Buen registro financiero'
            : 'Estás fortaleciendo tus ahorros',
    message:
        messages[_stableIndex('$description|$amountMinor', messages.length)],
  );
}

String _expenseAdvice(String category, String description) {
  final variants = <String>[
    'Comprueba que sea necesario ahora y conserva margen para los gastos que faltan este mes.',
    'Revisa el monto una vez más; una compra consciente también cuida tu tranquilidad financiera.',
    'Si puede esperar, compáralo con tus prioridades del mes antes de confirmarlo.',
    'El registro mejora tu control. Procura mantener una reserva para imprevistos.',
  ];
  return variants[_stableIndex('$category|$description', variants.length)];
}

int _stableIndex(String value, int length) {
  var hash = 17;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash % length;
}

String _money(int minor) =>
    '\$${(minor / 100).toStringAsFixed(2).replaceAll('.', ',')}';
