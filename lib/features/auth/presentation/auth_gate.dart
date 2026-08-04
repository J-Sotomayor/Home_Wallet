import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/theme_controller.dart';
import '../../households/presentation/household_gate.dart';
import '../data/auth_repository.dart';
import 'auth_flow.dart';
import 'session_lock_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.services,
    required this.themeController,
  });

  final AppServices services;
  final ThemeController themeController;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Stream<AuthUser?> _userStream;
  String? _pendingNotice;

  @override
  void initState() {
    super.initState();
    _userStream = widget.services.auth.watchUser();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services.auth != widget.services.auth) {
      _userStream = widget.services.auth.watchUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('No se pudo iniciar Firebase Authentication.'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          _switchThemeAfterBuild('guest');
          return AuthFlow(
            repository: widget.services.auth,
            notice: _pendingNotice,
            onNoticeShown: () {
              if (mounted) setState(() => _pendingNotice = null);
            },
          );
        }
        _switchThemeAfterBuild(user.uid);
        if (!user.emailVerified) {
          return EmailVerificationScreen(
            user: user,
            repository: widget.services.auth,
            onVerified: _finishEmailVerification,
          );
        }
        return SessionLockGate(
          uid: user.uid,
          service: widget.services.biometricLock,
          onSignOut: widget.services.auth.signOut,
          child: HouseholdGate(
            user: user,
            services: widget.services,
            themeController: widget.themeController,
          ),
        );
      },
    );
  }

  void _switchThemeAfterBuild(String userId) {
    if (widget.themeController.userId == userId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.themeController.switchUser(userId));
    });
  }

  Future<void> _finishEmailVerification() async {
    if (mounted) {
      setState(() {
        _pendingNotice =
            'Correo verificado correctamente. Ya puedes iniciar sesión.';
      });
    }
    await widget.services.auth.signOut();
  }
}
