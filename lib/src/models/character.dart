// Этот файл: lib/src/models/character.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';

/// Класс Character: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class Character {
  final ObjectId? id;
  final String name;
  final String avatarUrl;
  final String systemPrompt;
  final String shortDescription;
  final String longDescription;
  final Map<String, String> localizedNames;
  final Map<String, String> localizedShortDescriptions;
  final Map<String, String> localizedLongDescriptions;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Конструктор Character: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  Character({
    this.id,
    required this.name,
    required this.avatarUrl,
    required this.systemPrompt,
    String? shortDescription,
    String? longDescription,
    String? greetingText,
    Map<String, String>? localizedNames,
    Map<String, String>? localizedShortDescriptions,
    Map<String, String>? localizedLongDescriptions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : shortDescription = _fallbackText(shortDescription, greetingText ?? ''),
       longDescription = _fallbackText(
         longDescription,
         _fallbackText(shortDescription, greetingText ?? ''),
       ),
       localizedNames = Map.unmodifiable(
         _normalizeLocalizedTextMap(localizedNames),
       ),
       localizedShortDescriptions = Map.unmodifiable(
         _normalizeLocalizedTextMap(localizedShortDescriptions),
       ),
       localizedLongDescriptions = Map.unmodifiable(
         _normalizeLocalizedTextMap(localizedLongDescriptions),
       ),
       createdAt = (createdAt ?? DateTime.now().toUtc()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now().toUtc()).toUtc();

  /// Фабрика Character.fromJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory Character.fromJson(Map<String, dynamic> json) {
    final greetingText = json['greetingText'] as String? ?? '';
    final shortDescription = _fallbackText(
      json['shortDescription'] as String?,
      greetingText,
    );

    /// Функция Character: выполняет шаг Character в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Character(
      id: json['_id'] as ObjectId?,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      shortDescription: shortDescription,
      longDescription: _fallbackText(
        json['longDescription'] as String?,
        shortDescription,
      ),
      localizedNames: _parseLocalizedTextMap(json['localizedNames']),
      localizedShortDescriptions: _parseLocalizedTextMap(
        json['localizedShortDescriptions'],
      ),
      localizedLongDescriptions: _parseLocalizedTextMap(
        json['localizedLongDescriptions'],
      ),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'systemPrompt': systemPrompt,
      'shortDescription': shortDescription,
      'longDescription': longDescription,
      'localizedNames': localizedNames,
      'localizedShortDescriptions': localizedShortDescriptions,
      'localizedLongDescriptions': localizedLongDescriptions,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson({
    String? languageCode,
    bool includeLocalizedDescriptions = false,
  }) {
    final nameForLanguage = localizedName(languageCode);
    final shortDescriptionForLanguage = localizedShortDescription(languageCode);
    final longDescriptionForLanguage = localizedLongDescription(languageCode);

    return {
      '_id': id?.oid,
      'name': nameForLanguage,
      'avatarUrl': avatarUrl,
      'systemPrompt': systemPrompt,
      'shortDescription': shortDescriptionForLanguage,
      'longDescription': longDescriptionForLanguage,
      if (includeLocalizedDescriptions) 'localizedNames': localizedNames,
      if (includeLocalizedDescriptions)
        'localizedShortDescriptions': localizedShortDescriptions,
      if (includeLocalizedDescriptions)
        'localizedLongDescriptions': localizedLongDescriptions,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  String localizedName(String? languageCode) {
    return _localizedText(localizedNames, languageCode, fallback: name);
  }

  String localizedShortDescription(String? languageCode) {
    return _localizedText(
      localizedShortDescriptions,
      languageCode,
      fallback: shortDescription,
    );
  }

  String localizedLongDescription(String? languageCode) {
    return _localizedText(
      localizedLongDescriptions,
      languageCode,
      fallback: longDescription,
    );
  }

  /// Функция copyWith: возвращает копию объекта, где можно заменить только нужные поля.
  /// Возвращает значение типа Character; это готовый результат для следующего шага программы.
  Character copyWith({
    ObjectId? id,
    String? name,
    String? avatarUrl,
    String? systemPrompt,
    String? shortDescription,
    String? longDescription,
    Map<String, String>? localizedNames,
    Map<String, String>? localizedShortDescriptions,
    Map<String, String>? localizedLongDescriptions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    /// Функция Character: выполняет шаг Character в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Character(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      shortDescription: shortDescription ?? this.shortDescription,
      longDescription: longDescription ?? this.longDescription,
      localizedNames: localizedNames ?? this.localizedNames,
      localizedShortDescriptions:
          localizedShortDescriptions ?? this.localizedShortDescriptions,
      localizedLongDescriptions:
          localizedLongDescriptions ?? this.localizedLongDescriptions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _localizedText(
    Map<String, String> values,
    String? languageCode, {
    required String fallback,
  }) {
    final normalizedCode = languageCode
        ?.split(',')
        .first
        .split('-')
        .first
        .trim()
        .toLowerCase();
    if (normalizedCode == null || normalizedCode == 'ru') {
      return fallback;
    }

    final localizedValue = values[normalizedCode]?.trim();
    return localizedValue == null || localizedValue.isEmpty
        ? fallback
        : localizedValue;
  }

  static Map<String, String> _parseLocalizedTextMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    return _normalizeLocalizedTextMap(
      value.map(
        (key, rawValue) => MapEntry(key.toString(), rawValue?.toString() ?? ''),
      ),
    );
  }

  static Map<String, String> _normalizeLocalizedTextMap(
    Map<String, String>? value,
  ) {
    if (value == null || value.isEmpty) {
      return const {};
    }

    final normalized = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.trim().toLowerCase();
      final text = entry.value.trim();
      if ((key == 'en' || key == 'be') && text.isNotEmpty) {
        normalized[key] = text;
      }
    }
    return normalized;
  }

  /// Функция _fallbackText: выполняет шаг _fallbackText в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static String _fallbackText(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
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
