import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/households/domain/household_models.dart';

void main() {
  test('exposes the four supported space kinds', () {
    expect(HouseholdKind.values, <HouseholdKind>[
      HouseholdKind.individual,
      HouseholdKind.family,
      HouseholdKind.couple,
      HouseholdKind.group,
    ]);
  });

  test('an Individual space is private and non-collaborative', () {
    const space = Household(
      id: 'personal',
      name: 'Mi espacio',
      memberCount: 1,
      role: 'owner',
      kind: HouseholdKind.individual,
    );

    expect(space.isIndividual, isTrue);
    expect(space.isCollaborative, isFalse);
  });

  test('role capabilities match the product permission matrix', () {
    expect(HouseholdRole.owner.canManage, isTrue);
    expect(HouseholdRole.admin.canManage, isTrue);
    expect(HouseholdRole.member.canManage, isFalse);
    expect(HouseholdRole.junior.canManage, isFalse);

    expect(HouseholdRole.owner.canContribute, isTrue);
    expect(HouseholdRole.admin.canContribute, isTrue);
    expect(HouseholdRole.member.canContribute, isTrue);
    expect(HouseholdRole.junior.canContribute, isFalse);
  });

  test('a full Couple shows members instead of inviting again', () {
    const availableCouple = Household(
      id: 'couple-open',
      name: 'Pareja',
      memberCount: 1,
      role: 'owner',
      kind: HouseholdKind.couple,
    );
    const fullCouple = Household(
      id: 'couple-full',
      name: 'Pareja completa',
      memberCount: 2,
      role: 'owner',
      kind: HouseholdKind.couple,
    );
    const fullCoupleMember = Household(
      id: 'couple-member',
      name: 'Pareja completa',
      memberCount: 2,
      role: 'member',
      kind: HouseholdKind.couple,
    );

    expect(availableCouple.canInvite, isTrue);
    expect(fullCouple.canInvite, isFalse);
    expect(fullCoupleMember.canInvite, isFalse);
  });

  test('a member exposes the encrypted monthly income when configured', () {
    const pending = HouseholdMember(
      uid: 'one',
      displayName: 'Persona uno',
      role: 'member',
    );
    const configured = HouseholdMember(
      uid: 'two',
      displayName: 'Persona dos',
      role: 'member',
      monthlyIncomeMinor: 120000,
    );

    expect(pending.hasMonthlyIncome, isFalse);
    expect(configured.hasMonthlyIncome, isTrue);
    expect(configured.monthlyIncomeMinor, 120000);
  });
}
