import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/theme_controller.dart';
import '../../../app/widgets/homewallet_logo.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/presentation/home_shell.dart';
import '../../onboarding/presentation/category_setup_screen.dart';
import 'household_setup_screen.dart';

class HouseholdGate extends StatefulWidget {
  const HouseholdGate({
    super.key,
    required this.user,
    required this.services,
    required this.themeController,
    required this.onSignOut,
  });

  final AuthUser user;
  final AppServices services;
  final ThemeController themeController;
  final Future<void> Function() onSignOut;

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
        onSignOut: widget.onSignOut,
      );
    }
    return StreamBuilder<String?>(
      stream: _householdStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GateError(
            message: 'No se pudo consultar el espacio activo.',
            onSignOut: widget.onSignOut,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: HomeWalletLoadingView(message: 'Buscando tu espacio'),
          );
        }
        final householdId = snapshot.data ?? _confirmedHouseholdId;
        if (householdId == null || householdId.isEmpty) {
          return HouseholdSetupScreen(
            user: widget.user,
            repository: widget.services.households,
            onSignOut: widget.onSignOut,
            onHouseholdCreated: (value) {
              if (mounted) setState(() => _confirmedHouseholdId = value);
            },
          );
        }
        return _HouseholdKeyGate(
          key: ValueKey(householdId),
          householdId: householdId,
          user: widget.user,
          services: widget.services,
          themeController: widget.themeController,
          onSignOut: widget.onSignOut,
        );
      },
    );
  }
}

class _HouseholdKeyGate extends StatefulWidget {
  const _HouseholdKeyGate({
    super.key,
    required this.householdId,
    required this.user,
    required this.services,
    required this.themeController,
    required this.onSignOut,
  });

  final String householdId;
  final AuthUser user;
  final AppServices services;
  final ThemeController themeController;
  final Future<void> Function() onSignOut;

  @override
  State<_HouseholdKeyGate> createState() => _HouseholdKeyGateState();
}

class _HouseholdKeyGateState extends State<_HouseholdKeyGate> {
  Timer? _automaticRetry;
  late Future<bool> _keyAvailable = _recoverKey();

  Future<bool> _recoverKey() async {
    final available = await widget.services.households.ensureKeyAvailable(
      widget.householdId,
    );
    if (!available && mounted) {
      _automaticRetry?.cancel();
      _automaticRetry = Timer(const Duration(seconds: 10), _retryRecovery);
    }
    return available;
  }

  void _retryRecovery() {
    _automaticRetry?.cancel();
    setState(() {
      _keyAvailable = _recoverKey();
    });
  }

  @override
  void dispose() {
    _automaticRetry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _keyAvailable,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: HomeWalletLoadingView(message: 'Abriendo tu espacio'),
          );
        }
        if (snapshot.data != true) {
          return _MissingKeyScreen(
            onRetry: _retryRecovery,
            onSignOut: widget.onSignOut,
          );
        }
        return HomeShell(
          user: widget.user,
          householdId: widget.householdId,
          services: widget.services,
          themeController: widget.themeController,
          onSignOut: widget.onSignOut,
        );
      },
    );
  }
}

class _MissingKeyScreen extends StatelessWidget {
  const _MissingKeyScreen({required this.onRetry, required this.onSignOut});

  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

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
                  const HomeWalletLogo(width: 220, height: 200),
                  const SizedBox(height: 30),
                  Icon(
                    Icons.phonelink_lock_outlined,
                    size: 68,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Sincronizando tu espacio',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tu cuenta ya inició sesión correctamente. Este espacio es antiguo y todavía necesita que un teléfono que conserve sus datos envíe la copia protegida.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.phone_android_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Abre HomeWallet una vez en cualquier teléfono donde este espacio ya funcione. La migración será automática y este dispositivo volverá a intentar la sincronización sin códigos.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar ahora'),
                  ),
                  TextButton(
                    onPressed: onSignOut,
                    child: const Text('Usar otra cuenta'),
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
