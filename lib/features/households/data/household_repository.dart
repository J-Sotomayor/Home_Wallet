import 'dart:async';
import 'dart:convert';

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
  Future<List<Household>> listHouseholds(String uid);
  Future<String> createHousehold(
    String name,
    AuthUser user, {
    HouseholdKind kind = HouseholdKind.family,
  });
  Future<InvitationPayload> createInvitation(
    String householdId, {
    HouseholdRole invitedRole = HouseholdRole.member,
  });
  Future<void> revokeInvitation(String householdId);
  Future<String> acceptInvitation(String rawPayload, AuthUser user);
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
  Future<void> updateHouseholdKind({
    required String householdId,
    required HouseholdKind kind,
  });
  Future<void> updateMemberDisplayName({
    required String householdId,
    required String uid,
    required String displayName,
  });
  Future<bool> ensureKeyAvailable(String householdId);
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
      .asyncMap((snapshot) async {
        final data = snapshot.data();
        final active = data?['activeHouseholdId'] as String?;
        if (active != null &&
            active.isNotEmpty &&
            await _hasActiveMembership(active, uid)) {
          return active;
        }
        final householdIds =
            (data?['householdIds'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toSet();
        String? recovered;
        for (final householdId in householdIds) {
          if (await _hasActiveMembership(householdId, uid)) {
            recovered = householdId;
            break;
          }
        }
        if (recovered != active) {
          try {
            await _firestore.collection('users').doc(uid).update({
              'activeHouseholdId': recovered,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } on FirebaseException {
            // La membresía es la autoridad; persistir la preferencia puede
            // reintentarse en el siguiente evento sin bloquear la aplicación.
          }
        }
        return recovered;
      });

  @override
  Stream<Household> watchHousehold(String householdId, String uid) => _firestore
      .collection('households')
      .doc(householdId)
      .snapshots()
      .asyncMap((snapshot) async {
        if (!snapshot.exists) {
          throw const AppException('El espacio ya no existe.');
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
          name: clear['name'] as String? ?? 'Mi espacio',
          memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
          role: member.data()?['role'] as String? ?? 'member',
          kind: HouseholdKind.parse(data['kind'] ?? clear['kind']),
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
  Future<List<Household>> listHouseholds(String uid) async {
    try {
      final user = await _firestore.collection('users').doc(uid).get();
      final householdIds =
          (user.data()?['householdIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet()
              .toList();
      final households = await Future.wait(
        householdIds.map((householdId) async {
          try {
            final householdReference = _firestore
                .collection('households')
                .doc(householdId);
            final results = await Future.wait([
              householdReference.get(),
              householdReference.collection('members').doc(uid).get(),
            ]);
            final household = results[0];
            final member = results[1];
            if (!household.exists ||
                !member.exists ||
                member.data()?['status'] != 'active') {
              return null;
            }
            final data = household.data()!;
            final key = await _keyStore.readHouseholdKey(householdId);
            var name = 'Espacio protegido';
            var kind = HouseholdKind.parse(data['kind']);
            if (key != null && data['privatePayload'] is Map) {
              try {
                final clear = await _crypto.decryptJson(
                  payload: _asMap(data['privatePayload']),
                  keyBytes: key,
                  context: 'households/$householdId',
                );
                name = clear['name'] as String? ?? 'Mi espacio';
                kind = HouseholdKind.parse(data['kind'] ?? clear['kind']);
              } on Object {
                name = 'Espacio protegido';
              }
            }
            return Household(
              id: householdId,
              name: name,
              memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
              role: member.data()?['role'] as String? ?? 'member',
              kind: kind,
              hasLocalKey: key != null,
            );
          } on FirebaseException {
            // Un índice heredado puede conservar un ID después de perder la
            // membresía. Se omite sin impedir el acceso a los demás espacios.
            return null;
          }
        }),
      );
      final available =
          households.whereType<Household>().toList()..sort((left, right) {
            if (left.isIndividual != right.isIndividual) {
              return left.isIndividual ? -1 : 1;
            }
            return left.name.toLowerCase().compareTo(right.name.toLowerCase());
          });
      return available;
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

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
        throw const AppException('Firebase no devolvió el espacio creado.');
      }
      final key = await _crypto.generateKey();
      await _keyStore.writeHouseholdKey(householdId, key);
      final householdPayload = await _crypto.encryptJson(
        value: {'name': cleanName, 'kind': kind.name},
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
      await _tryBackupHouseholdKey(householdId, key);
      await setActiveHousehold(user.uid, householdId);
      return householdId;
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateHouseholdKind({
    required String householdId,
    required HouseholdKind kind,
  }) async {
    try {
      final reference = _firestore.collection('households').doc(householdId);
      final snapshot = await reference.get();
      if (!snapshot.exists) {
        throw const AppException('El espacio ya no existe.');
      }
      final data = snapshot.data()!;
      final key = await _requireKey(householdId);
      final payload = _asMap(data['privatePayload']);
      final clear =
          payload.isEmpty
              ? <String, dynamic>{}
              : await _crypto.decryptJson(
                payload: payload,
                keyBytes: key,
                context: 'households/$householdId',
              );
      clear['kind'] = kind.name;
      final encrypted = await _crypto.encryptJson(
        value: clear,
        keyBytes: key,
        context: 'households/$householdId',
      );
      await _refreshVerifiedSession();
      await _functions.httpsCallable('updateHouseholdKind').call({
        'householdId': householdId,
        'kind': kind.name,
        'privatePayload': encrypted,
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<InvitationPayload> createInvitation(
    String householdId, {
    HouseholdRole invitedRole = HouseholdRole.member,
  }) async {
    try {
      await _refreshVerifiedSession();
      final key = await _requireKey(householdId);
      final result = await _functions.httpsCallable('createInvitation').call({
        'householdId': householdId,
        'role': invitedRole == HouseholdRole.junior ? 'junior' : 'member',
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
  Future<void> revokeInvitation(String householdId) async {
    try {
      await _refreshVerifiedSession();
      await _functions.httpsCallable('revokeInvitation').call({
        'householdId': householdId,
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<String> acceptInvitation(String rawPayload, AuthUser user) async {
    try {
      final payload = InvitationPayload.decode(rawPayload);
      if (payload.isExpired) {
        throw const AppException(
          'La invitación ya venció. Solicita una nueva.',
        );
      }
      await _refreshVerifiedSession();
      final result = await _functions.httpsCallable('acceptInvitation').call({
        'invitationId': payload.invitationId,
        'token': payload.token,
      });
      final resultData = _asMap(result.data);
      final householdId = resultData['householdId'] as String?;
      if (householdId == null || householdId != payload.householdId) {
        throw const AppException('La invitación no coincide con el espacio.');
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
      await _tryBackupHouseholdKey(householdId, payload.keyBytes);
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
        'La propiedad del espacio no se cambia desde esta opción.',
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
  Future<bool> ensureKeyAvailable(String householdId) async {
    final localKey = await _keyStore.readHouseholdKey(householdId);
    if (localKey != null) {
      // No retrasamos la entrada: el respaldo se renueva en segundo plano.
      unawaited(_tryBackupHouseholdKey(householdId, localKey));
      return true;
    }
    try {
      await _refreshVerifiedSession();
      final result = await _functions.httpsCallable('recoverHouseholdKey').call(
        {'householdId': householdId},
      );
      final encoded = _asMap(result.data)['key'];
      if (encoded is! String) return false;
      final key = base64Url.decode(
        encoded.padRight((encoded.length + 3) ~/ 4 * 4, '='),
      );
      if (key.length != 32) return false;
      await _keyStore.writeHouseholdKey(householdId, key);
      return true;
    } on Object {
      // Si todavía no existe respaldo o no hay conexión, la interfaz conserva
      // el QR como recuperación manual y permite reintentar.
      return false;
    }
  }

  Future<void> _tryBackupHouseholdKey(String householdId, List<int> key) async {
    try {
      await _functions.httpsCallable('backupHouseholdKey').call({
        'householdId': householdId,
        'key': base64UrlEncode(key).replaceAll('=', ''),
      });
    } on Object {
      // El respaldo mejora la recuperación, pero una caída temporal de la
      // Function no debe bloquear el acceso con una clave local válida.
    }
  }

  Future<bool> _hasActiveMembership(String householdId, String uid) async {
    try {
      final householdReference = _firestore
          .collection('households')
          .doc(householdId);
      final results = await Future.wait([
        householdReference.get(),
        householdReference.collection('members').doc(uid).get(),
      ]);
      return results[0].exists &&
          results[1].exists &&
          results[1].data()?['status'] == 'active';
    } on FirebaseException {
      return false;
    }
  }

  Future<List<int>> _requireKey(String householdId) async {
    final key = await _keyStore.readHouseholdKey(householdId);
    if (key == null) {
      throw const AppException(
        'Falta la clave cifrada de este espacio. Escanea un QR nuevo de otro integrante.',
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
