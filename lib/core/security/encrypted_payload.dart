import 'dart:convert';

class EncryptedPayload {
  const EncryptedPayload({
    required this.cipherText,
    required this.nonce,
    required this.mac,
    this.version = 1,
  });

  factory EncryptedPayload.fromMap(Map<String, dynamic> map) {
    if (map['v'] != 1 || map['alg'] != 'A256GCM') {
      throw const FormatException('Formato cifrado no compatible.');
    }
    return EncryptedPayload(
      cipherText: _decode(map['ct']),
      nonce: _decode(map['iv']),
      mac: _decode(map['tag']),
    );
  }

  final List<int> cipherText;
  final List<int> nonce;
  final List<int> mac;
  final int version;

  Map<String, dynamic> toMap() => {
    'v': version,
    'alg': 'A256GCM',
    'ct': _encode(cipherText),
    'iv': _encode(nonce),
    'tag': _encode(mac),
  };

  static String _encode(List<int> value) =>
      base64UrlEncode(value).replaceAll('=', '');

  static List<int> _decode(Object? value) {
    if (value is! String || value.isEmpty || value.length > 100000) {
      throw const FormatException('Contenido cifrado inválido.');
    }
    final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(normalized);
  }
}
