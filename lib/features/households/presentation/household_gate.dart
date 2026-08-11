import 'package:flutter/material.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/theme_controller.dart';
import '../../../app/widgets/homewallet_logo.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/presentation/home_shell.dart';
import '../../onboarding/presentation/category_setup_screen.dart';
import 'family_invite_screen.dart';
import 'household_setup_screen.dart';

class HouseholdGate extends StatefulWidget {
  const HouseholdGate({
    super.key,
    required this.user,
    required this.services,
    required this.themeController,
  });

  final AuthUser user;
  final AppServices services;
  final ThemeController themeController;

  @override
  State<HouseholdGate> createState() => _HouseholdGateState();
}

class _HouseholdGateState extends State<HouseholdGate> {
  late Stream<String?> _householdStream;
  String? _confirmedHouseholdId;

  @override
  void initState() {
    super.initState();
    _householdStream = widget.services.households.watchActiveHouseholdId(
      widget.user.uid,
    );
  }

  @override
  void didUpdateWidget(covariant HouseholdGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.services.households != widget.services.households) {
      _confirmedHouseholdId = null;
      _householdStream = widget.services.households.watchActiveHouseholdId(
        widget.user.uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user.needsOnboarding) {
      return CategorySetupScreen(
        user: widget.user,
        repository: widget.services.auth,
        onSignOut: widget.services.auth.signOut,
      );
    }
    return StreamBuilder<String?>(
      stream: _householdStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GateError(
            message: 'No se pudo consultar el hogar activo.',
            onSignOut: widget.services.auth.signOut,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final householdId = _confirmedHouseholdId ?? snapshot.data;
        if (householdId == null || householdId.isEmpty) {
          return HouseholdSetupScreen(
            user: widget.user,
            repository: widget.services.households,
            onSignOut: widget.services.auth.signOut,
            onHouseholdCreated: (value) {
              if (mounted) setState(() => _confirmedHouseholdId = value);
            },
          );
        }
        return _HouseholdKeyGate(
          householdId: householdId,
          user: widget.user,
          services: widget.services,
          themeController: widget.themeController,
        );
      },
    );
  }
}

class _HouseholdKeyGate extends StatefulWidget {
  const _HouseholdKeyGate({
    required this.householdId,
    required this.user,
    required this.services,
    required this.themeController,
  });

  final String householdId;
  final AuthUser user;
  final AppServices services;
  final ThemeController themeController;

  @override
  State<_HouseholdKeyGate> createState() => _HouseholdKeyGateState();
}

class _HouseholdKeyGateState extends State<_HouseholdKeyGate> {
  late Future<bool> _hasKey = widget.services.households.hasKey(
    widget.householdId,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasKey,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.data!) {
          return _MissingKeyScreen(
            user: widget.user,
            services: widget.services,
            onRecovered:
                () => setState(
                  () =>
                      _hasKey = widget.services.households.hasKey(
                        widget.householdId,
                      ),
                ),
          );
        }
        return HomeShell(
          user: widget.user,
          householdId: widget.householdId,
          services: widget.services,
          themeController: widget.themeController,
        );
      },
    );
  }
}

class _MissingKeyScreen extends StatelessWidget {
  const _MissingKeyScreen({
    required this.user,
    required this.services,
    required this.onRecovered,
  });

  final AuthUser user;
  final AppServices services;
  final VoidCallback onRecovered;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const HomeWalletLogo(width: 250, height: 74),
                  const SizedBox(height: 30),
                  Icon(
                    Icons.key_off_outlined,
                    size: 68,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Falta la clave de este hogar',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Esto puede ocurrir después de reinstalar la app o cambiar de teléfono. Pide a otro integrante un QR nuevo para recuperar el acceso cifrado.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      final result = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder:
                              (_) => JoinHouseholdScreen(
                                user: user,
                                repository: services.households,
                              ),
                        ),
                      );
                      if (result != null) onRecovered();
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear QR de recuperación'),
                  ),
                  TextButton(
                    onPressed: services.auth.signOut,
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GateError extends StatelessWidget {
  const _GateError({required this.message, required this.onSignOut});

  final String message;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 58,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onSignOut,
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
