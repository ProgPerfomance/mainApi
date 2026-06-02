// Этот файл: lib/src/helper/parse_request_data_helper.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';

import 'package:shelf/shelf.dart';

// В shelf тело запроса читается как строка.
// Этот helper берёт JSON из body и превращает его в Map,
// чтобы controller мог обращаться к data['userId'], data['amount'] и т.д.
Future<Map<String, dynamic>> parseRequestDataHelper(Request request) async {
  /// Функция jsonDecode: выполняет шаг jsonDecode в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
  /// Возвращает значение типа return; это готовый результат для следующего шага программы.
  return jsonDecode(await request.readAsString());
}
