// Этот файл: lib/src/models/wish_request.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';
import 'package:main_api/src/models/wish.dart';

/// Класс WishRequest: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class WishRequest {
  final ObjectId? id;
  final ObjectId? userId;
  final String appId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Конструктор WishRequest: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  WishRequest({
    this.id,
    this.userId,
    required String appId,
    required this.text,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : appId = _normalizeAppId(appId),
       createdAt = (createdAt ?? DateTime.now().toUtc()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now().toUtc()).toUtc();

  /// Фабрика WishRequest.fromJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory WishRequest.fromJson(Map<String, dynamic> json) {
    /// Функция WishRequest: выполняет шаг WishRequest в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return WishRequest(
      id: json['_id'] as ObjectId?,
      userId: _parseObjectId(json['userId']),
      appId:
          json['appId']?.toString() ??
          json['app_id']?.toString() ??
          defaultWishAppId,
      text: json['text'] as String? ?? '',
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      if (userId != null) 'userId': userId,
      'appId': appId,
      'app_id': appId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      if (userId != null) 'userId': userId?.oid,
      'appId': appId,
      'app_id': appId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Функция copyWith: возвращает копию объекта, где можно заменить только нужные поля.
  /// Возвращает значение типа WishRequest; это готовый результат для следующего шага программы.
  WishRequest copyWith({
    ObjectId? id,
    ObjectId? userId,
    String? appId,
    String? text,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    /// Функция WishRequest: выполняет шаг WishRequest в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return WishRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      appId: appId ?? this.appId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Функция _parseDateTime: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа DateTime; это готовый результат для следующего шага программы.
  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value.toUtc();
    }

    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value).toUtc();
    }

    return DateTime.now().toUtc();
  }

  static ObjectId? _parseObjectId(dynamic value) {
    if (value == null) return null;
    if (value is ObjectId) return value;
    final normalized = value.toString().trim();
    if (normalized.isEmpty) return null;
    if (!ObjectId.isValidHexId(normalized)) return null;
    return ObjectId.fromHexString(normalized);
  }

  static String _normalizeAppId(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return defaultWishAppId;
    }
    return normalized;
  }
}
