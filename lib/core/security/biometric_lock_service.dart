import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../errors/app_exception.dart';
import 'secure_key_store.dart';

abstract interface class DeviceAuthenticator {
  Future<bool> isSupported();
  Future<bool> authenticate();
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    try {
      return await _localAuthentication.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: 'Confirma tu identidad para abrir HomeWallet',
        options: const AuthenticationOptions(
          stickyAuth: true,
          sensitiveTransaction: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (error) {
      throw AppException(
        'No fue posible usar la seguridad del dispositivo.',
        code: error.code,
      );
    }
  }
}

class BiometricLockService {
  BiometricLockService({
    required SecureKeyStore keyStore,
    DeviceAuthenticator? authenticator,
  }) : _keyStore = keyStore,
       _authenticator = authenticator ?? LocalDeviceAuthenticator();

  final SecureKeyStore _keyStore;
  final DeviceAuthenticator _authenticator;
  static const _settingsChannel = MethodChannel(
    'com.homewallet.app/device_security',
  );

  Future<bool> isAvailable() => _authenticator.isSupported();

  Future<bool> isEnabled(String uid) async {
    final preference = await _keyStore.readBiometricPreference(uid);
    return preference ?? false;
  }

  Future<void> openEnrollmentSettings() async {
    if (kIsWeb) {
      throw const AppException(
        'Configura la seguridad desde los ajustes de tu dispositivo.',
      );
    }
    try {
      await _settingsChannel.invokeMethod<void>('openEnrollmentSettings');
    } on PlatformException catch (error) {
      throw AppException(
        'No fue posible abrir los ajustes de seguridad.',
        code: error.code,
      );
    }
  }

  Future<void> setEnabled(String uid, bool enabled) async {
    if (enabled && !await isAvailable()) {
      throw const AppException(
        'Configura huella, rostro, PIN o patrón en el dispositivo primero.',
      );
    }
    if (enabled && !await _authenticator.authenticate()) {
      throw const AppException('No se confirmó la identidad.');
    }
    await _keyStore.writeBiometricPreference(uid, enabled);
  }

  Future<bool> unlock(String uid) async {
    if (!await isEnabled(uid)) return true;
    return _authenticator.authenticate();
  }
}
