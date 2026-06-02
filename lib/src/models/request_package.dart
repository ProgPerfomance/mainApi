// Этот файл: lib/src/models/request_package.dart.
// Простыми словами: это товар "пакет AI-запросов", который админ настраивает для покупки.

import 'package:mongo_dart/mongo_dart.dart';

// Пакет запросов - это продукт витрины.
// Пользователь покупает его один раз и получает фиксированное число будущих AI-ответов.
class RequestPackage {
  RequestPackage({
    this.id,
    required this.requestCount,
    required this.price,
    String? appId,
    String? scope,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : appId = _normalizeAppId(appId),
       scope = _normalizeScope(scope),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final ObjectId? id;
  final int requestCount;
  final double price;
  final String appId;
  final String scope;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Собираем пакет из базы, чтобы backend мог показать его в админке и приложении.
  factory RequestPackage.fromJson(Map<String, dynamic> json) {
    return RequestPackage(
      id: json['_id'] as ObjectId?,
      requestCount: (json['requestCount'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      appId: json['appId']?.toString() ?? json['app_id']?.toString(),
      scope: json['scope']?.toString(),
      isActive: json['isActive'] != false,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  // Формат для сохранения пакета в базе.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'requestCount': requestCount,
      'price': price,
      'appId': appId,
      'app_id': appId,
      'scope': scope,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Формат для админки и мобильного приложения.
  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      'requestCount': requestCount,
      'price': price,
      'appId': appId,
      'app_id': appId,
      'scope': scope,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    final rawValue = value?.toString();
    if (rawValue == null || rawValue.isEmpty) {
      return DateTime.now();
    }

    return DateTime.tryParse(rawValue) ?? DateTime.now();
  }

  static String _normalizeAppId(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return 'psychology';
    }
    return normalized;
  }

  static String _normalizeScope(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == 'global' ? 'global' : 'app';
  }
}
