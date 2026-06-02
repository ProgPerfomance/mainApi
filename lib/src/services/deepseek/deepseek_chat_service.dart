// Этот файл: lib/src/services/deepseek/deepseek_chat_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:dio/dio.dart';
import 'package:main_api/src/services/app_config.dart';

/// Это короткий итог ответа от внешнего AI-сервиса.
///
/// Для владельца проекта здесь важны только два поля:
/// - `content`: что именно увидит клиент в чате;
/// - `model`: какая модель DeepSeek сгенерировала этот ответ.
///
/// Все остальные технические детали ответа провайдера на продукт напрямую не влияют,
/// поэтому мы их здесь не храним.
class DeepSeekChatCompletionResult {
  final String content;
  final String model;

  const DeepSeekChatCompletionResult({
    required this.content,
    required this.model,
  });
}

/// Класс DeepSeekChatService: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class DeepSeekChatService {
  /// Конструктор DeepSeekChatService._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  DeepSeekChatService._();

  static final DeepSeekChatService instance = DeepSeekChatService._();

  // Это единая точка подключения проекта к DeepSeek.
  //
  // Смысл для бизнеса:
  // - здесь зафиксирован внешний AI-провайдер;
  // - здесь заданы лимиты ожидания ответа;
  // - если в будущем понадобится сменить провайдера или условия интеграции,
  //   это делается в одном понятном месте.
  final Dio _dio = Dio(
    /// Конструктор BaseOptions: создаёт новый объект этого класса.
    /// Возвращает готовый объект, с которым дальше работает приложение.
    BaseOptions(
      baseUrl: 'https://api.deepseek.com',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Функция generateReply: создаёт новое значение и возвращает его.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<DeepSeekChatCompletionResult> generateReply({
    required List<Map<String, String>> messages,
    String model = 'deepseek-chat',
  }) async {
    // Если истории сообщений нет, AI вызывать нельзя:
    // у системы просто нет основы для ответа пользователю.
    //
    // Это также защищает проект от пустых запросов,
    // за которые не должно происходить ни ответа, ни списания.
    if (messages.isEmpty) {
      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError('DeepSeek request messages are empty');
    }

    try {
      // Это сам запрос во внешний AI.
      //
      // На вход уже приходит полностью подготовленный пакет данных:
      // - история диалога;
      // - системные правила;
      // - язык ответа;
      // - выбранная модель.
      //
      // Этот слой не решает, что AI "должен сказать" по смыслу.
      // Его задача уже прикладная: отправить подготовленные данные в DeepSeek
      // и вернуть результат обратно в чатовый сервис проекта.
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/completions',
        data: {
          'model': model,
          'messages': messages,
          'stream': false,
        }, //а тут параметры задаем которые выше приняли
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AppConfig.deepSeekApiKey}',
          }, //тут авторизация с токеном
        ),
      );

      // Здесь лежит ответ внешнего провайдера в уже разобранном JSON-виде.
      // Если он пустой, такой ответ нельзя считать рабочим для продукта.
      final data = response.data;
      if (data == null) {
        /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw StateError(
          'DeepSeek returned an empty response',
        ); //если дипсик ничего не ответил
      }

      // Внешний AI может вернуть несколько вариантов ответа.
      // Для текущего продукта используется первый вариант как основной.
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw StateError('DeepSeek response does not contain choices');
      }

      final firstChoice = choices.first; // это его ответ
      if (firstChoice is! Map<String, dynamic>) {
        /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw StateError('DeepSeek response choice has invalid format');
      }

      // Внутри выбранного варианта нас интересует конкретное сообщение AI,
      // то есть тот текст, который затем попадёт пользователю в чат.
      final message = firstChoice['message'];
      if (message is! Map<String, dynamic>) {
        /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw StateError('DeepSeek response message has invalid format');
      }

      // Провайдер может прислать ответ в разном внутреннем формате,
      // но для бизнеса результат всегда должен быть один:
      // готовый цельный текст для показа клиенту.
      final content = _extractContent(message['content']).trim();
      if (content.isEmpty) {
        /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw StateError('DeepSeek returned an empty message');
      }

      /// Функция DeepSeekChatCompletionResult: выполняет шаг DeepSeekChatCompletionResult в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
      /// Возвращает значение типа return; это готовый результат для следующего шага программы.
      return DeepSeekChatCompletionResult(
        content: content,
        model: data['model']?.toString() ?? model,
      );
    } on DioException catch (error) {
      // а тут ошибку ловим если есть
      //Этот код запустится если ошибка случилась
      // Если внешний AI недоступен или ответил ошибкой,
      // сохраняем максимум деталей.
      //
      // Это помогает владельцу проекта и поддержке быстрее понять,
      // проблема на нашей стороне или у внешнего провайдера.
      final details = error.response?.data;

      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError(
        //а тут мы её фиксируем
        'DeepSeek request failed'
        '${error.response?.statusCode != null ? ' (${error.response?.statusCode})' : ''}'
        '${details != null ? ': $details' : ': ${error.message}'}',
      );
    }
  }

  /// Функция _extractContent: выполняет шаг _extractContent в этой части программы. Возвращает текст.
  /// Возвращает текст.
  String _extractContent(dynamic content) {
    // Лучший сценарий:
    // провайдер сразу вернул готовый цельный текст.
    if (content is String) {
      return content;
    }

    if (content is List) {
      // Иногда ответ приходит частями.
      // Для пользователя это всё равно должен быть один связный текст,
      // поэтому здесь части аккуратно склеиваются.
      final buffer = StringBuffer();

      for (final item in content) {
        // Наиболее частый формат: объект с полем text.
        if (item is Map<String, dynamic> && item['text'] != null) {
          buffer.writeln(item['text'].toString());
        } else if (item is String) {
          // Резервный вариант: часть пришла просто строкой.
          buffer.writeln(item);
        }
      }

      return buffer.toString().trim();
    }
    return content?.toString() ??
        ''; //а это если сообщение пришло не такое как должно быть от дипсика (вообще нулевая вероятность практически, но бывает)
  }
}
