// Этот файл: lib/src/helper/response_helper.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'package:shelf/shelf.dart';

/// ResponseHelper собирает ответы backend в одном формате.
/// Так фронту проще: он всегда ждёт либо status=success, либо status=error.
class ResponseHelper {
  /// Успешный ответ.
  /// data - полезная информация, например пользователь или новый баланс.
  static Response success({required dynamic data, int statusCode = 200}) {
    /// Функция Response: выполняет шаг Response в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Response(
      statusCode,
      body: jsonEncode({'status': 'success', 'data': data}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Ошибка.
  /// errorMessage - текст для человека.
  /// errorCode/details - машинные детали, по которым фронт может понять тип ошибки.
  static Response error({
    required String errorMessage,
    int statusCode = 400,
    String? errorCode,
    Map<String, dynamic>? details,
  }) {
    // Собираем JSON вручную, чтобы не добавлять пустые поля.
    final payload = <String, dynamic>{
      'status': 'error',
      'errorMessage': errorMessage,
    };

    // errorCode нужен для особых случаев:
    // например INSUFFICIENT_BALANCE или PURCHASE_ALREADY_APPLIED.
    if (errorCode != null && errorCode.isNotEmpty) {
      payload['errorCode'] = errorCode;
    }

    // details хранит дополнительные числа/данные,
    // например сколько денег не хватает.
    if (details != null && details.isNotEmpty) {
      payload['details'] = details;
    }

    /// Функция Response: выполняет шаг Response в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Response(
      statusCode,
      body: jsonEncode(payload),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
