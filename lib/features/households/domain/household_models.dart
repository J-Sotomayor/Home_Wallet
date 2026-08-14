enum HouseholdKind {
  individual,
  family,
  couple,
  group;

  String get label => switch (this) {
    HouseholdKind.individual => 'Individual',
    HouseholdKind.family => 'Familia',
    HouseholdKind.couple => 'Pareja',
    HouseholdKind.group => 'Grupo',
  };

  static HouseholdKind parse(Object? value) => switch (value) {
    'individual' => HouseholdKind.individual,
    'couple' => HouseholdKind.couple,
    'group' => HouseholdKind.group,
    _ => HouseholdKind.family,
  };
}

enum HouseholdRole {
  owner,
  admin,
  member,
  junior;

  String get label => switch (this) {
    HouseholdRole.owner => 'Propietario',
    HouseholdRole.admin => 'Moderador',
    HouseholdRole.member => 'Miembro',
    HouseholdRole.junior => 'Lector (Integrante Jr)',
  };

  bool get canManage => this == owner || this == admin;
  bool get canContribute => this != junior;

  static HouseholdRole parse(Object? value) => switch (value) {
    'owner' => HouseholdRole.owner,
    'admin' => HouseholdRole.admin,
    'junior' => HouseholdRole.junior,
    _ => HouseholdRole.member,
  };
}

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.role,
    this.kind = HouseholdKind.family,
    this.hasLocalKey = true,
  });

  final String id;
  final String name;
  final int memberCount;
  final String role;
  final HouseholdKind kind;
  final bool hasLocalKey;

  HouseholdRole get roleType => HouseholdRole.parse(role);
  bool get canManage => roleType.canManage;
  bool get canContribute => roleType.canContribute;
  bool get isOwner => roleType == HouseholdRole.owner;
  bool get isIndividual => kind == HouseholdKind.individual;
  bool get isCollaborative => !isIndividual;
  bool get canInvite =>
      canManage &&
      isCollaborative &&
      !(kind == HouseholdKind.couple && memberCount >= 2);
}

class HouseholdMember {
  const HouseholdMember({
    required this.uid,
    required this.displayName,
    required this.role,
    this.monthlyIncomeMinor = 0,
  });

  final String uid;
  final String displayName;
  final String role;
  final int monthlyIncomeMinor;

  HouseholdRole get roleType => HouseholdRole.parse(role);
  bool get hasMonthlyIncome => monthlyIncomeMinor > 0;
}
