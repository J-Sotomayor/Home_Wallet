import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/services/app_services.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../../legal/presentation/legal_screen.dart';
import 'profile_photo_crop_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.householdId,
    required this.services,
  });

  final AuthUser user;
  final String householdId;
  final AppServices services;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  Uint8List? _photoBytes;
  String? _photoExtension;
  bool _busy = false;
  DateTime? _scheduledDeletionAt;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.displayName);
    _phoneController = TextEditingController(text: widget.user.phoneNumber);
    _scheduledDeletionAt = widget.user.deletionScheduledFor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider =
        _photoBytes != null
            ? MemoryImage(_photoBytes!) as ImageProvider
            : widget.user.photoUrl?.isNotEmpty == true
            ? NetworkImage(widget.user.photoUrl!)
            : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: AppColors.blushPinkLight,
                        foregroundColor: AppColors.blushPinkDark,
                        backgroundImage: imageProvider,
                        child:
                            imageProvider == null
                                ? Text(
                                  _initials(_nameController.text),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                                : null,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: IconButton.filled(
                          tooltip: 'Cambiar y ajustar foto',
                          onPressed: _busy ? null : _pickPhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text.trim().isEmpty
                              ? 'Tu perfil'
                              : _nameController.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.user.email,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Toca la cámara para recortar, acercar y centrar.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Información personal',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      enabled: !_busy,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nombre y apellido',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Correo electrónico'),
                      subtitle: Text(widget.user.email),
                      trailing: const Icon(Icons.lock_outline, size: 18),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneController,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Celular',
                        hintText: '+593 99 123 4567',
                        prefixIcon: Icon(Icons.phone_android_outlined),
                        helperText:
                            'Es un dato de contacto; no cambia tu acceso.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _saveProfile,
              icon:
                  _busy
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_outlined),
              label: const Text('Guardar cambios'),
            ),
            const SizedBox(height: 22),
            Text('Seguridad', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Cambiar contraseña'),
                subtitle: const Text('Confirma primero tu contraseña actual'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _changePassword,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Privacidad y cuenta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Términos y privacidad'),
                    subtitle: const Text('Consulta los acuerdos vigentes'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LegalScreen(),
                          ),
                        ),
                  ),
                  const Divider(height: 1),
                  if (_scheduledDeletionAt == null)
                    ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Eliminar mi cuenta'),
                      subtitle: const Text(
                        'Se programa con tres días hábiles para cancelarla',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _requestDeletion,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.schedule_outlined,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Borrado programado para ${DateFormat('dd/MM/yyyy · HH:mm').format(_scheduledDeletionAt!.toLocal())}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _cancelDeletion,
                            icon: const Icon(Icons.undo),
                            label: const Text('Cancelar eliminación'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => ProfilePhotoCropScreen(image: bytes),
      ),
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _photoBytes = cropped;
      _photoExtension = image.name.split('.').last;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Foto ajustada. Guarda los cambios para subirla.'),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      final name = _nameController.text.trim();
      await widget.services.auth.updateProfile(
        displayName: name,
        phoneNumber: _phoneController.text,
        photoBytes: _photoBytes,
        photoExtension: _photoExtension,
      );
      await widget.services.households.updateMemberDisplayName(
        householdId: widget.householdId,
        uid: widget.user.uid,
        displayName: name,
      );
      if (mounted) {
        final uploadedPhoto = _photoBytes != null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uploadedPhoto
                  ? 'Foto cargada y perfil actualizado correctamente.'
                  : 'Perfil actualizado correctamente.',
            ),
          ),
        );
      }
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final input = await showDialog<_PasswordInput>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.services.auth.changePassword(
        currentPassword: input.currentPassword,
        newPassword: input.newPassword,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')),
        );
      }
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Programar eliminación'),
            content: const Text(
              'La cuenta y sus datos se eliminarán después de tres días hábiles. Hasta entonces puedes cancelar desde esta misma pantalla.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Conservar cuenta'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Programar borrado'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final date = await widget.services.auth.requestAccountDeletion();
      if (mounted) {
        setState(() => _scheduledDeletionAt = date);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Eliminación programada. Puedes cancelarla durante el plazo.',
            ),
          ),
        );
      }
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDeletion() async {
    setState(() => _busy = true);
    try {
      await widget.services.auth.cancelAccountDeletion();
      if (mounted) {
        setState(() => _scheduledDeletionAt = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La eliminación fue cancelada.')),
        );
      }
    } on AppException catch (error) {
      _showError(error.message);
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

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentController,
              obscureText: _obscure,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newController,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Confirmar nueva contraseña',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_newController.text.length < 8 ||
                _newController.text != _confirmController.text ||
                _currentController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Revisa las contraseñas; la nueva requiere 8 caracteres.',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _PasswordInput(
                currentPassword: _currentController.text,
                newPassword: _newController.text,
              ),
            );
          },
          child: const Text('Actualizar'),
        ),
      ],
    );
  }
}

class _PasswordInput {
  const _PasswordInput({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;
}

String _initials(String name) {
  final values = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty);
  final initials = values.take(2).map((value) => value[0].toUpperCase()).join();
  return initials.isEmpty ? 'HW' : initials;
}
