// Этот файл: lib/src/services/chat/chat_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/models/character.dart';
import 'package:main_api/src/models/chat_message.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/deepseek/deepseek_chat_service.dart';
import 'package:main_api/src/services/deepseek/rules.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Класс ChatServiceException: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ChatServiceException implements Exception {
  final String message;
  final int statusCode;
  final String? errorCode;
  final Map<String, dynamic>? details;

  const ChatServiceException(
    this.message, {
    this.statusCode = 400,
    this.errorCode,
    this.details,
  });

  /// Функция toString: выполняет шаг toString в этой части программы. Возвращает текст.
  /// Возвращает текст.
  @override
  String toString() => message;
}

// Это готовый результат одного обращения пользователя в чат.
//
// Для владельца проекта здесь важно два блока:
// - какой ответ увидит клиент;
// - что произошло с оплатой за этот AI-ответ.
class ChatSendResult {
  final ChatMessage assistantMessage;
  final Map<String, dynamic> billing;

  const ChatSendResult({required this.assistantMessage, required this.billing});

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      'assistantMessage': assistantMessage.toPublicJson(),
      'billing': billing,
    };
  }
}

/// Класс ChatService: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ChatService {
  /// Конструктор ChatService._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  ChatService._();

  static final ChatService instance = ChatService._();

  /// Геттер _db: читает значение _db и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа Db; это готовый результат для следующего шага программы.
  Db get _db => MongoService.instance.db;

  /// Геттер _charactersCollection: читает значение _charactersCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  DbCollection get _charactersCollection =>
      _db.collection(Collections.characters);

  /// Функция sendMessage: отправляет данные и возвращает ответ или результат отправки.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<ChatSendResult> sendMessage({
    required String userId,
    required dynamic messages,
    String? characterId,
    String? systemPrompt,
    String? languageCode,
    String? appId,
  }) async {
    // Сначала проверяем, что пользователь корректен
    // и в целом может получить платный AI-ответ.
    //
    // Это защита продукта от лишних внешних запросов:
    // если пользователь не найден или у него недостаточно средств,
    // мы не идём в AI вообще.
    final userObjectId = _parseObjectId(userId, fieldName: 'User ID');
    final chargePreparation = await _prepareAiRequestCharge(
      userObjectId,
      appId: appId,
    );

    // Здесь входящая история приводится к внутреннему стандарту проекта.
    //
    // Проще говоря:
    // из сырого JSON от клиента мы делаем понятные и проверенные сообщения,
    // с которыми уже можно безопасно работать дальше.
    final parsedMessages = _parseMessages(messages);
    final nonSystemMessages = parsedMessages
        .where((message) => message.role != ChatMessageRole.system)
        .toList();

    // Если в переписке нет живых реплик, AI отвечать не на что.
    // Одних внутренних правил поведения недостаточно.
    if (nonSystemMessages.isEmpty) {
      throw const ChatServiceException(
        'Messages must contain at least one user or assistant message',
      );
    }

    // По текущей логике мобильное приложение присылает всю историю диалога целиком.
    // Последним всегда должно быть сообщение пользователя,
    // потому что именно на него AI сейчас и отвечает.
    if (nonSystemMessages.last.role != ChatMessageRole.user) {
      throw const ChatServiceException(
        'The last message in "messages" must have role "user"',
      );
    }

    // На этом шаге определяется основная роль AI в диалоге.
    //
    // Приоритет такой:
    // 1. Явно переданный prompt
    // 2. Настройка выбранного психолога
    // 3. Базовое правило по умолчанию
    //
    // Это позволяет продукту использовать максимально точный сценарий общения.
    final normalizedSystemPrompt = await _resolveSystemPrompt(
      characterId: characterId,
      systemPrompt: systemPrompt,
    );
    final deepSeekMessages = _buildDeepSeekMessages(
      messages: parsedMessages,
      systemPrompt: normalizedSystemPrompt,
      languageCode: languageCode,
    );

    // Здесь у проекта уже есть всё, что нужно для AI:
    // - корректная история;
    // - выбранная роль психолога;
    // - понятный язык ответа;
    // - предварительная финансовая проверка.
    //
    // После этого можно обращаться во внешний AI.
    final completion = await DeepSeekChatService.instance.generateReply(
      messages: deepSeekMessages,
    );
    // Деньги списываются только после успешного ответа AI.
    // Это важно для доверия пользователя: оплата происходит за результат,
    // а не просто за попытку обращения.
    final chargeResult = await _chargeSuccessfulAiRequest(
      userId: userObjectId,
      userName: chargePreparation.user.name,
      requestPrice: chargePreparation.requestPrice,
      sessionStartedAt: chargePreparation.sessionStartedAt,
      sessionRequestIndex: chargePreparation.sessionRequestIndex,
      appId: appId,
    );

    /// Функция ChatSendResult: выполняет шаг ChatSendResult в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return ChatSendResult(
      assistantMessage: ChatMessage.assistantReply(
        content: completion.content,
        model: completion.model,
      ),
      billing: chargeResult.toJson(),
    );
  }

  /// Функция _findCharacter: выполняет шаг _findCharacter в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<Character> _findCharacter(ObjectId characterId) async {
    final rawCharacter = await _charactersCollection.findOne(
      where.eq('_id', characterId),
    );

    if (rawCharacter == null) {
      throw const ChatServiceException(
        'Psychologist not found',
        statusCode: 404,
      );
    }

    return Character.fromJson(rawCharacter);
  }

  /// Функция _parseMessages: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает список значений.
  List<ChatMessage> _parseMessages(dynamic rawMessages) {
    // Клиент обязан прислать именно список сообщений.
    // Любой другой формат считаем ошибкой запроса.
    if (rawMessages is! List) {
      throw const ChatServiceException(
        'Messages are required and must be an array',
      );
    }

    final messages = <ChatMessage>[];

    for (var index = 0; index < rawMessages.length; index++) {
      final rawMessage = rawMessages[index];
      if (rawMessage is! Map) {
        /// Функция ChatServiceException: выполняет шаг ChatServiceException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw ChatServiceException('Message at index $index must be an object');
      }

      try {
        // Проверяем историю по каждому сообщению отдельно.
        // Это помогает быстрее понять, где именно проблема в данных клиента.
        messages.add(
          /// Конструктор ChatMessage.fromClientJson: создаёт новый объект этого класса.
          /// Возвращает готовый объект, с которым дальше работает приложение.
          ChatMessage.fromClientJson(Map<String, dynamic>.from(rawMessage)),
        );
      } on FormatException catch (error) {
        /// Функция ChatServiceException: выполняет шаг ChatServiceException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw ChatServiceException(
          'Message at index $index is invalid: ${error.message}',
        );
      }
    }

    if (messages.isEmpty) {
      throw const ChatServiceException('Messages array must not be empty');
    }

    return messages;
  }

  /// Функция _buildDeepSeekMessages: собирает и возвращает видимый кусок экрана, который пользователь видит в приложении.
  /// Возвращает текст.
  List<Map<String, String>> _buildDeepSeekMessages({
    required List<ChatMessage> messages,
    required String? systemPrompt,
    required String? languageCode,
  }) {
    // Это финальный пакет данных, который уходит во внешний AI.
    //
    // Здесь соединяются:
    // - правила поведения психолога;
    // - правило по языку;
    // - сама история общения.
    final requestMessages = <Map<String, String>>[];
    final languageInstruction = deepSeekLanguageInstructionForCode(
      languageCode,
    );

    // Если уже есть отдельная роль психолога,
    // системные сообщения из истории не должны ей противоречить.
    final normalizedHistory = messages
        .where((message) => message.role != ChatMessageRole.system)
        .map((message) => message.toDeepSeekMessage());

    if (systemPrompt != null) {
      // Если роль AI уже явно определена, ставим её первой.
      // Для внешней модели это главный ориентир поведения.
      requestMessages.add({
        'role': ChatMessageRole.system.name,
        'content': systemPrompt,
      });
    } else {
      // Если отдельной настройки нет,
      // пробуем использовать системные сообщения из самой истории.
      final systemMessages = messages
          .where((message) => message.role == ChatMessageRole.system)
          .map((message) => message.toDeepSeekMessage())
          .toList();

      if (systemMessages.isNotEmpty) {
        requestMessages.addAll(systemMessages);
      } else {
        // Даже без персональной настройки AI всё равно получает
        // минимальное базовое правило поведения.
        requestMessages.add({
          'role': ChatMessageRole.system.name,
          'content': defaultDeepSeekSystemPrompt,
        });
      }
    }

    // Язык ответа добавляется отдельно,
    // чтобы его можно было менять независимо от роли психолога.
    if (languageInstruction != null) {
      requestMessages.add({
        'role': ChatMessageRole.system.name,
        'content': languageInstruction,
      });
    }

    // После всех правил добавляется сама переписка,
    // чтобы AI видел полный контекст разговора.
    requestMessages.addAll(normalizedHistory);
    return requestMessages;
  }

  /// Функция _parseObjectId: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа ObjectId; это готовый результат для следующего шага программы.
  ObjectId _parseObjectId(String value, {required String fieldName}) {
    // Это базовая защита от некорректного идентификатора.
    // Если ID сломан, дальше по процессу идти нельзя.
    if (!ObjectId.isValidHexId(value)) {
      /// Функция ChatServiceException: выполняет шаг ChatServiceException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw ChatServiceException('Invalid ${fieldName.toLowerCase()} format');
    }

    return ObjectId.fromHexString(value);
  }

  /// Функция _normalizeOptionalString: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает текст или пустое значение, если текста нет.
  String? _normalizeOptionalString(String? value) {
    // Служебная очистка строк:
    // пустые значения превращаем в null,
    // а полезные аккуратно обрезаем по краям.
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  /// Функция _resolveSystemPrompt: выполняет шаг _resolveSystemPrompt в этой части программы. Возвращает текст или пустое значение, если текста нет.
  /// Возвращает текст или пустое значение, если текста нет.
  Future<String?> _resolveSystemPrompt({
    required String? characterId,
    required String? systemPrompt,
  }) async {
    // Если prompt уже пришёл напрямую, он самый приоритетный.
    final normalizedSystemPrompt = _normalizeOptionalString(systemPrompt);
    if (normalizedSystemPrompt != null) {
      return normalizedSystemPrompt;
    }

    // Если прямой настройки нет, пробуем взять её из выбранного психолога.
    final normalizedCharacterId = _normalizeOptionalString(characterId);
    if (normalizedCharacterId == null) {
      return null;
    }

    final characterObjectId = _parseObjectId(
      normalizedCharacterId,
      fieldName: 'Psychologist ID',
    );
    // Это позволяет каждому психологу иметь свой собственный сценарий общения.
    final character = await _findCharacter(characterObjectId);
    return character.systemPrompt;
  }

  /// Функция _prepareAiRequestCharge: выполняет шаг _prepareAiRequestCharge в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<AiRequestChargePreparation> _prepareAiRequestCharge(
    ObjectId userId, {
    String? appId,
  }) async {
    try {
      return await BillingService.instance.prepareAiRequestCharge(
        userId,
        appId: appId,
      );
    } on BillingServiceException catch (error) {
      // Биллинг знает всё про оплату и баланс.
      // Чатовый слой здесь просто переводит эту ошибку
      // в формат, понятный chat API.
      throw ChatServiceException(
        error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    }
  }

  /// Функция _chargeSuccessfulAiRequest: выполняет шаг _chargeSuccessfulAiRequest в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<AiRequestChargeResult> _chargeSuccessfulAiRequest({
    required ObjectId userId,
    required String userName,
    required double requestPrice,
    required DateTime sessionStartedAt,
    required int sessionRequestIndex,
    String? appId,
  }) async {
    try {
      return await BillingService.instance.chargeSuccessfulAiRequest(
        userId: userId,
        userName: userName,
        requestPrice: requestPrice,
        sessionStartedAt: sessionStartedAt,
        sessionRequestIndex: sessionRequestIndex,
        appId: appId,
      );
    } on BillingServiceException catch (error) {
      /// Функция ChatServiceException: выполняет шаг ChatServiceException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw ChatServiceException(
        error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    }
  }
}
