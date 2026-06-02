// Этот файл: lib/src/controller/character/character_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/character.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:shelf/shelf.dart';

/// Класс CharacterController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class CharacterController {
  /// Функция listCharacters: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listCharacters(Request request) async {
    try {
      final charactersCollection = MongoService.instance.db.collection(
        Collections.characters,
      );

      final rawCharacters = await charactersCollection.find().toList();
      final characters = rawCharacters.map(Character.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final languageCode =
          request.url.queryParameters['language'] ??
          request.headers['accept-language'];

      return ResponseHelper.success(
        data: characters
            .map((item) => item.toPublicJson(languageCode: languageCode))
            .toList(),
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }
}
