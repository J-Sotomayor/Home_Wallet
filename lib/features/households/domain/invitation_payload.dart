import 'dart:convert';

import 'household_models.dart';

class InvitationPayload {
  const InvitationPayload({
    required this.householdId,
    required this.invitationId,
    required this.token,
    required this.keyBytes,
    required this.expiresAt,
    this.kind = HouseholdKind.family,
    this.role = HouseholdRole.member,
    this.shortCode,
  });

  factory InvitationPayload.decode(String raw) {
    final value = raw.trim();
    if (!value.startsWith('HW1.')) {
      throw const FormatException('Este código no pertenece a HomeWallet.');
    }
    final encoded = value.substring(4);
    if (encoded.length > 4096) {
      throw const FormatException('El código es demasiado largo.');
    }
    final normalized = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
    final json = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (json is! Map<String, dynamic> || json['v'] != 1) {
      throw const FormatException('El código de invitación no es válido.');
    }
    final keyValue = json['k'];
    if (keyValue is! String) {
      throw const FormatException('El código no contiene una clave válida.');
    }
    final keyNormalized = keyValue.padRight(
      (keyValue.length + 3) ~/ 4 * 4,
      '=',
    );
    final keyBytes = base64Url.decode(keyNormalized);
    final householdId = json['h'];
    final invitationId = json['i'];
    final token = json['t'];
    final expiryMillis = json['e'];
    if (householdId is! String ||
        invitationId is! String ||
        token is! String ||
        expiryMillis is! int ||
        !_validId(householdId) ||
        !_validId(invitationId) ||
        token.length < 32 ||
        token.length > 256 ||
        keyBytes.length != 32) {
      throw const FormatException('El código de invitación está incompleto.');
    }
    return InvitationPayload(
      householdId: householdId,
      invitationId: invitationId,
      token: token,
      keyBytes: keyBytes,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiryMillis, isUtc: true),
      kind: HouseholdKind.parse(json['g']),
      role: HouseholdRole.parse(json['r']),
    );
  }

  final String householdId;
  final String invitationId;
  final String token;
  final List<int> keyBytes;
  final DateTime expiresAt;
  final HouseholdKind kind;
  final HouseholdRole role;
  final String? shortCode;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  String encode() {
    final content = jsonEncode({
      'v': 1,
      'h': householdId,
      'i': invitationId,
      't': token,
      'k': base64UrlEncode(keyBytes).replaceAll('=', ''),
      'e': expiresAt.toUtc().millisecondsSinceEpoch,
      'g': kind.name,
      'r': role.name,
    });
    return 'HW1.${base64UrlEncode(utf8.encode(content)).replaceAll('=', '')}';
  }

  static bool _validId(String value) =>
      value.length >= 8 &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
}

class HouseholdInvitationPreview {
  const HouseholdInvitationPreview({
    required this.payload,
    required this.householdName,
    required this.role,
  });

  final InvitationPayload payload;
  final String householdName;
  final HouseholdRole role;
}
