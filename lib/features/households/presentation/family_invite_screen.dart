import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../data/household_repository.dart';
import '../domain/household_models.dart';
import '../domain/invitation_payload.dart';

class FamilyInviteScreen extends StatefulWidget {
  const FamilyInviteScreen({
    super.key,
    required this.householdId,
    required this.repository,
  });

  final String householdId;
  final HouseholdRepository repository;

  @override
  State<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends State<FamilyInviteScreen> {
  InvitationPayload? _invitation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    final invitation = _invitation;
    return Scaffold(
      appBar: AppBar(title: const Text('Invitar al espacio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'QR cifrado y de un solo uso',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'La invitación vence en 15 minutos. Compártela únicamente con la persona que deseas agregar.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null)
              _ErrorCard(message: _error!, onRetry: _generate)
            else if (invitation == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: invitation.encode(),
                    version: QrVersions.auto,
                    size: 270,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Válido hasta'),
                  subtitle: Text(_formatExpiry(invitation.expiresAt)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final code = invitation.encode();
                  await Clipboard.setData(ClipboardData(text: code));
                  unawaited(_clearClipboard(code));
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Código seguro copiado temporalmente.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copiar código manual'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('Generar otro QR'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SecurityNotice(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _invitation = null;
      _error = null;
    });
    try {
      final invitation = await widget.repository.createInvitation(
        widget.householdId,
      );
      if (mounted) setState(() => _invitation = invitation);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  String _formatExpiry(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} · ${local.hour}:$minute';
  }

  Future<void> _clearClipboard(String expectedCode) async {
    await Future<void>.delayed(const Duration(seconds: 60));
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == expectedCode) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}

class JoinHouseholdScreen extends StatefulWidget {
  const JoinHouseholdScreen({
    super.key,
    required this.user,
    required this.repository,
    this.onJoined,
  });

  final AuthUser user;
  final HouseholdRepository repository;
  final ValueChanged<String>? onJoined;

  @override
  State<JoinHouseholdScreen> createState() => _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends State<JoinHouseholdScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manualController = TextEditingController();
  bool _processing = false;
  bool _manual = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unirse a un espacio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              _manual ? 'Pega el código seguro' : 'Escanea el QR del espacio',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'La invitación debe estar vigente y solo puede utilizarse una vez.',
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.qr_code_scanner),
                  label: Text('Escanear'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.content_paste),
                  label: Text('Código'),
                ),
              ],
              selected: {_manual},
              onSelectionChanged:
                  _processing
                      ? null
                      : (selection) =>
                          setState(() => _manual = selection.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_manual)
              TextField(
                controller: _manualController,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Código HomeWallet',
                  hintText: 'HW1.…',
                  alignLabelWithHint: true,
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 360,
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      final value = capture.barcodes.firstOrNull?.rawValue;
                      if (value != null) _accept(value);
                    },
                    errorBuilder:
                        (context, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No se pudo abrir la cámara. Revisa el permiso o usa el código manual.\n\n$error',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_manual)
              FilledButton.icon(
                onPressed:
                    _processing ? null : () => _accept(_manualController.text),
                icon:
                    _processing
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.group_add_outlined),
                label: const Text('Validar y unirme'),
              ),
            const SizedBox(height: AppSpacing.md),
            const _SecurityNotice(),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(String rawValue) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    await _controller.stop();
    try {
      final payload = InvitationPayload.decode(rawValue);
      final requestedRole = await _chooseRole(payload.kind);
      if (requestedRole == null) return;
      final householdId = await widget.repository.acceptInvitation(
        rawValue,
        widget.user,
        requestedRole: requestedRole,
      );
      widget.onJoined?.call(householdId);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(householdId);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        if (!_manual) await _controller.start();
      }
    }
  }

  Future<HouseholdRole?> _chooseRole(HouseholdKind kind) async {
    if (kind != HouseholdKind.family) return HouseholdRole.member;
    if (!mounted) return null;
    return showDialog<HouseholdRole>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            icon: const Icon(Icons.family_restroom),
            title: const Text('¿Cómo participarás?'),
            content: const Text(
              'El propietario podrá cambiar este permiso después. Un lector (Integrante Jr) puede consultar, pero no agregar, editar ni eliminar datos.',
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, HouseholdRole.junior),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Lector / Integrante Jr'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, HouseholdRole.member),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Miembro'),
              ),
            ],
          ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'El QR contiene la clave secreta que permite descifrar el espacio. No publiques capturas ni lo envíes a personas desconocidas.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
