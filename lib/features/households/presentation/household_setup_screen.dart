import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/widgets/homewallet_logo.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../data/household_repository.dart';
import '../domain/household_models.dart';
import 'family_invite_screen.dart';

class HouseholdSetupScreen extends StatefulWidget {
  const HouseholdSetupScreen({
    super.key,
    required this.user,
    required this.repository,
    required this.onSignOut,
    this.onHouseholdCreated,
  });

  final AuthUser user;
  final HouseholdRepository repository;
  final Future<void> Function() onSignOut;
  final ValueChanged<String>? onHouseholdCreated;

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _busy = false;
  bool _created = false;
  HouseholdKind _kind = HouseholdKind.individual;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cardColor = Color.alphaBlend(
      scheme.primary.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.14 : 0.08,
      ),
      scheme.surfaceContainerHigh,
    );
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _busy ? null : widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: HomeWalletLogo(width: 220, height: 200)),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Configura tu espacio',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No agregamos datos de demostración. Empieza creando un espacio vacío o ingresando una invitación.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Form(
                    key: _formKey,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.home_outlined,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Crear un espacio nuevo',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'Nombre del espacio',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextFormField(
                              key: const Key('household_name'),
                              controller: _nameController,
                              enabled: !_busy,
                              style: TextStyle(color: scheme.onSurface),
                              cursorColor: scheme.primary,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 60,
                              validator: (value) {
                                final length = value?.trim().length ?? 0;
                                return length < 2 || length > 60
                                    ? 'Escribe un nombre de 2 a 60 caracteres.'
                                    : null;
                              },
                              onFieldSubmitted: (_) {
                                if (!_busy) _create();
                              },
                              decoration: InputDecoration(
                                hintText: 'Ej. Familia González',
                                hintStyle: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                                counterStyle: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                                prefixIcon: Icon(
                                  Icons.edit_outlined,
                                  color: scheme.primary,
                                ),
                                filled: true,
                                fillColor: scheme.surfaceContainerHighest,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: scheme.outline),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: scheme.primary,
                                    width: 2,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Tipo de espacio',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = (constraints.maxWidth - 8) / 2;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      HouseholdKind.values
                                          .map(
                                            (kind) => SizedBox(
                                              width: width,
                                              child: _HouseholdKindOption(
                                                key: Key(
                                                  'household_kind_${kind.name}',
                                                ),
                                                kind: kind,
                                                selected: _kind == kind,
                                                enabled: !_busy,
                                                onTap:
                                                    () => setState(
                                                      () => _kind = kind,
                                                    ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                );
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              key: const Key('create_household'),
                              onPressed: _busy ? null : _create,
                              icon:
                                  _busy
                                      ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.add_home_outlined),
                              label: Text(
                                _created
                                    ? 'Espacio creado'
                                    : _busy
                                    ? 'Creando espacio…'
                                    : 'Crear espacio cifrado',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: scheme.onPrimary,
                                disabledBackgroundColor: scheme.primary
                                    .withValues(alpha: 0.65),
                                disabledForegroundColor: scheme.onPrimary,
                              ),
                            ),
                            if (_busy) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Estamos cifrando y confirmando el espacio con Firebase. No cierres esta pantalla.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    key: const Key('join_household'),
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Ingresar invitación'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final householdId = await widget.repository.createHousehold(
        _nameController.text,
        widget.user,
        kind: _kind,
      );
      if (!mounted) return;
      setState(() => _created = true);
      widget.onHouseholdCreated?.call(householdId);
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => JoinHouseholdScreen(
              user: widget.user,
              repository: widget.repository,
            ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static IconData _kindIcon(HouseholdKind kind) => switch (kind) {
    HouseholdKind.individual => Icons.person_outline,
    HouseholdKind.family => Icons.family_restroom,
    HouseholdKind.couple => Icons.favorite_outline,
    HouseholdKind.group => Icons.groups_outlined,
  };
}

class _HouseholdKindOption extends StatelessWidget {
  const _HouseholdKindOption({
    super.key,
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final HouseholdKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color:
          selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(
                _HouseholdSetupScreenState._kindIcon(kind),
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        selected ? scheme.onPrimaryContainer : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 18, color: scheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
