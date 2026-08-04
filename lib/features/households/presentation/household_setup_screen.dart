import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
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
  });

  final AuthUser user;
  final HouseholdRepository repository;
  final Future<void> Function() onSignOut;

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _nameController = TextEditingController();
  bool _busy = false;
  HouseholdKind _kind = HouseholdKind.family;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  Card(
                    color: AppColors.blushPinkLight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.home_outlined,
                                color: AppColors.blushPinkDark,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Crear un hogar nuevo',
                                style: TextStyle(
                                  color: AppColors.darkGray,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            key: const Key('household_name'),
                            controller: _nameController,
                            enabled: !_busy,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 60,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del hogar',
                              hintText: 'Ej. Familia González',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SegmentedButton<HouseholdKind>(
                            segments: const [
                              ButtonSegment(
                                value: HouseholdKind.family,
                                label: Text('Familia'),
                                icon: Icon(Icons.family_restroom),
                              ),
                              ButtonSegment(
                                value: HouseholdKind.couple,
                                label: Text('Pareja'),
                                icon: Icon(Icons.favorite_outline),
                              ),
                              ButtonSegment(
                                value: HouseholdKind.group,
                                label: Text('Grupo'),
                                icon: Icon(Icons.groups_outlined),
                              ),
                            ],
                            selected: {_kind},
                            onSelectionChanged:
                                _busy
                                    ? null
                                    : (value) =>
                                        setState(() => _kind = value.first),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            key: const Key('create_household'),
                            onPressed: _busy ? null : _create,
                            icon: const Icon(Icons.add_home_outlined),
                            label: const Text('Crear hogar cifrado'),
                          ),
                        ],
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
    setState(() => _busy = true);
    try {
      await widget.repository.createHousehold(
        _nameController.text,
        widget.user,
        kind: _kind,
      );
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
