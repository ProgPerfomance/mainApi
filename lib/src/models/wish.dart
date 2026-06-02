// Этот файл: lib/src/models/wish.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';

const String defaultWishAppId = 'psychology';

/// Набор вариантов WishReaction: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
enum WishReaction {
  like,
  dislike;

  /// Функция parse: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа WishReaction; это готовый результат для следующего шага программы.
  static WishReaction parse(dynamic value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'like':
        return WishReaction.like;
      case 'dislike':
        return WishReaction.dislike;
      default:
        throw const FormatException(
          'Reaction must be either "like" or "dislike"',
        );
    }
  }

  /// Функция parseNullable: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа WishReaction?; это готовый результат для следующего шага программы.
  static WishReaction? parseNullable(dynamic value) {
    final normalizedValue = value?.toString().trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return null;
    }

    /// Функция parse: разбирает входные данные и возвращает их в понятном для программы виде.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return parse(normalizedValue);
  }

  /// Геттер counterField: читает значение counterField и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  String get counterField {
    switch (this) {
      case WishReaction.like:
        return 'likeCount';
      case WishReaction.dislike:
        return 'dislikeCount';
    }
  }
}

/// Класс Wish: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class Wish {
  final ObjectId? id;
  final ObjectId? requestId;
  final String appId;
  final String text;
  final int likeCount;
  final int dislikeCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Конструктор Wish: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  Wish({
    this.id,
    this.requestId,
    required String appId,
    required this.text,
    this.likeCount = 0,
    this.dislikeCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : appId = _normalizeAppId(appId),
       createdAt = (createdAt ?? DateTime.now().toUtc()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now().toUtc()).toUtc();

  /// Фабрика Wish.fromJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory Wish.fromJson(Map<String, dynamic> json) {
    /// Функция Wish: выполняет шаг Wish в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Wish(
      id: json['_id'] as ObjectId?,
      requestId: _parseObjectId(json['requestId']),
      appId:
          json['appId']?.toString() ??
          json['app_id']?.toString() ??
          defaultWishAppId,
      text: json['text'] as String? ?? '',
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      dislikeCount: (json['dislikeCount'] as num?)?.toInt() ?? 0,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      if (requestId != null) 'requestId': requestId,
      'appId': appId,
      'app_id': appId,
      'text': text,
      'likeCount': likeCount,
      'dislikeCount': dislikeCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      if (requestId != null) 'requestId': requestId?.oid,
      'appId': appId,
      'app_id': appId,
      'text': text,
      'likeCount': likeCount,
      'dislikeCount': dislikeCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Функция copyWith: возвращает копию объекта, где можно заменить только нужные поля.
  /// Возвращает значение типа Wish; это готовый результат для следующего шага программы.
  Wish copyWith({
    ObjectId? id,
    ObjectId? requestId,
    String? appId,
    String? text,
    int? likeCount,
    int? dislikeCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    /// Функция Wish: выполняет шаг Wish в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Wish(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      appId: appId ?? this.appId,
      text: text ?? this.text,
      likeCount: likeCount ?? this.likeCount,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Функция applyReaction: применяет действие к данным и возвращает обновлённый результат.
  /// Возвращает значение типа Wish; это готовый результат для следующего шага программы.
  Wish applyReaction({
    required WishReaction reaction,
    WishReaction? previousReaction,
    DateTime? reactedAt,
  }) {
    if (previousReaction == reaction) {
      return this;
    }

    var nextLikeCount = likeCount;
    var nextDislikeCount = dislikeCount;

    // Клиент хранит прошлую реакцию локально и отправляет её в API,
    // поэтому при смене выбора здесь нужно сперва откатить старый счётчик.
    if (previousReaction == WishReaction.like && nextLikeCount > 0) {
      nextLikeCount -= 1;
    }
    if (previousReaction == WishReaction.dislike && nextDislikeCount > 0) {
      nextDislikeCount -= 1;
    }

    if (reaction == WishReaction.like) {
      nextLikeCount += 1;
    } else {
      nextDislikeCount += 1;
    }

    /// Функция copyWith: возвращает копию объекта, где можно заменить только нужные поля.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return copyWith(
      likeCount: nextLikeCount,
      dislikeCount: nextDislikeCount,
      updatedAt: (reactedAt ?? DateTime.now().toUtc()).toUtc(),
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
