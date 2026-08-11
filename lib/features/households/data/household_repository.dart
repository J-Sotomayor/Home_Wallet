import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/firebase_error_mapper.dart';
import '../../../core/security/household_crypto_service.dart';
import '../../../core/security/secure_key_store.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/household_models.dart';
import '../domain/invitation_payload.dart';

abstract interface class HouseholdRepository {
  Stream<String?> watchActiveHouseholdId(String uid);
  Stream<Household> watchHousehold(String householdId, String uid);
  Stream<List<HouseholdMember>> watchMembers(String householdId);
  Future<String> createHousehold(
    String name,
    AuthUser user, {
    HouseholdKind kind = HouseholdKind.family,
  });
  Future<InvitationPayload> createInvitation(String householdId);
  Future<String> acceptInvitation(
    String rawPayload,
    AuthUser user, {
    HouseholdRole requestedRole = HouseholdRole.member,
  });
  Future<void> updateMemberRole({
    required String householdId,
    required String memberId,
    required HouseholdRole role,
  });
  Future<void> removeMember({
    required String householdId,
    required String memberId,
  });
  Future<void> leaveHousehold(String householdId);
  Future<void> setActiveHousehold(String uid, String householdId);
  Future<void> updateMemberDisplayName({
    required String householdId,
    required String uid,
    required String displayName,
  });
  Future<bool> hasKey(String householdId);
}

