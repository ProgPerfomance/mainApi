import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:main_api/src/services/app_config.dart';

class EncryptionService {
  EncryptionService._();

  static final EncryptionService instance = EncryptionService._();

  static const String _algorithmName = 'aes-256-gcm';
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<Map<String, dynamic>> encryptString(String value) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _secretKey(),
    );
    return {
      'v': 1,
      'alg': _algorithmName,
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<String?> decryptString(dynamic value) async {
    if (value is! Map) {
      return null;
    }
    final data = Map<String, dynamic>.from(value);
    if (data['alg'] != _algorithmName) {
      return null;
    }
    final nonce = _decode(data['nonce']);
    final cipherText = _decode(data['cipherText']);
    final mac = _decode(data['mac']);
    if (nonce == null || cipherText == null || mac == null) {
      return null;
    }
    final clearBytes = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: await _secretKey(),
    );
    return utf8.decode(clearBytes);
  }

  Future<SecretKey> _secretKey() async {
    final digest = sha256.convert(
      utf8.encode(AppConfig.settingsEncryptionSecret),
    );
    return SecretKey(digest.bytes);
  }

  List<int>? _decode(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }
}
