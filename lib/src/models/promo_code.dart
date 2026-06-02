// Этот файл: lib/src/models/promo_code.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';

/// Класс PromoCodeRedemption: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class PromoCodeRedemption {
  final ObjectId userId;
  final String? userName;
  final String? userEmail;
  final DateTime redeemedAt;

  const PromoCodeRedemption({
    required this.userId,
    this.userName,
    this.userEmail,
    required this.redeemedAt,
  });

  /// Фабрика PromoCodeRedemption.fromJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory PromoCodeRedemption.fromJson(Map<String, dynamic> json) {
    final userId = _parseObjectId(json['userId']);

    /// Функция PromoCodeRedemption: выполняет шаг PromoCodeRedemption в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return PromoCodeRedemption(
      userId: userId,
      userName: json['userName'] as String?,
      userEmail: json['userEmail'] as String?,
      redeemedAt: _parseDateTime(json['redeemedAt']),
    );
  }

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      if (userName != null) 'userName': userName,
      if (userEmail != null) 'userEmail': userEmail,
      'redeemedAt': redeemedAt.toIso8601String(),
    };
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson() {
    return {
      'userId': userId.oid,
      if (userName != null) 'userName': userName,
      if (userEmail != null) 'userEmail': userEmail,
      'redeemedAt': redeemedAt.toIso8601String(),
    };
  }
}

/// Класс PromoCode: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class PromoCode {
  final ObjectId? id;
  final String code;
  final String appId;
  final String? campaign;
  final double amount;
  final bool isActive;
  final int? maxRedemptions;
  final DateTime? expiresAt;
  final List<PromoCodeRedemption> redemptions;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PromoCode({
    this.id,
    required this.code,
    this.appId = 'psychology',
    this.campaign,
    required this.amount,
    this.isActive = true,
    this.maxRedemptions,
    this.expiresAt,
    this.redemptions = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isExpired {
    final expires = expiresAt;
    return expires != null && !expires.toUtc().isAfter(DateTime.now().toUtc());
  }

  /// Фабрика PromoCode.fromJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory PromoCode.fromJson(Map<String, dynamic> json) {
    final rawRedemptions = json['redemptions'] as List<dynamic>? ?? const [];

    /// Функция PromoCode: выполняет шаг PromoCode в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return PromoCode(
      id: json['_id'] as ObjectId?,
      code: json['code'] as String,
      appId: _normalizeAppId(json['appId'] ?? json['app_id']),
      campaign: json['campaign'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? true,
      maxRedemptions: (json['maxRedemptions'] as num?)?.toInt(),
      expiresAt: _parseNullableDateTime(json['expiresAt']),
      redemptions: rawRedemptions
          .whereType<Map>()
          .map(
            (item) =>
                /// Конструктор PromoCodeRedemption.fromJson: создаёт новый объект этого класса.
                /// Возвращает готовый объект, с которым дальше работает приложение.
                PromoCodeRedemption.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'code': code,
      'appId': appId,
      'app_id': appId,
      if (campaign != null) 'campaign': campaign,
      'amount': amount,
      'isActive': isActive,
      if (maxRedemptions != null) 'maxRedemptions': maxRedemptions,
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      'redemptions': redemptions.map((item) => item.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      'code': code,
      'appId': appId,
      'app_id': appId,
      if (campaign != null) 'campaign': campaign,
      'amount': amount,
      'isActive': isActive,
      if (maxRedemptions != null) 'maxRedemptions': maxRedemptions,
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      'isExpired': isExpired,
      'redemptionsCount': redemptions.length,
      'redemptions': redemptions.map((item) => item.toPublicJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

ObjectId _parseObjectId(dynamic value) {
  if (value is ObjectId) {
    return value;
  }
  final rawValue = value?.toString().trim();
  if (rawValue != null && ObjectId.isValidHexId(rawValue)) {
    return ObjectId.fromHexString(rawValue);
  }
  return ObjectId();
}

String _normalizeAppId(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return 'psychology';
  }
  return normalized;
}

DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  final rawValue = value?.toString().trim();
  if (rawValue == null || rawValue.isEmpty) {
    return DateTime.now().toUtc();
  }
  return DateTime.tryParse(rawValue)?.toUtc() ?? DateTime.now().toUtc();
}

DateTime? _parseNullableDateTime(dynamic value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  final rawValue = value?.toString().trim();
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }
  return DateTime.tryParse(rawValue)?.toUtc();
}