class FirebaseHouseholdRepository implements HouseholdRepository {
  FirebaseHouseholdRepository({
    required SecureKeyStore keyStore,
    required HouseholdCryptoService crypto,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _keyStore = keyStore,
       _crypto = crypto,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'southamerica-west1');

  final SecureKeyStore _keyStore;
  final HouseholdCryptoService _crypto;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  Stream<String?> watchActiveHouseholdId(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      // No avanzamos al tutorial con una escritura local que Firebase todavía
      // puede rechazar. Solo un valor confirmado por el servidor abre el hogar.
      .where((snapshot) => !snapshot.metadata.hasPendingWrites)
      .map((snapshot) => snapshot.data()?['activeHouseholdId'] as String?);

  @override
  Stream<Household> watchHousehold(String householdId, String uid) => _firestore
      .collection('households')
      .doc(householdId)
      .snapshots()
      .asyncMap((snapshot) async {
        if (!snapshot.exists) {
          throw const AppException('El hogar ya no existe.');
        }
        final key = await _requireKey(householdId);
        final data = snapshot.data()!;
        final payload = _asMap(data['privatePayload']);
        final clear = await _crypto.decryptJson(
          payload: payload,
          keyBytes: key,
          context: 'households/$householdId',
        );
        final member =
            await _firestore
                .collection('households')
                .doc(householdId)
                .collection('members')
                .doc(uid)
                .get();
        return Household(
          id: householdId,
          name: clear['name'] as String? ?? 'Mi hogar',
          memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
          role: member.data()?['role'] as String? ?? 'member',
          kind: HouseholdKind.parse(data['kind']),
        );
      });

  @override
  Stream<List<HouseholdMember>> watchMembers(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('members')
      .where('status', isEqualTo: 'active')
      .snapshots()
      .asyncMap((snapshot) async {
        final key = await _requireKey(householdId);
        final result = <HouseholdMember>[];
        for (final document in snapshot.docs) {
          final data = document.data();
          var name = 'Integrante';
          final encrypted = data['privatePayload'];
          if (encrypted is Map) {
            try {
              final clear = await _crypto.decryptJson(
                payload: _asMap(encrypted),
                keyBytes: key,
                context: 'households/$householdId/members/${document.id}',
              );
              name = clear['displayName'] as String? ?? name;
            } on Object {
              name = 'Integrante protegido';
            }
          }
          result.add(
            HouseholdMember(
              uid: document.id,
              displayName: name,
              role: data['role'] as String? ?? 'member',
            ),
          );
        }
        return result;
      });

  @override
  Future<String> createHousehold(
    String name,
    AuthUser user, {
    HouseholdKind kind = HouseholdKind.family,
  }) async {
    final cleanName = name.trim();
    if (cleanName.length < 2 || cleanName.length > 60) {
      throw const AppException('El nombre debe tener entre 2 y 60 caracteres.');
    }
    try {
      await _refreshVerifiedSession();
      final result = await _functions.httpsCallable('createHousehold').call({
        'kind': kind.name,
      });
      final data = _asMap(result.data);
      final householdId = data['householdId'] as String?;
      if (householdId == null) {
        throw const AppException('Firebase no devolvió el hogar creado.');
      }
      final key = await _crypto.generateKey();
      await _keyStore.writeHouseholdKey(householdId, key);
      final householdPayload = await _crypto.encryptJson(
        value: {'name': cleanName},
        keyBytes: key,
        context: 'households/$householdId',
      );
      final memberPayload = await _crypto.encryptJson(
        value: {
          'displayName':
              user.displayName.isEmpty ? 'Integrante' : user.displayName,
        },
        keyBytes: key,
        context: 'households/$householdId/members/${user.uid}',
      );
      final batch = _firestore.batch();
      batch.update(_firestore.collection('households').doc(householdId), {
        'privatePayload': householdPayload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(
        _firestore
            .collection('households')
            .doc(householdId)
            .collection('members')
            .doc(user.uid),
        {'privatePayload': memberPayload},
      );
      await batch.commit();
      await setActiveHousehold(user.uid, householdId);
      return householdId;
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<InvitationPayload> createInvitation(String householdId) async {
    try {
      await _refreshVerifiedSession();
      final key = await _requireKey(householdId);
      final result = await _functions.httpsCallable('createInvitation').call({
        'householdId': householdId,
      });
      final data = _asMap(result.data);
      final invitationId = data['invitationId'] as String?;
      final token = data['token'] as String?;
      final expiresAtMillis = (data['expiresAt'] as num?)?.toInt();
      if (invitationId == null || token == null || expiresAtMillis == null) {
        throw const AppException('No se pudo construir la invitación segura.');
      }
      return InvitationPayload(
        householdId: householdId,
        invitationId: invitationId,
        token: token,
        keyBytes: key,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          expiresAtMillis,
          isUtc: true,
        ),
        kind: HouseholdKind.parse(data['kind']),
      );
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<String> acceptInvitation(
    String rawPayload,
    AuthUser user, {
    HouseholdRole requestedRole = HouseholdRole.member,
  }) async {
    try {
      final payload = InvitationPayload.decode(rawPayload);
      if (payload.isExpired) {
        throw const AppException(
          'La invitación ya venció. Solicita una nueva.',
        );
      }
      await _refreshVerifiedSession();
      final effectiveRole =
          payload.kind == HouseholdKind.family &&
                  requestedRole == HouseholdRole.junior
              ? HouseholdRole.junior
              : HouseholdRole.member;
      final result = await _functions.httpsCallable('acceptInvitation').call({
        'invitationId': payload.invitationId,
        'token': payload.token,
        'requestedRole': effectiveRole.name,
      });
      final resultData = _asMap(result.data);
      final householdId = resultData['householdId'] as String?;
      if (householdId == null || householdId != payload.householdId) {
        throw const AppException('La invitación no coincide con el hogar.');
      }
      await _keyStore.writeHouseholdKey(householdId, payload.keyBytes);
      final memberPayload = await _crypto.encryptJson(
        value: {
          'displayName':
              user.displayName.isEmpty ? 'Integrante' : user.displayName,
        },
        keyBytes: payload.keyBytes,
        context: 'households/$householdId/members/${user.uid}',
      );
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(user.uid)
          .set({'privatePayload': memberPayload}, SetOptions(merge: true));
      await setActiveHousehold(user.uid, householdId);
      return householdId;
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateMemberRole({
    required String householdId,
    required String memberId,
    required HouseholdRole role,
  }) async {
    if (role == HouseholdRole.owner) {
      throw const AppException(
        'La propiedad del hogar no se cambia desde esta opción.',
      );
    }
    try {
      await _refreshVerifiedSession();
      await _functions.httpsCallable('updateMemberRole').call({
        'householdId': householdId,
        'memberId': memberId,
        'role': role.name,
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> removeMember({
    required String householdId,
    required String memberId,
  }) async {
    try {
      await _refreshVerifiedSession();
      await _functions.httpsCallable('removeMember').call({
        'householdId': householdId,
        'memberId': memberId,
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> leaveHousehold(String householdId) async {
    try {
      await _refreshVerifiedSession();
      await _functions.httpsCallable('leaveHousehold').call({
        'householdId': householdId,
      });
      await _keyStore.deleteHouseholdKey(householdId);
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> setActiveHousehold(String uid, String householdId) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'activeHouseholdId': householdId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateMemberDisplayName({
    required String householdId,
    required String uid,
    required String displayName,
  }) async {
    try {
      final key = await _requireKey(householdId);
      final payload = await _crypto.encryptJson(
        value: {'displayName': displayName.trim()},
        keyBytes: key,
        context: 'households/$householdId/members/$uid',
      );
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(uid)
          .set({'privatePayload': payload}, SetOptions(merge: true));
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<bool> hasKey(String householdId) async =>
      await _keyStore.readHouseholdKey(householdId) != null;

  Future<List<int>> _requireKey(String householdId) async {
    final key = await _keyStore.readHouseholdKey(householdId);
    if (key == null) {
      throw const AppException(
        'Falta la clave cifrada de este hogar. Escanea un QR nuevo de otro integrante.',
        code: 'missing-household-key',
      );
    }
    return key;
  }

  Future<void> _refreshVerifiedSession() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw const AppException(
        'Tu sesión terminó. Vuelve a iniciar sesión.',
        code: 'unauthenticated',
      );
    }
    await currentUser.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) {
      throw const AppException(
        'Tu sesión terminó. Vuelve a iniciar sesión.',
        code: 'unauthenticated',
      );
    }
    if (!refreshedUser.emailVerified) {
      throw const AppException(
        'Tu correo aún no aparece como verificado. Vuelve al inicio de sesión e inténtalo nuevamente.',
        code: 'email-not-verified',
      );
    }
    await refreshedUser.getIdToken(true);
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const FormatException('La respuesta del servidor no es válida.');
  }
}
