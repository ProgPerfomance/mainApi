// Этот файл: lib/src/controller/chat/chat_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/auth/jwt_service.dart';
import 'package:main_api/src/services/chat/chat_service.dart';
import 'package:shelf/shelf.dart';

/// Класс ChatController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ChatController {
  // Старые chat endpoints оставлены как явная подсказка клиенту.
  //
  // Для продукта это означает:
  // история переписки теперь хранится на стороне мобильного приложения,
  // а сервер отвечает только за генерацию нового AI-ответа.
  static const String _clientStorageOnlyMessage =
      'Chats and messages are now stored on the client. '
      'Send the full conversation in the "messages" array to /api/v1/chats/send.';

  /// Функция createChat: создаёт новую запись или объект и возвращает созданный результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> createChat(Request request) async {
    return ResponseHelper.error(
      errorMessage: _clientStorageOnlyMessage,
      statusCode: 410,
    );
  }

  /// Функция listChats: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listChats(Request request) async {
    return ResponseHelper.error(
      errorMessage: _clientStorageOnlyMessage,
      statusCode: 410,
    );
  }

  /// Функция listMessages: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listMessages(Request request) async {
    return ResponseHelper.error(
      errorMessage: _clientStorageOnlyMessage,
      statusCode: 410,
    );
  }

  /// Функция sendMessage: отправляет данные и возвращает ответ или результат отправки.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> sendMessage(Request request) async {
    try {
      // Контроллер принимает данные от мобильного клиента.
      final data = await parseRequestDataHelper(request);

      // Контроллер сам не принимает ключевых продуктовых решений.
      //
      // Его роль простая:
      // - принять запрос;
      // - передать данные в основной сервис чата;
      // - вернуть клиенту готовый ответ в понятном формате.
      //
      // Вся основная логика находится в ChatService:
      // там выбирается роль психолога, язык ответа, работа с AI и оплата.
      final userId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final result = await ChatService.instance.sendMessage(
        userId: userId.oid,
        messages: data['messages'],
        characterId: data['characterId']?.toString(),
        systemPrompt: data['systemPrompt']?.toString(),
        languageCode: data['language']?.toString(),
        appId:
            data['appId']?.toString() ??
            data['app_id']?.toString() ??
            request.headers['x-app-id'],
      );

      // Если всё прошло успешно, клиент получает:
      // - новый ответ психолога;
      // - информацию о списании за этот AI-ответ.
      return ResponseHelper.success(data: result.toJson());
    } on ChatServiceException catch (error) {
      // Это ожидаемые рабочие ошибки продукта:
      // например, недостаточно средств или некорректная история переписки.
      //
      // Их важно отдавать в управляемом виде,
      // чтобы приложение могло показать понятное сообщение пользователю.
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      // Всё неожиданное считаем внутренней ошибкой сервера.
      // Это уже не нормальный сценарий продукта, а технический сбой.
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }
}
