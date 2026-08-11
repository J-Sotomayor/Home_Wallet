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
  HouseholdKind _kind = HouseholdKind.family;

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
                  const Center(child: HomeWalletLogo(width: 250, height: 74)),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Configura tu hogar',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No agregamos datos de demostración. Empieza creando un hogar vacío o escaneando la invitación de tu familia.',
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
                                    'Crear un hogar nuevo',
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
                              'Nombre del hogar',
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
                              'Tipo de hogar',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 330;
                                return SegmentedButton<HouseholdKind>(
                                  segments: [
                                    ButtonSegment(
                                      value: HouseholdKind.family,
                                      label: const Text('Familia'),
                                      icon:
                                          compact
                                              ? null
                                              : const Icon(
                                                Icons.family_restroom,
                                              ),
                                    ),
                                    ButtonSegment(
                                      value: HouseholdKind.couple,
                                      label: const Text('Pareja'),
                                      icon:
                                          compact
                                              ? null
                                              : const Icon(
                                                Icons.favorite_outline,
                                              ),
                                    ),
                                    ButtonSegment(
                                      value: HouseholdKind.group,
                                      label: const Text('Grupo'),
                                      icon:
                                          compact
                                              ? null
                                              : const Icon(
                                                Icons.groups_outlined,
                                              ),
                                    ),
                                  ],
                                  selected: {_kind},
                                  style: ButtonStyle(
                                    foregroundColor:
                                        WidgetStateProperty.resolveWith(
                                          (states) =>
                                              states.contains(
                                                    WidgetState.selected,
                                                  )
                                                  ? scheme.onPrimary
                                                  : states.contains(
                                                    WidgetState.disabled,
                                                  )
                                                  ? scheme.onSurfaceVariant
                                                  : scheme.onSurface,
                                        ),
                                    backgroundColor:
                                        WidgetStateProperty.resolveWith(
                                          (states) =>
                                              states.contains(
                                                    WidgetState.selected,
                                                  )
                                                  ? scheme.primary
                                                  : scheme
                                                      .surfaceContainerHighest,
                                        ),
                                    side: WidgetStatePropertyAll(
                                      BorderSide(color: scheme.outline),
                                    ),
                                    visualDensity:
                                        compact
                                            ? VisualDensity.compact
                                            : VisualDensity.standard,
                                  ),
                                  onSelectionChanged:
                                      _busy
                                          ? null
                                          : (value) => setState(
                                            () => _kind = value.first,
                                          ),
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
                                    ? 'Hogar creado'
                                    : _busy
                                    ? 'Creando hogar…'
                                    : 'Crear hogar cifrado',
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
                                'Estamos cifrando y confirmando el hogar con Firebase. No cierres esta pantalla.',
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
                    label: const Text('Escanear invitación familiar'),
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
}
