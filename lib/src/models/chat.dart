// Этот файл: lib/src/models/chat.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';

/// Класс Chat: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class Chat {
  final ObjectId? id;
  final ObjectId userId;
  final String title;
  final String? systemPrompt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastMessageAt;

  /// Конструктор Chat: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  Chat({
    this.id,
    required this.userId,
    required this.title,
    this.systemPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc(),
       lastMessageAt = lastMessageAt ?? DateTime.now().toUtc();

  /// Фабрика Chat.fromJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory Chat.fromJson(Map<String, dynamic> json) {
    /// Функция Chat: выполняет шаг Chat в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Chat(
      id: json['_id'] as ObjectId?,
      userId: json['userId'] as ObjectId,
      title: json['title'] as String? ?? 'New Chat',
      systemPrompt: json['systemPrompt'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      lastMessageAt: _parseDateTime(json['lastMessageAt']),
    );
  }

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'userId': userId,
      'title': title,
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastMessageAt': lastMessageAt.toIso8601String(),
    };
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      'userId': userId.oid,
      'title': title,
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastMessageAt': lastMessageAt.toIso8601String(),
    };
  }

  /// Функция copyWith: возвращает копию объекта, где можно заменить только нужные поля.
  /// Возвращает значение типа Chat; это готовый результат для следующего шага программы.
  Chat copyWith({
    ObjectId? id,
    ObjectId? userId,
    String? title,
    String? systemPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
  }) {
    /// Функция Chat: выполняет шаг Chat в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Chat(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
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
}
