import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encrypted_payload.dart';

class HouseholdCryptoService {
  HouseholdCryptoService({AesGcm? algorithm})
    : _algorithm = algorithm ?? AesGcm.with256bits();

  final AesGcm _algorithm;

  Future<List<int>> generateKey() async {
    final key = await _algorithm.newSecretKey();
    return key.extractBytes();
  }

  Future<Map<String, dynamic>> encryptJson({
    required Map<String, dynamic> value,
    required List<int> keyBytes,
    required String context,
  }) async {
    _validateKey(keyBytes);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: SecretKey(keyBytes),
      aad: utf8.encode(context),
    );
    return EncryptedPayload(
      cipherText: secretBox.cipherText,
      nonce: secretBox.nonce,
      mac: secretBox.mac.bytes,
    ).toMap();
  }

  Future<Map<String, dynamic>> decryptJson({
    required Map<String, dynamic> payload,
    required List<int> keyBytes,
    required String context,
  }) async {
    _validateKey(keyBytes);
    final encrypted = EncryptedPayload.fromMap(payload);
    final clearText = await _algorithm.decrypt(
      SecretBox(
        encrypted.cipherText,
        nonce: encrypted.nonce,
        mac: Mac(encrypted.mac),
      ),
      secretKey: SecretKey(keyBytes),
      aad: utf8.encode(context),
    );
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Los datos descifrados no son válidos.');
    }
    return decoded;
  }

  void _validateKey(List<int> keyBytes) {
    if (keyBytes.length != 32) {
      throw const FormatException('La clave del espacio no es válida.');
    }
  }
}
