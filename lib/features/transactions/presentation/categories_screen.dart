import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/transaction_categories.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({
    super.key,
    required this.householdId,
    required this.uid,
    required this.repository,
    required this.canContribute,
  });

  final String householdId;
  final String uid;
  final FinanceRepository repository;
  final bool canContribute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton:
          canContribute
              ? FloatingActionButton.extended(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('Categoría'),
              )
              : null,
      body: StreamBuilder<List<FinanceCategory>>(
        stream: repository.watchCategories(householdId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar las categorías.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final custom = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Categorías predeterminadas'),
                  subtitle: Text(
                    'Siempre disponibles; las sugerencias automáticas las usan al analizar la descripción.',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              for (final type in TransactionType.values) ...[
                Text(
                  _typeLabel(type),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      ...TransactionCategories.forType(type).map(
                        (name) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.lock_outline, size: 19),
                          title: Text(name),
                          subtitle: const Text('Predeterminada'),
                        ),
                      ),
                      ...custom
                          .where((item) => item.type == type)
                          .map(
                            (category) => ListTile(
                              leading: const Icon(Icons.label_outline),
                              title: Text(category.name),
                              subtitle: const Text('Personalizada'),
                              trailing:
                                  canContribute && category.createdBy == uid
                                      ? PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _edit(context, existing: category);
                                          } else {
                                            _delete(context, category);
                                          }
                                        },
                                        itemBuilder:
                                            (_) => const [
                                              PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Editar'),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Eliminar'),
                                              ),
                                            ],
                                      )
                                      : null,
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, {FinanceCategory? existing}) async {
    final input = await showModalBottomSheet<_CategoryInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryForm(existing: existing),
    );
    if (input == null || !context.mounted) return;
    try {
      if (existing == null) {
        await repository.addCategory(
          householdId: householdId,
          uid: uid,
          name: input.name,
          type: input.type,
        );
      } else {
        await repository.updateCategory(
          householdId: householdId,
          category: existing,
          name: input.name,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Categoría creada.' : 'Categoría actualizada.',
            ),
          ),
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

  Future<void> _delete(BuildContext context, FinanceCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar categoría'),
            content: const Text(
              'Los movimientos existentes conservarán el nombre guardado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repository.deleteCategory(householdId, category);
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.existing});

  final FinanceCategory? existing;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name,
  );
  late TransactionType _type = widget.existing?.type ?? TransactionType.expense;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: SizedBox(width: 42, child: Divider(thickness: 4)),
          ),
          const SizedBox(height: 16),
          Text(
            widget.existing == null ? 'Nueva categoría' : 'Editar categoría',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<TransactionType>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items:
                TransactionType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_typeLabel(type)),
                      ),
                    )
                    .toList(),
            onChanged:
                widget.existing != null
                    ? null
                    : (value) => setState(
                      () => _type = value ?? TransactionType.expense,
                    ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              if (name.length < 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Escribe un nombre válido.')),
                );
                return;
              }
              Navigator.pop(context, _CategoryInput(name: name, type: _type));
            },
            child: const Text('Guardar categoría'),
          ),
        ],
      ),
    );
  }
}

class _CategoryInput {
  const _CategoryInput({required this.name, required this.type});

  final String name;
  final TransactionType type;
}

String _typeLabel(TransactionType type) => switch (type) {
  TransactionType.expense => 'Gastos',
  TransactionType.income => 'Ingresos',
  TransactionType.saving => 'Ahorros',
};
