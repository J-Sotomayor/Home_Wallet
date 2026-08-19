import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/households/domain/household_models.dart';
import 'package:homewallet/features/households/domain/invitation_payload.dart';

void main() {
  test('QR payload preserves the space kind and assigned role', () {
    final invitation = InvitationPayload(
      householdId: 'household_123',
      invitationId: 'invitation_123',
      token: 'a' * 32,
      keyBytes: List<int>.generate(32, (index) => index),
      expiresAt: DateTime.utc(2026, 8, 15, 20),
      kind: HouseholdKind.family,
      role: HouseholdRole.junior,
      shortCode: '48210736',
    );

    final decoded = InvitationPayload.decode(invitation.encode());

    expect(decoded.householdId, invitation.householdId);
    expect(decoded.kind, HouseholdKind.family);
    expect(decoded.role, HouseholdRole.junior);
    expect(decoded.keyBytes, invitation.keyBytes);
  });
}
