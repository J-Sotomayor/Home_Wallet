import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/widgets/homewallet_logo.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/biometric_lock_service.dart';

class SessionLockGate extends StatefulWidget {
  const SessionLockGate({
    super.key,
    required this.uid,
    required this.service,
    required this.onSignOut,
    required this.child,
  });

  final String uid;
  final BiometricLockService service;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  State<SessionLockGate> createState() => _SessionLockGateState();
}

class _SessionLockGateState extends State<SessionLockGate>
    with WidgetsBindingObserver {
  bool _locked = true;
  bool _authenticating = false;
  String? _error;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final elapsed = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (elapsed >= const Duration(seconds: 30)) {
        setState(() => _locked = true);
        unawaited(_unlock());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const HomeWalletLogo(width: 220, height: 200),
                  const SizedBox(height: 36),
                  Icon(
                    Icons.fingerprint,
                    size: 84,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'HomeWallet está bloqueado',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Usa la huella, el rostro o el bloqueo seguro de este dispositivo.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _authenticating ? null : _unlock,
                      icon:
                          _authenticating
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.lock_open),
                      label: const Text('Desbloquear'),
                    ),
                  ),
                  TextButton(
                    onPressed: _authenticating ? null : widget.onSignOut,
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

  Future<void> _unlock() async {
    if (_authenticating || !mounted) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final unlocked = await widget.service.unlock(widget.uid);
      if (mounted) {
        setState(() {
          _locked = !unlocked;
          if (!unlocked) _error = 'No se confirmó la identidad.';
        });
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }
}
