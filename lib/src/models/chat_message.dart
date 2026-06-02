// Этот файл: lib/src/models/chat_message.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

enum ChatMessageRole { system, user, assistant }

/// Класс ChatMessage: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ChatMessage {
  final ChatMessageRole role;
  final String content;
  final String? provider;
  final String? model;
  final DateTime createdAt;

  /// Конструктор ChatMessage: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  ChatMessage({
    required this.role,
    required this.content,
    this.provider,
    this.model,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now().toUtc()).toUtc();

  /// Фабрика ChatMessage.fromClientJson: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory ChatMessage.fromClientJson(Map<String, dynamic> json) {
    // Это главный конструктор для сообщений, которые приходят с клиента.
    //
    // Клиент присылает обычный JSON вида:
    // {
    //   "role": "user",
    //   "content": "Мне тревожно",
    //   "createdAt": "..."
    // }
    //
    // Здесь мы:
    // - валидируем role
    // - приводим content к строке
    // - проверяем, что content не пустой
    // - аккуратно разбираем дату, если она пришла
    final role = _parseRole(json['role']);
    final content = json['content']?.toString().trim() ?? '';

    if (content.isEmpty) {
      throw const FormatException('Message content is required');
    }

    /// Функция ChatMessage: выполняет шаг ChatMessage в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return ChatMessage(
      role: role,
      content: content,
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  /// Фабрика ChatMessage.assistantReply: собирает объект из входных данных.
  /// Возвращает готовый объект этого класса.
  factory ChatMessage.assistantReply({
    required String content,
    required String model,
    String provider = 'deepseek',
  }) {
    // Этот конструктор используем уже после ответа модели.
    // То есть это не "сырой клиентский JSON", а уже наше серверное
    // представление готового сообщения ассистента.
    return ChatMessage(
      role: ChatMessageRole.assistant,
      content: content.trim(),
      provider: provider,
      model: model,
    );
  }

  /// Функция toPublicJson: возвращает безопасный JSON без лишних внутренних данных.
  /// Возвращает текст.
  Map<String, dynamic> toPublicJson() {
    // Это формат, который вернём обратно клиенту через API.
    return {
      'role': role.name,
      'content': content,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Функция toDeepSeekMessage: выполняет шаг toDeepSeekMessage в этой части программы. Возвращает текст.
  /// Возвращает текст.
  Map<String, String> toDeepSeekMessage() {
    // DeepSeek ожидает простой формат role/content,
    // поэтому server metadata типа provider/model тут не нужны.
    return {'role': role.name, 'content': content};
  }

  /// Функция _parseRole: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа ChatMessageRole; это готовый результат для следующего шага программы.
  static ChatMessageRole _parseRole(dynamic value) {
    // Валидируем роль сообщения строго по enum:
    // system / user / assistant
    final normalizedValue = value?.toString().trim() ?? '';

    for (final role in ChatMessageRole.values) {
      if (role.name == normalizedValue) {
        return role;
      }
    }

    /// Функция FormatException: приводит значение к красивому текстовому виду и возвращает строку.
    /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
    throw FormatException(
      'Unsupported message role "$normalizedValue". '
      'Allowed roles: ${ChatMessageRole.values.map((item) => item.name).join(', ')}',
    );
  }

  /// Функция _parseDateTime: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа DateTime?; это готовый результат для следующего шага программы.
  static DateTime? _parseDateTime(dynamic value) {
    // createdAt с клиента опционален:
    // если даты нет, просто оставим null, а конструктор поставит текущее время.
    if (value is DateTime) {
      return value.toUtc();
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.parse(value).toUtc();
    }

    return null;
  }
}
