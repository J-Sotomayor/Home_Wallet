import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../../transactions/domain/finance_models.dart';
import '../../transactions/domain/transaction_categories.dart';

class CategorySetupScreen extends StatefulWidget {
  const CategorySetupScreen({
    super.key,
    required this.user,
    required this.repository,
    required this.onSignOut,
  });

  final AuthUser user;
  final AuthRepository repository;
  final Future<void> Function() onSignOut;

  @override
  State<CategorySetupScreen> createState() => _CategorySetupScreenState();
}

class _CategorySetupScreenState extends State<CategorySetupScreen> {
  late final Set<String> _selected = {
    if (widget.user.preferredCategories.isNotEmpty)
      ...widget.user.preferredCategories
    else ...const [
      'Alimentación',
      'Arriendo',
      'Luz',
      'Agua',
      'Internet',
      'Transporte',
      'Salud',
      'Sueldo',
      'Fondo de emergencia',
    ],
  };
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _busy ? null : widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
          children: [
            Icon(
              Icons.tune_outlined,
              size: 62,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '¿Qué quieres organizar?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Elige las categorías que usarás con más frecuencia. Podrás activar otras o crear nuevas en cualquier momento.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected.length} seleccionadas',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed:
                      _busy
                          ? null
                          : () => setState(() {
                            if (_selected.length ==
                                TransactionCategories.all.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(TransactionCategories.all);
                            }
                          }),
                  child: Text(
                    _selected.length == TransactionCategories.all.length
                        ? 'Quitar todas'
                        : 'Elegir todas',
                  ),
                ),
              ],
            ),
            for (final type in TransactionType.values) ...[
              const SizedBox(height: 14),
              Text(
                _typeLabel(type),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    TransactionCategories.forType(type).map((category) {
                      final selected = _selected.contains(category);
                      return FilterChip(
                        selected: selected,
                        showCheckmark: false,
                        selectedColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        side: BorderSide(
                          color:
                              selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                          width: selected ? 1.5 : 1,
                        ),
                        avatar: Icon(
                          selected
                              ? Icons.check_circle_outline
                              : _categoryIcon(category),
                          size: 18,
                          color:
                              selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                        ),
                        label: Text(category),
                        onSelected:
                            _busy
                                ? null
                                : (value) => setState(() {
                                  value
                                      ? _selected.add(category)
                                      : _selected.remove(category);
                                }),
                      );
                    }).toList(),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              key: const Key('finish_category_setup'),
              onPressed: _busy || _selected.isEmpty ? null : _continue,
              icon:
                  _busy
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.arrow_forward),
              label: const Text('Continuar al hogar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      await widget.repository.completeOnboarding(_selected.toList());
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _typeLabel(TransactionType type) => switch (type) {
  TransactionType.expense => 'Gastos del hogar',
  TransactionType.income => 'Ingresos',
  TransactionType.saving => 'Ahorros',
};

IconData _categoryIcon(String category) => switch (category) {
  'Luz' => Icons.lightbulb_outline,
  'Agua' => Icons.water_drop_outlined,
  'Internet' => Icons.wifi,
  'Arriendo' || 'Vivienda' => Icons.home_outlined,
  'Transporte' => Icons.directions_bus_outlined,
  'Salud' => Icons.health_and_safety_outlined,
  'Alimentación' => Icons.restaurant_outlined,
  'Sueldo' => Icons.work_outline,
  'Fondo de emergencia' => Icons.shield_outlined,
  _ => Icons.label_outline,
};
