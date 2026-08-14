import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/firebase_error_mapper.dart';

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.emailVerified,
    this.phoneNumber = '',
    this.photoUrl,
    this.deletionScheduledFor,
    this.needsOnboarding = false,
    this.preferredCategories = const <String>[],
  });

  final String uid;
  final String email;
  final String displayName;
  final bool emailVerified;
  final String phoneNumber;
  final String? photoUrl;
  final DateTime? deletionScheduledFor;
  final bool needsOnboarding;
  final List<String> preferredCategories;
}

abstract interface class AuthRepository {
  Stream<AuthUser?> watchUser();
  AuthUser? get currentUser;
  Future<void> signIn({required String email, required String password});
  Future<void> signInWithGoogle();
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  });
  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();
  Future<bool> reloadEmailVerification();
  Future<void> updateProfile({
    required String displayName,
    required String phoneNumber,
    Uint8List? photoBytes,
    String? photoExtension,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<void> acceptTerms();
  Future<void> completeOnboarding(List<String> preferredCategories);
  Future<void> updatePreferredCategories(List<String> preferredCategories);
  Future<DateTime> requestAccountDeletion();
  Future<void> cancelAccountDeletion();
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'southamerica-west1');

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleInitialization;

  @override
  AuthUser? get currentUser => _mapUser(_auth.currentUser, null);

  @override
  Stream<AuthUser?> watchUser() {
    late final StreamController<AuthUser?> controller;
    StreamSubscription<User?>? authSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    profileSubscription;
    var generation = 0;

    Future<void> switchUser(User? user) async {
      final currentGeneration = ++generation;
      await profileSubscription?.cancel();
      profileSubscription = null;
      if (controller.isClosed || currentGeneration != generation) return;
      if (user == null) {
        controller.add(null);
        return;
      }

      controller.add(_mapUser(user, null));
      profileSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (snapshot) {
              if (controller.isClosed || currentGeneration != generation) {
                return;
              }
              final currentUser = _auth.currentUser;
              if (currentUser?.uid == user.uid) {
                controller.add(_mapUser(currentUser, snapshot.data()));
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed && currentGeneration == generation) {
                debugPrint(
                  'No se pudo actualizar el perfil de ${user.uid}: $error',
                );
                final currentUser = _auth.currentUser;
                if (currentUser?.uid == user.uid) {
                  // El perfil de Firestore complementa la sesión, pero una
                  // falla temporal al leerlo no invalida Firebase Auth.
                  controller.add(_mapUser(currentUser, null));
                }
              }
            },
          );
    }

    controller = StreamController<AuthUser?>(
      onListen: () {
        authSubscription = _auth.userChanges().listen(
          (user) => unawaited(switchUser(user)),
          onError: controller.addError,
        );
      },
      onCancel: () async {
        generation++;
        await authSubscription?.cancel();
        await profileSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _ensureProfile();
      await _auth.currentUser?.getIdToken(true);
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        await _auth.signInWithPopup(GoogleAuthProvider());
      } else {
        final supportedPlatform = switch (defaultTargetPlatform) {
          TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.macOS => true,
          _ => false,
        };
        if (!supportedPlatform) {
          throw const AppException(
            'El acceso con Google está disponible en Android.',
            code: 'google-platform-not-supported',
          );
        }
        await (_googleInitialization ??= _googleSignIn.initialize());
        final googleUser = await _googleSignIn.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          throw const AppException(
            'Google no devolvió una credencial válida. Inténtalo nuevamente.',
            code: 'google-missing-id-token',
          );
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        await _auth.signInWithCredential(credential);
      }
      await _ensureProfile();
      await _auth.currentUser?.getIdToken(true);
    } on GoogleSignInException catch (error) {
      final message = switch (error.code) {
        GoogleSignInExceptionCode.canceled =>
          'Se canceló el acceso con Google.',
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google no está configurado correctamente para esta aplicación.',
        GoogleSignInExceptionCode.uiUnavailable =>
          'No se pudo abrir el selector de cuentas de Google.',
        _ => 'No se pudo iniciar sesión con Google. Inténtalo nuevamente.',
      };
      throw AppException(message, code: error.code.name);
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw StateError('Firebase no devolvió el usuario.');
      await user.updateDisplayName(displayName.trim());
      // El correo es la primera operación posterior al alta. Si Firestore
      // rechaza temporalmente la creación del perfil, el usuario igual debe
      // recibir el enlace y poder completar la verificación.
      await _auth.setLanguageCode('es');
      await user.sendEmailVerification();
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': displayName.trim(),
        'phoneNumber': '',
        'photoUrl': null,
        'activeHouseholdId': null,
        'householdIds': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'termsVersion': '2026-08-02',
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': false,
        'preferredCategories': <String>[],
      }, SetOptions(merge: true));
      await user.reload();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.setLanguageCode('es');
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _auth.setLanguageCode('es');
      await user.sendEmailVerification();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<bool> reloadEmailVerification() async {
    try {
      await _auth.currentUser?.reload();
      final user = _auth.currentUser;
      final verified = user?.emailVerified ?? false;
      if (verified) {
        await user!.getIdToken(true);
      }
      return verified;
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    required String phoneNumber,
    Uint8List? photoBytes,
    String? photoExtension,
  }) async {
    final cleanName = displayName.trim();
    final cleanPhone = phoneNumber.trim();
    if (cleanName.length < 2 || cleanName.length > 60) {
      throw const AppException('El nombre debe tener entre 2 y 60 caracteres.');
    }
    if (cleanPhone.isNotEmpty &&
        !RegExp(r'^\+?[0-9][0-9\s-]{6,19}$').hasMatch(cleanPhone)) {
      throw const AppException('Ingresa un número de celular válido.');
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException('Tu sesión terminó. Vuelve a iniciar sesión.');
    }
    try {
      var photoUrl = user.photoURL;
      if (photoBytes != null) {
        if (photoBytes.length > 5 * 1024 * 1024) {
          throw const AppException('La foto no puede superar los 5 MB.');
        }
        final extension = (photoExtension ?? '').toLowerCase();
        final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
        final reference = _storage.ref('profilePhotos/${user.uid}/avatar');
        await reference.putData(
          photoBytes,
          SettableMetadata(contentType: contentType),
        );
        photoUrl = await reference.getDownloadURL();
        await user.updatePhotoURL(photoUrl);
      }
      if (user.displayName != cleanName) {
        await user.updateDisplayName(cleanName);
      }
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': cleanName,
        'phoneNumber': cleanPhone,
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await user.reload();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 8) {
      throw const AppException(
        'La nueva contraseña debe tener al menos 8 caracteres.',
      );
    }
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AppException('Tu sesión terminó. Vuelve a iniciar sesión.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> acceptTerms() async {
    try {
      await _functions.httpsCallable('acceptTerms').call({
        'version': '2026-08-02',
      });
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> completeOnboarding(List<String> preferredCategories) async {
    await _savePreferredCategories(
      preferredCategories,
      onboardingCompleted: true,
    );
  }

  @override
  Future<void> updatePreferredCategories(
    List<String> preferredCategories,
  ) async {
    await _savePreferredCategories(preferredCategories);
  }

  Future<void> _savePreferredCategories(
    List<String> preferredCategories, {
    bool? onboardingCompleted,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException('Tu sesión terminó. Vuelve a iniciar sesión.');
    }
    final clean =
        preferredCategories
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty && value.length <= 40)
            .toSet()
            .toList()
          ..sort();
    if (clean.isEmpty) {
      throw const AppException('Elige al menos una categoría para continuar.');
    }
    final values = <String, Object?>{
      'preferredCategories': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (onboardingCompleted != null) {
      values['onboardingCompleted'] = onboardingCompleted;
      values['onboardingCompletedAt'] = FieldValue.serverTimestamp();
    }
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(values, SetOptions(merge: true));
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<DateTime> requestAccountDeletion() async {
    try {
      final result =
          await _functions.httpsCallable('requestAccountDeletion').call();
      final data = result.data;
      if (data is! Map) {
        throw const AppException(
          'El servidor no confirmó la fecha de borrado.',
        );
      }
      final millis = (data['executeAfter'] as num?)?.toInt();
      if (millis == null) {
        throw const AppException(
          'El servidor no confirmó la fecha de borrado.',
        );
      }
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> cancelAccountDeletion() async {
    try {
      await _functions.httpsCallable('cancelAccountDeletion').call();
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      if (!kIsWeb) {
        try {
          await (_googleInitialization ??= _googleSignIn.initialize());
          await _googleSignIn.signOut();
        } on Object {
          // Firebase ya cerró la sesión. Google se limpiará en el próximo uso.
        }
      }
    } catch (error) {
      throw mapFirebaseError(error);
    }
  }

  Future<void> _ensureProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final reference = _firestore.collection('users').doc(user.uid);
    final snapshot = await reference.get();
    final displayName = user.displayName?.trim() ?? '';
    if (!snapshot.exists) {
      await reference.set({
        'displayName': displayName,
        'phoneNumber': '',
        'photoUrl': user.photoURL,
        'activeHouseholdId': null,
        'householdIds': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'termsVersion': '2026-08-02',
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': false,
        'preferredCategories': <String>[],
      });
      return;
    }
    await reference.update({
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static AuthUser? _mapUser(User? user, Map<String, dynamic>? profile) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName?.trim() ?? '',
      emailVerified: user.emailVerified,
      phoneNumber: profile?['phoneNumber'] as String? ?? user.phoneNumber ?? '',
      photoUrl: profile?['photoUrl'] as String? ?? user.photoURL,
      deletionScheduledFor:
          (profile?['deletionScheduledFor'] as Timestamp?)?.toDate(),
      needsOnboarding: profile?['onboardingCompleted'] == false,
      preferredCategories:
          (profile?['preferredCategories'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
    );
  }
}
