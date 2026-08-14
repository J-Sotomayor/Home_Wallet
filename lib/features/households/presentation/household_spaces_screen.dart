import 'package:flutter/material.dart';

import '../../../app/widgets/app_page_header.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../data/household_repository.dart';
import '../domain/household_models.dart';
import 'family_invite_screen.dart';

enum HouseholdSpacesAction { createShared, join }

class HouseholdSpacesScreen extends StatefulWidget {
  const HouseholdSpacesScreen({
    super.key,
    required this.user,
    required this.currentHouseholdId,
    required this.repository,
    this.initialAction,
  });

  final AuthUser user;
  final String currentHouseholdId;
  final HouseholdRepository repository;
  final HouseholdSpacesAction? initialAction;

  @override
  State<HouseholdSpacesScreen> createState() => _HouseholdSpacesScreenState();
}

class _HouseholdSpacesScreenState extends State<HouseholdSpacesScreen> {
  late Future<List<Household>> _households;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (widget.initialAction!) {
          case HouseholdSpacesAction.createShared:
            _createSharedSpace();
          case HouseholdSpacesAction.join:
            _joinSpace();
        }
      });
    }
  }

  void _reload() {
    _households = widget.repository.listHouseholds(widget.user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis espacios')),
      body: SafeArea(
        child: FutureBuilder<List<Household>>(
          future: _households,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                message: _errorText(snapshot.error),
                actionLabel: 'Reintentar',
                onAction: () => setState(_reload),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final households = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                const AppPageHeader(
                  icon: Icons.space_dashboard_outlined,
                  title: 'Tus espacios',
                  subtitle:
                      'Cada espacio conserva sus propios movimientos y su propia clave de cifrado.',
                ),
                const SizedBox(height: 16),
                ...households.map(_spaceCard),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    key: const Key('create_shared_space'),
                    enabled: !_busy,
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Crear espacio compartido'),
                    subtitle: const Text(
                      'Crea una Pareja, Familia o Grupo sin compartir tu historial personal.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _createSharedSpace,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    key: const Key('join_shared_space'),
                    enabled: !_busy,
                    leading: const Icon(Icons.qr_code_scanner),
                    title: const Text('Unirse a un espacio'),
                    subtitle: const Text(
                      'Escanea o ingresa el código de invitación.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _joinSpace,
                  ),
                ),
                const SizedBox(height: 14),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: Text('Tus datos no se mezclan'),
                    subtitle: Text(
                      'Para registrar algo personal o compartido, activa primero el espacio correspondiente.',
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _spaceCard(Household household) {
    final active = household.id == widget.currentHouseholdId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: active ? Theme.of(context).colorScheme.primaryContainer : null,
        child: ListTile(
          key: Key('space_${household.id}'),
          enabled: !_busy,
          leading: Icon(_kindIcon(household.kind)),
          title: Text(household.name),
          subtitle: Text(
            household.hasLocalKey
                ? '${household.kind.label} · ${household.memberCount} ${household.memberCount == 1 ? 'integrante' : 'integrantes'}'
                : '${household.kind.label} · requiere recuperar la clave',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (household.isOwner)
                IconButton(
                  key: Key('change_space_kind_${household.id}'),
                  tooltip:
                      household.isIndividual
                          ? 'Crear espacio compartido'
                          : 'Cambiar tipo de espacio',
                  onPressed:
                      _busy
                          ? null
                          : household.isIndividual
                          ? _createSharedSpace
                          : () => _changeKind(household),
                  icon: Icon(
                    household.isIndividual
                        ? Icons.group_add_outlined
                        : Icons.edit_outlined,
                  ),
                ),
              if (active)
                const Chip(label: Text('Activo'))
              else
                const Icon(Icons.chevron_right),
            ],
          ),
          onTap: active ? null : () => _activate(household.id),
        ),
      ),
    );
  }

  Future<void> _activate(String householdId) async {
    setState(() => _busy = true);
    try {
      await widget.repository.setActiveHousehold(widget.user.uid, householdId);
      if (mounted) Navigator.pop(context, householdId);
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeKind(Household household) async {
    var hasJunior = false;
    try {
      final members = await widget.repository.watchMembers(household.id).first;
      hasJunior = members.any(
        (member) => member.roleType == HouseholdRole.junior,
      );
    } on Object {
      // El backend vuelve a validar todas las restricciones antes de guardar.
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<HouseholdKind>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder:
          (context) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppPageHeader(
                  icon: Icons.home_outlined,
                  title: 'Tipo de espacio',
                  subtitle:
                      'El nombre y los movimientos no cambiarán. Individual requiere exactamente una persona.',
                ),
                const SizedBox(height: 14),
                for (final kind in HouseholdKind.values)
                  Builder(
                    builder: (context) {
                      final enabled =
                          (kind != HouseholdKind.individual ||
                              household.memberCount == 1) &&
                          (kind != HouseholdKind.couple ||
                              household.memberCount <= 2) &&
                          (kind == HouseholdKind.family || !hasJunior);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          color:
                              household.kind == kind
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer
                                  : null,
                          child: ListTile(
                            key: Key('change_household_kind_${kind.name}'),
                            leading: Icon(_kindIcon(kind)),
                            title: Text(kind.label),
                            subtitle:
                                enabled
                                    ? null
                                    : Text(
                                      kind != HouseholdKind.family && hasJunior
                                          ? 'Cambia primero el rol de Integrante Jr.'
                                          : kind == HouseholdKind.individual
                                          ? 'Retira primero a los demás integrantes.'
                                          : 'Pareja admite como máximo dos integrantes.',
                                    ),
                            trailing:
                                household.kind == kind
                                    ? Icon(
                                      Icons.check_circle,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    )
                                    : const Icon(Icons.chevron_right),
                            enabled: enabled,
                            onTap:
                                enabled
                                    ? () => Navigator.pop(context, kind)
                                    : null,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
    );
    if (selected == null || selected == household.kind || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.updateHouseholdKind(
        householdId: household.id,
        kind: selected,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tipo de espacio actualizado a ${selected.label}.'),
        ),
      );
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createSharedSpace() async {
    final kind = await showModalBottomSheet<HouseholdKind>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder:
          (context) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppPageHeader(
                  icon: Icons.group_add_outlined,
                  title: 'Nuevo espacio compartido',
                  subtitle:
                      'Tu espacio Individual y sus movimientos permanecerán separados.',
                ),
                const SizedBox(height: 14),
                for (final value in const [
                  HouseholdKind.couple,
                  HouseholdKind.family,
                  HouseholdKind.group,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(_kindIcon(value)),
                        title: Text(value.label),
                        subtitle: Text(_kindDescription(value)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, value),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    );
    if (kind == null || !mounted) return;
    final name = await _askName(kind);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final householdId = await widget.repository.createHousehold(
        name,
        widget.user,
        kind: kind,
      );
      if (mounted) Navigator.pop(context, householdId);
    } on AppException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(HouseholdKind kind) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _SpaceNameDialog(kind: kind),
    );
  }

  Future<void> _joinSpace() async {
    final householdId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => JoinHouseholdScreen(
              user: widget.user,
              repository: widget.repository,
            ),
      ),
    );
    if (householdId != null && mounted) Navigator.pop(context, householdId);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SpaceNameDialog extends StatefulWidget {
  const _SpaceNameDialog({required this.kind});

  final HouseholdKind kind;

  @override
  State<_SpaceNameDialog> createState() => _SpaceNameDialogState();
}

class _SpaceNameDialogState extends State<_SpaceNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: _defaultName(widget.kind),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nombre de ${widget.kind.label.toLowerCase()}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Nombre del espacio',
          hintText: 'Ej. Casa, Viaje o Compañeros',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.length >= 2) Navigator.pop(context, value);
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

IconData _kindIcon(HouseholdKind kind) => switch (kind) {
  HouseholdKind.individual => Icons.person_outline,
  HouseholdKind.couple => Icons.favorite_outline,
  HouseholdKind.family => Icons.family_restroom,
  HouseholdKind.group => Icons.groups_outlined,
};

String _kindDescription(HouseholdKind kind) => switch (kind) {
  HouseholdKind.couple => 'Hasta dos integrantes.',
  HouseholdKind.family => 'Incluye el rol Lector / Integrante Jr.',
  HouseholdKind.group => 'Para amigos, compañeros o equipos.',
  HouseholdKind.individual => 'Un espacio privado para una sola persona.',
};

String _defaultName(HouseholdKind kind) => switch (kind) {
  HouseholdKind.couple => 'Nuestra pareja',
  HouseholdKind.family => 'Mi familia',
  HouseholdKind.group => 'Mi grupo',
  HouseholdKind.individual => 'Mi espacio',
};

String _errorText(Object? error) => switch (error) {
  AppException(:final message) => message,
  _ => 'No se pudieron cargar tus espacios.',
};
