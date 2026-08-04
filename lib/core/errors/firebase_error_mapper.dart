import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'app_exception.dart';

AppException mapFirebaseError(Object error) {
  if (error is AppException) return error;
  if (error is FirebaseAuthException) {
    final message = switch (error.code) {
      'invalid-email' => 'El correo electrónico no es válido.',
      'invalid-credential' ||
      'user-not-found' ||
      'wrong-password' => 'El correo o la contraseña son incorrectos.',
      'user-disabled' => 'Esta cuenta fue deshabilitada.',
      'email-already-in-use' => 'Ya existe una cuenta con ese correo.',
      'weak-password' => 'La contraseña no cumple los requisitos de seguridad.',
      'too-many-requests' =>
        'Se realizaron demasiados intentos. Espera unos minutos.',
      'network-request-failed' =>
        'No se pudo conectar. Revisa tu conexión a Internet.',
      'operation-not-allowed' =>
        'Este método de acceso no está habilitado en Firebase.',
      'requires-recent-login' =>
        'Por seguridad, vuelve a iniciar sesión antes de continuar.',
      _ => 'No se pudo completar la autenticación. Inténtalo nuevamente.',
    };
    return AppException(message, code: error.code);
  }
  if (error is FirebaseFunctionsException) {
    final serverMessage = error.message?.trim();
    final message = switch (error.code) {
      'permission-denied' ||
      'failed-precondition' ||
      'invalid-argument' ||
      'not-found' ||
      'already-exists' ||
      'deadline-exceeded' ||
      'resource-exhausted' =>
        serverMessage?.isNotEmpty == true
            ? serverMessage!
            : 'No se pudo completar la operación solicitada.',
      'unauthenticated' => 'Tu sesión terminó. Vuelve a iniciar sesión.',
      'unavailable' => 'El servicio no está disponible. Inténtalo nuevamente.',
      'internal' =>
        'El servidor no pudo completar la operación. Inténtalo nuevamente.',
      _ =>
        serverMessage?.isNotEmpty == true
            ? serverMessage!
            : 'No se pudo completar la operación en Firebase.',
    };
    return AppException(message, code: error.code);
  }
  if (error is FirebaseException) {
    final message = switch (error.code) {
      'permission-denied' =>
        'No tienes permiso para acceder a esta información.',
      'unauthenticated' => 'Tu sesión terminó. Vuelve a iniciar sesión.',
      'failed-precondition' =>
        error.message ?? 'Falta completar un requisito para continuar.',
      'invalid-argument' =>
        error.message ?? 'La información enviada no es válida.',
      'not-found' =>
        error.message ?? 'No se encontró la información solicitada.',
      'already-exists' => error.message ?? 'La información ya existe.',
      'unauthorized' => 'No tienes permiso para administrar este archivo.',
      'object-not-found' => 'No se encontró el archivo solicitado.',
      'unavailable' => 'El servicio no está disponible. Inténtalo nuevamente.',
      'deadline-exceeded' => 'La operación tardó demasiado en responder.',
      'resource-exhausted' =>
        'Se alcanzó temporalmente el límite del servicio.',
      'internal' =>
        'El servidor encontró un problema interno. Inténtalo nuevamente.',
      _ => 'Ocurrió un problema al comunicarse con Firebase.',
    };
    return AppException(message, code: error.code);
  }
  return const AppException(
    'Ocurrió un error inesperado. Inténtalo nuevamente.',
  );
}
