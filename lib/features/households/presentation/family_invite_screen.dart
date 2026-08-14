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
    required this.householdKind,
    required this.repository,
  });

  final String householdId;
  final HouseholdKind householdKind;
  final HouseholdRepository repository;

  @override
  State<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends State<FamilyInviteScreen> {
  InvitationPayload? _invitation;
  String? _error;
  bool _revoked = false;
  bool _working = false;
  HouseholdRole _invitedRole = HouseholdRole.member;

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
            if (widget.householdKind == HouseholdKind.family) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Rol de la persona invitada',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<HouseholdRole>(
                segments: const [
                  ButtonSegment(
                    value: HouseholdRole.member,
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Miembro'),
                  ),
                  ButtonSegment(
                    value: HouseholdRole.junior,
                    icon: Icon(Icons.visibility_outlined),
                    label: Text('Lector / Jr.'),
                  ),
                ],
                selected: {_invitedRole},
                onSelectionChanged:
                    invitation == null || _working
                        ? null
                        : (selection) {
                          setState(() => _invitedRole = selection.first);
                          _generate();
                        },
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'El rol queda protegido en la invitación y no puede elegirlo quien la recibe.',
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (_error != null)
              _ErrorCard(message: _error!, onRetry: _generate)
            else if (_revoked)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.link_off_outlined, size: 42),
                      const SizedBox(height: 10),
                      const Text(
                        'La invitación fue revocada y ya no puede utilizarse.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Generar nueva invitación'),
                      ),
                    ],
                  ),
                ),
              )
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
                onPressed: _working ? null : _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('Generar otro QR'),
              ),
              TextButton.icon(
                onPressed: _working ? null : _revoke,
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('Revocar esta invitación'),
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
    if (_working) return;
    setState(() {
      _working = true;
      _invitation = null;
      _error = null;
      _revoked = false;
    });
    try {
      final invitation = await widget.repository.createInvitation(
        widget.householdId,
        invitedRole: _invitedRole,
      );
      if (mounted) setState(() => _invitation = invitation);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revoke() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.repository.revokeInvitation(widget.householdId);
      if (mounted) {
        setState(() {
          _invitation = null;
          _error = null;
          _revoked = true;
        });
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
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
      final householdId = await widget.repository.acceptInvitation(
        rawValue,
        widget.user,
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
