import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

class JwtAuthException implements Exception {
  const JwtAuthException(this.message, {this.statusCode = 401});

  final String message;
  final int statusCode;
}

class JwtService {
  JwtService._();

  static final JwtService instance = JwtService._();
  static const Duration _tokenLifetime = Duration(days: 30);

  String issueToken({required ObjectId userId}) {
    final now = DateTime.now().toUtc();
    final header = _encodeJson({'alg': 'HS256', 'typ': 'JWT'});
    final payload = _encodeJson({
      'sub': userId.oid,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(_tokenLifetime).millisecondsSinceEpoch ~/ 1000,
    });
    final unsignedToken = '$header.$payload';
    final signature = _sign(unsignedToken);
    return '$unsignedToken.$signature';
  }

  ObjectId userIdFromRequest(Request request) {
    final token = _bearerToken(request);
    if (token == null || token.isEmpty) {
      throw const JwtAuthException('Authorization token is required');
    }

    return verifyToken(token);
  }

  ObjectId resolveUserId(Request request, String? requestedUserId) {
    final tokenUserId = userIdFromRequest(request);
    final normalizedRequestedUserId = requestedUserId?.trim();
    if (normalizedRequestedUserId == null ||
        normalizedRequestedUserId.isEmpty) {
      return tokenUserId;
    }

    if (!ObjectId.isValidHexId(normalizedRequestedUserId)) {
      throw const JwtAuthException('Invalid user ID format', statusCode: 400);
    }

    final requestedObjectId = ObjectId.fromHexString(normalizedRequestedUserId);
    if (requestedObjectId != tokenUserId) {
      throw const JwtAuthException(
        'Authorization token does not match user',
        statusCode: 403,
      );
    }

    return tokenUserId;
  }

  ObjectId verifyToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const JwtAuthException('Invalid authorization token');
    }

    final unsignedToken = '${parts[0]}.${parts[1]}';
    final expectedSignature = _sign(unsignedToken);
    if (!_constantTimeEquals(expectedSignature, parts[2])) {
      throw const JwtAuthException('Invalid authorization token');
    }

    final payload = _decodeJson(parts[1]);
    final userId = payload['sub']?.toString();
    final expiresAt = payload['exp'];
    if (userId == null || !ObjectId.isValidHexId(userId)) {
      throw const JwtAuthException('Invalid authorization token');
    }
    if (expiresAt is! num ||
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 >=
            expiresAt.toInt()) {
      throw const JwtAuthException('Authorization token expired');
    }

    return ObjectId.fromHexString(userId);
  }

  String? _bearerToken(Request request) {
    final authorization = request.headers['authorization'];
    if (authorization == null) {
      return null;
    }

    final match = RegExp(
      r'^Bearer\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(authorization.trim());
    return match?.group(1)?.trim();
  }

  String _encodeJson(Map<String, dynamic> value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  Map<String, dynamic> _decodeJson(String value) {
    try {
      final normalized = base64Url.normalize(value);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return Map<String, dynamic>.from(jsonDecode(decoded) as Map);
    } catch (_) {
      throw const JwtAuthException('Invalid authorization token');
    }
  }

  String _sign(String value) {
    final digest = Hmac(
      sha256,
      utf8.encode(AppConfig.jwtSecret),
    ).convert(utf8.encode(value));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }

    var diff = 0;
    for (var i = 0; i < a.length; i += 1) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
