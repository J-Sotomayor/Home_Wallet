import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/core/security/household_crypto_service.dart';
import 'package:homewallet/features/households/domain/invitation_payload.dart';

void main() {
  test('AES-256-GCM cifra y descifra el contenido financiero', () async {
    final service = HouseholdCryptoService();
    final key = await service.generateKey();
    final encrypted = await service.encryptJson(
      value: {'amountMinor': 12345, 'description': 'Dato privado'},
      keyBytes: key,
      context: 'households/household-12345678/transactions/record-12345678',
    );

    expect(encrypted['alg'], 'A256GCM');
    expect(encrypted.toString(), isNot(contains('Dato privado')));
    expect(encrypted.toString(), isNot(contains('12345')));

    final clear = await service.decryptJson(
      payload: encrypted,
      keyBytes: key,
      context: 'households/household-12345678/transactions/record-12345678',
    );
    expect(clear['amountMinor'], 12345);
    expect(clear['description'], 'Dato privado');
  });

  test('AES-GCM rechaza datos manipulados', () async {
    final service = HouseholdCryptoService();
    final key = await service.generateKey();
    final encrypted = await service.encryptJson(
      value: {'value': 'privado'},
      keyBytes: key,
      context: 'contexto-autenticado',
    );
    encrypted['ct'] = '${encrypted['ct']}A';

    expect(
      () => service.decryptJson(
        payload: encrypted,
        keyBytes: key,
        context: 'contexto-autenticado',
      ),
      throwsA(anything),
    );
  });

  test('la invitación QR conserva hogar, token, clave y vencimiento', () {
    final expires = DateTime.now().toUtc().add(const Duration(minutes: 15));
    final invitation = InvitationPayload(
      householdId: 'household-12345678',
      invitationId: 'invitation-12345678',
      token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
      keyBytes: List<int>.generate(32, (index) => index),
      expiresAt: expires,
    );

    final decoded = InvitationPayload.decode(invitation.encode());

    expect(decoded.householdId, invitation.householdId);
    expect(decoded.invitationId, invitation.invitationId);
    expect(decoded.token, invitation.token);
    expect(decoded.keyBytes, invitation.keyBytes);
    expect(
      decoded.expiresAt.millisecondsSinceEpoch,
      invitation.expiresAt.millisecondsSinceEpoch,
    );
  });

  test('rechaza códigos que no sean de HomeWallet', () {
    expect(
      () => InvitationPayload.decode('https://sitio-malicioso.example/join'),
      throwsFormatException,
    );
  });
}
