import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/transaction_categories.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.householdId,
    required this.uid,
    required this.repository,
    required this.authRepository,
    required this.preferredCategories,
    required this.canContribute,
  });

  final String householdId;
  final String uid;
  final FinanceRepository repository;
  final AuthRepository authRepository;
  final Set<String> preferredCategories;
  final bool canContribute;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final Set<String> _preferred =
      widget.preferredCategories.isEmpty
          ? TransactionCategories.all.toSet()
          : {...widget.preferredCategories};
  bool _savingPreferences = false;

  String get householdId => widget.householdId;
  String get uid => widget.uid;
  FinanceRepository get repository => widget.repository;
  bool get canContribute => widget.canContribute;

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
                    'Activa las que quieras ver al registrar movimientos. Esta selección es solo para tu perfil.',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${_preferred.length} activas')),
                    TextButton(
                      onPressed:
                          _savingPreferences
                              ? null
                              : () => _replacePreferences(
                                TransactionCategories.all.toSet(),
                              ),
                      child: const Text('Activar todas'),
                    ),
                  ],
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
                          leading: Checkbox(
                            value: _preferred.contains(name),
                            onChanged:
                                _savingPreferences
                                    ? null
                                    : (value) =>
                                        _togglePreference(name, value ?? false),
                          ),
                          title: Text(name),
                          subtitle: Text(
                            _preferred.contains(name)
                                ? 'Visible al registrar'
                                : 'Disponible para activar',
                          ),
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

  Future<void> _togglePreference(String name, bool enabled) async {
    final next = {..._preferred};
    enabled ? next.add(name) : next.remove(name);
    if (next.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mantén al menos una categoría activa.')),
      );
      return;
    }
    await _replacePreferences(next);
  }

  Future<void> _replacePreferences(Set<String> next) async {
    final previous = {..._preferred};
    setState(() {
      _preferred
        ..clear()
        ..addAll(next);
      _savingPreferences = true;
    });
    try {
      await widget.authRepository.updatePreferredCategories(
        _preferred.toList(),
      );
    } on AppException catch (error) {
      if (mounted) {
        setState(
          () =>
              _preferred
                ..clear()
                ..addAll(previous),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
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
