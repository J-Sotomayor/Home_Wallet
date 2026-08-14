import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../data/household_repository.dart';
import '../domain/household_models.dart';

class HouseholdMembersScreen extends StatefulWidget {
  const HouseholdMembersScreen({
    super.key,
    required this.user,
    required this.household,
    required this.repository,
  });

  final AuthUser user;
  final Household household;
  final HouseholdRepository repository;

  @override
  State<HouseholdMembersScreen> createState() => _HouseholdMembersScreenState();
}

class _HouseholdMembersScreenState extends State<HouseholdMembersScreen> {
  var _busy = false;
  var _leaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integrantes y permisos')),
      body: SafeArea(
        child:
            _leaving
                ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('Saliendo del espacio…'),
                    ],
                  ),
                )
                : StreamBuilder<List<HouseholdMember>>(
                  stream: widget.repository.watchMembers(widget.household.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.group_off_outlined, size: 48),
                              const SizedBox(height: 12),
                              const Text(
                                'Este espacio ya no está disponible para tu cuenta.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () => Navigator.maybePop(context),
                                child: const Text('Volver a mis espacios'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final members =
                        snapshot.data!..sort((a, b) {
                          if (a.roleType == HouseholdRole.owner) return -1;
                          if (b.roleType == HouseholdRole.owner) return 1;
                          return a.displayName.compareTo(b.displayName);
                        });
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.shield_outlined),
                            title: Text(
                              '${widget.household.kind.label} · Permisos',
                            ),
                            subtitle: Text(
                              widget.household.kind == HouseholdKind.family
                                  ? 'El lector (Integrante Jr) puede ver la información, pero no modificarla.'
                                  : 'El propietario administra los permisos de participación.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...members.map((member) => _memberCard(member)),
                        if (!widget.household.isOwner) ...[
                          const SizedBox(height: 22),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _leave,
                            icon: const Icon(Icons.exit_to_app),
                            label: const Text('Salir de este espacio'),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Al salir perderás el acceso a los datos cifrados de este espacio.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    );
                  },
                ),
      ),
    );
  }

  Widget _memberCard(HouseholdMember member) {
    final isMe = member.uid == widget.user.uid;
    final canEdit =
        widget.household.isOwner &&
        !isMe &&
        member.roleType != HouseholdRole.owner;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(_initials(member.displayName))),
        title: Text(member.displayName),
        subtitle: Row(
          children: [
            Text(member.roleType.label),
            if (member.roleType == HouseholdRole.junior) ...[
              const SizedBox(width: 6),
              const Icon(Icons.visibility_outlined, size: 15),
            ],
          ],
        ),
        trailing:
            isMe
                ? const Chip(label: Text('Tú'))
                : canEdit
                ? PopupMenuButton<_MemberAction>(
                  enabled: !_busy,
                  onSelected: (action) {
                    if (action == _MemberAction.role) {
                      _changeRole(member);
                    } else {
                      _remove(member);
                    }
                  },
                  itemBuilder:
                      (_) => const [
                        PopupMenuItem(
                          value: _MemberAction.role,
                          child: ListTile(
                            leading: Icon(Icons.manage_accounts_outlined),
                            title: Text('Cambiar rol'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _MemberAction.remove,
                          child: ListTile(
                            leading: Icon(Icons.person_remove_outlined),
                            title: Text('Eliminar del espacio'),
                          ),
                        ),
                      ],
                )
                : null,
      ),
    );
  }

  Future<void> _changeRole(HouseholdMember member) async {
    final roles = <HouseholdRole>[
      HouseholdRole.admin,
      HouseholdRole.member,
      if (widget.household.kind == HouseholdKind.family) HouseholdRole.junior,
    ];
    final role = await showDialog<HouseholdRole>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: Text('Rol de ${member.displayName}'),
            children:
                roles
                    .map(
                      (value) => RadioListTile<HouseholdRole>(
                        value: value,
                        groupValue: member.roleType,
                        title: Text(value.label),
                        subtitle: Text(_roleDescription(value)),
                        onChanged:
                            (selected) => Navigator.pop(context, selected),
                      ),
                    )
                    .toList(),
          ),
    );
    if (role == null || role == member.roleType || !mounted) return;
    await _run(
      () => widget.repository.updateMemberRole(
        householdId: widget.household.id,
        memberId: member.uid,
        role: role,
      ),
      'Rol actualizado a ${role.label}.',
    );
  }

  Future<void> _remove(HouseholdMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Eliminar a ${member.displayName}'),
            content: const Text(
              'Esta persona perderá inmediatamente el acceso al espacio y necesitará una invitación nueva para volver.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => widget.repository.removeMember(
        householdId: widget.household.id,
        memberId: member.uid,
      ),
      'Integrante eliminado del espacio.',
    );
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Salir del espacio'),
            content: const Text(
              'Perderás el acceso a todos sus movimientos, reportes y claves cifradas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salir'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _leaving = true;
    });
    try {
      await widget.repository.leaveHousehold(widget.household.id);
      if (mounted) Navigator.pop(context);
    } on AppException catch (error) {
      if (mounted) setState(() => _leaving = false);
      _show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    try {
      await action();
      _show(message);
    } on AppException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _roleDescription(HouseholdRole role) => switch (role) {
    HouseholdRole.admin =>
      'Moderador: puede colaborar, gestionar movimientos e invitar.',
    HouseholdRole.member => 'Miembro: puede agregar y editar sus movimientos.',
    HouseholdRole.junior => 'Lector: solo puede consultar la información.',
    HouseholdRole.owner => 'Control total del espacio.',
  };
}

enum _MemberAction { role, remove }

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final result = words.take(2).map((word) => word[0].toUpperCase()).join();
  return result.isEmpty ? 'HW' : result;
}
