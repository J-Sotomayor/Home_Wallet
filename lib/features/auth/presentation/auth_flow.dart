import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/widgets/homewallet_logo.dart';
import '../../../core/errors/app_exception.dart';
import '../../legal/presentation/legal_screen.dart';
import '../data/auth_repository.dart';

enum _AuthStep { login, register, recovery }

class AuthFlow extends StatefulWidget {
  const AuthFlow({
    super.key,
    required this.repository,
    this.notice,
    this.onNoticeShown,
  });

  final AuthRepository repository;
  final String? notice;
  final VoidCallback? onNoticeShown;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  _AuthStep _step = _AuthStep.login;

  @override
  void initState() {
    super.initState();
    if (widget.notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNotice());
    }
  }

  void _showNotice() {
    if (!mounted || widget.notice == null) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: scheme.primaryContainer,
        content: Row(
          children: [
            Icon(Icons.verified, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                widget.notice!,
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
    widget.onNoticeShown?.call();
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
    _AuthStep.login => LoginScreen(
      repository: widget.repository,
      onRegister: () => setState(() => _step = _AuthStep.register),
      onForgotPassword: () => setState(() => _step = _AuthStep.recovery),
    ),
    _AuthStep.register => RegisterScreen(
      repository: widget.repository,
      onBack: () => setState(() => _step = _AuthStep.login),
    ),
    _AuthStep.recovery => PasswordRecoveryScreen(
      repository: widget.repository,
      onBack: () => setState(() => _step = _AuthStep.login),
    ),
  };
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repository,
    required this.onRegister,
    required this.onForgotPassword,
  });

  final AuthRepository repository;
  final VoidCallback onRegister;
  final VoidCallback onForgotPassword;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: HomeWalletLogo(width: 290, height: 86)),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Bienvenida a tu espacio financiero',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Accede con tu cuenta.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            TextFormField(
              key: const Key('login_email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              validator: _emailValidator,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('login_password'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              enableSuggestions: false,
              validator:
                  (value) =>
                      value == null || value.isEmpty
                          ? 'Ingresa tu contraseña.'
                          : null,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip:
                      _obscurePassword
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                  onPressed:
                      () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : widget.onForgotPassword,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            FilledButton.icon(
              key: const Key('login_submit'),
              onPressed: _busy ? null : _submit,
              icon:
                  _busy
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.login),
              label: const Text('Iniciar sesión'),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _AuthDivider(),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              key: const Key('login_google'),
              onPressed: _busy ? null : _signInWithGoogle,
              icon: const _GoogleIcon(),
              label: const Text('Continuar con Google'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('¿Aún no tienes cuenta?'),
                TextButton(
                  onPressed: _busy ? null : widget.onRegister,
                  child: const Text('Crear cuenta'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      await widget.repository.signInWithGoogle();
    } on AppException catch (error) {
      if (error.code != 'canceled') _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.repository,
    required this.onBack,
  });

  final AuthRepository repository;
  final VoidCallback onBack;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _busy = false;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      onBack: widget.onBack,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: HomeWalletLogo(width: 250, height: 74)),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Crea tu cuenta',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tu correo debe verificarse antes de acceder a datos financieros.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            CheckboxListTile(
              key: const Key('accept_terms'),
              contentPadding: EdgeInsets.zero,
              value: _acceptedTerms,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged:
                  _busy
                      ? null
                      : (value) =>
                          setState(() => _acceptedTerms = value ?? false),
              title: const Text(
                'Acepto los términos y la política de privacidad',
              ),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _openTerms,
                  child: const Text('Leer términos completos'),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (value) {
                final length = value?.trim().length ?? 0;
                return length < 2 || length > 60
                    ? 'Ingresa un nombre de 2 a 60 caracteres.'
                    : null;
              },
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('register_email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.newUsername],
              validator: _emailValidator,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('register_password'),
              controller: _passwordController,
              obscureText: true,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              validator: _passwordValidator,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: Icon(Icons.lock_outline),
                helperText:
                    'Mínimo 10 caracteres, mayúscula, minúscula y número.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirmationController,
              obscureText: true,
              enableSuggestions: false,
              validator:
                  (value) =>
                      value != _passwordController.text
                          ? 'Las contraseñas no coinciden.'
                          : null,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
                prefixIcon: Icon(Icons.lock_reset_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('register_submit'),
              onPressed: _busy ? null : _submit,
              icon:
                  _busy
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.person_add_alt_1),
              label: const Text('Crear cuenta'),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _AuthDivider(),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              key: const Key('register_google'),
              onPressed: _busy ? null : _registerWithGoogle,
              icon: const _GoogleIcon(),
              label: const Text('Registrarme con Google'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_ensureAccepted()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.register(
        displayName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerWithGoogle() async {
    if (!_ensureAccepted()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.signInWithGoogle();
      await widget.repository.acceptTerms();
    } on AppException catch (error) {
      if (error.code != 'canceled') _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _ensureAccepted() {
    if (_acceptedTerms) return true;
    _showError('Debes aceptar los términos y la política de privacidad.');
    return false;
  }

  void _openTerms() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen()));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    required this.repository,
    required this.onBack,
  });

  final AuthRepository repository;
  final VoidCallback onBack;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      onBack: widget.onBack,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: HomeWalletLogo(width: 250, height: 74)),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Recupera tu contraseña',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _sent
                  ? 'Si existe una cuenta con ese correo, recibirás un enlace seguro.'
                  : 'Firebase enviará un enlace de un solo uso a tu correo.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextFormField(
              key: const Key('recovery_email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              validator: _emailValidator,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('recovery_submit'),
              onPressed: _busy ? null : _submit,
              icon:
                  _busy
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.send_outlined),
              label: const Text('Enviar instrucciones'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.sendPasswordReset(_emailController.text);
      if (mounted) setState(() => _sent = true);
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

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.repository,
    required this.onVerified,
  });

  final AuthUser user;
  final AuthRepository repository;
  final Future<void> Function() onVerified;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  Timer? _cooldownTimer;
  bool _checking = false;
  bool _manualChecking = false;
  bool _resending = false;
  bool _completed = false;
  int _resendSeconds = 0;
  String _statusMessage =
      'Revisa la bandeja de entrada y también correo no deseado o spam.';
  bool _statusIsError = false;

  bool get _resendDisabled => _resending || _completed || _resendSeconds > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkVerification());
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_checkVerification());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkVerification());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: HomeWalletLogo(width: 250, height: 74)),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.primary,
              child: const Icon(Icons.mark_email_read_outlined, size: 42),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Verifica tu correo',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Enviamos un enlace a ${widget.user.email}. Ábrelo y vuelve a HomeWallet.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.sync, color: scheme.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Comprobamos automáticamente la verificación al regresar a la app.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedContainer(
            key: const Key('verification_status'),
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color:
                  _statusIsError
                      ? scheme.errorContainer
                      : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _statusIsError
                      ? Icons.error_outline
                      : Icons.info_outline_rounded,
                  color:
                      _statusIsError
                          ? scheme.onErrorContainer
                          : scheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color:
                          _statusIsError
                              ? scheme.onErrorContainer
                              : scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            key: const Key('verification_continue'),
            onPressed:
                _manualChecking || _completed
                    ? null
                    : () => _checkVerification(
                      announceWhenPending: true,
                      showProgress: true,
                    ),
            icon:
                _manualChecking
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.verified_outlined),
            label: Text(
              _manualChecking ? 'Comprobando…' : 'Ya verifiqué mi correo',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            key: const Key('verification_resend'),
            onPressed: _resendDisabled ? null : _resend,
            icon:
                _resending
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.forward_to_inbox_outlined),
            label: Text(
              _resending
                  ? 'Enviando…'
                  : _resendSeconds > 0
                  ? 'Podrás reenviar en $_resendSeconds s'
                  : 'Reenviar enlace',
            ),
          ),
          TextButton(
            key: const Key('verification_other_account'),
            onPressed: _completed ? null : widget.repository.signOut,
            child: const Text('Usar otra cuenta'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkVerification({
    bool announceWhenPending = false,
    bool showProgress = false,
  }) async {
    if (_checking || _completed || !mounted) return;
    setState(() {
      _checking = true;
      if (showProgress) _manualChecking = true;
    });
    try {
      final verified = await widget.repository.reloadEmailVerification();
      if (verified) {
        _completed = true;
        _pollTimer?.cancel();
        await widget.onVerified();
      } else if (announceWhenPending && mounted) {
        setState(() {
          _statusIsError = false;
          _statusMessage =
              'Aún no aparece verificado. Si acabas de abrir el enlace, espera unos segundos y vuelve a intentarlo.';
        });
      }
    } on AppException catch (error) {
      if (announceWhenPending) _setStatus(error.message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          if (showProgress) _manualChecking = false;
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await widget.repository.sendEmailVerification();
      if (!mounted) return;
      _setStatus(
        'Nuevo enlace enviado a ${widget.user.email}. Revisa también spam o correo no deseado.',
      );
      _startResendCooldown();
    } on AppException catch (error) {
      _setStatus(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'o',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDADCE0)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child, this.onBack});

  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          onBack == null
              ? null
              : AppBar(
                leading: IconButton(
                  tooltip: 'Volver',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

String? _emailValidator(String? value) {
  final email = value?.trim() ?? '';
  final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  return valid ? null : 'Ingresa un correo electrónico válido.';
}

String? _passwordValidator(String? value) {
  final password = value ?? '';
  final valid =
      password.length >= 10 &&
      RegExp('[A-Z]').hasMatch(password) &&
      RegExp('[a-z]').hasMatch(password) &&
      RegExp('[0-9]').hasMatch(password);
  return valid ? null : 'Usa 10 caracteres con mayúscula, minúscula y número.';
}
