import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureKeyStore {
  Future<void> writeHouseholdKey(String householdId, List<int> keyBytes);
  Future<List<int>?> readHouseholdKey(String householdId);
  Future<void> deleteHouseholdKey(String householdId);
  Future<bool?> readBiometricPreference(String uid);
  Future<void> writeBiometricPreference(String uid, bool enabled);
}

class DeviceSecureKeyStore implements SecureKeyStore {
  DeviceSecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _androidOptions = AndroidOptions();
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<void> writeHouseholdKey(String householdId, List<int> keyBytes) {
    if (keyBytes.length != 32) {
      throw const FormatException('La clave del hogar debe tener 256 bits.');
    }
    return _storage.write(
      key: 'household_key_$householdId',
      value: base64UrlEncode(keyBytes),
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  @override
  Future<List<int>?> readHouseholdKey(String householdId) async {
    final value = await _storage.read(
      key: 'household_key_$householdId',
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    if (value == null) return null;
    final bytes = base64Url.decode(value);
    if (bytes.length != 32) return null;
    return bytes;
  }

  @override
  Future<void> deleteHouseholdKey(String householdId) => _storage.delete(
    key: 'household_key_$householdId',
    aOptions: _androidOptions,
    iOptions: _iosOptions,
  );

  @override
  Future<bool?> readBiometricPreference(String uid) async {
    final value = await _storage.read(
      key: 'biometric_enabled_$uid',
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  @override
  Future<void> writeBiometricPreference(String uid, bool enabled) =>
      _storage.write(
        key: 'biometric_enabled_$uid',
        value: enabled.toString(),
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
}

class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};

  @override
  Future<void> deleteHouseholdKey(String householdId) async {
    _values.remove('household_key_$householdId');
  }

  @override
  Future<bool?> readBiometricPreference(String uid) async {
    final value = _values['biometric_enabled_$uid'];
    return value == null ? null : value == 'true';
  }

  @override
  Future<List<int>?> readHouseholdKey(String householdId) async {
    final value = _values['household_key_$householdId'];
    return value == null ? null : base64Url.decode(value);
  }

  @override
  Future<void> writeBiometricPreference(String uid, bool enabled) async {
    _values['biometric_enabled_$uid'] = enabled.toString();
  }

  @override
  Future<void> writeHouseholdKey(String householdId, List<int> keyBytes) async {
    _values['household_key_$householdId'] = base64UrlEncode(keyBytes);
  }
}
