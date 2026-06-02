// Этот файл: lib/src/services/chat/chat_websocket_handler.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'dart:io';

import 'package:main_api/src/services/auth/jwt_service.dart';
import 'package:main_api/src/services/chat/chat_service.dart';

/// Класс ChatWebSocketHandler: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ChatWebSocketHandler {
  /// Конструктор ChatWebSocketHandler._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  ChatWebSocketHandler._();

  static const String _clientStorageOnlyMessage =
      'Chats and messages are now stored on the client. '
      'Send the full conversation in the "messages" array to /api/v1/chats/send.';

  /// Функция handle: обрабатывает событие или запрос и возвращает результат обработки.
  /// Возвращает ожидание завершения работы, но не возвращает отдельное значение.
  static Future<void> handle(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'status': 'error',
            'errorMessage': 'WebSocket upgrade expected',
          }),
        );
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);

    _send(socket, {
      'type': 'connected',
      'data': {'message': 'Chat WebSocket connected'},
    });

    socket.listen(
      (payload) async {
        if (payload is! String) {
          _sendError(socket, 'Only text frames are supported');
          return;
        }

        Map<String, dynamic> data;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) {
            _sendError(socket, 'Payload must be a JSON object');
            return;
          }
          data = decoded;
        } catch (_) {
          _sendError(socket, 'Invalid JSON payload');
          return;
        }

        final action = data['action']?.toString();
        if (action == null || action.isEmpty) {
          _sendError(socket, 'Action is required');
          return;
        }

        try {
          switch (action) {
            case 'create_chat':
              _sendError(
                socket,
                _clientStorageOnlyMessage,
                statusCode: HttpStatus.gone,
                action: action,
              );
              break;
            case 'list_chats':
              _sendError(
                socket,
                _clientStorageOnlyMessage,
                statusCode: HttpStatus.gone,
                action: action,
              );
              break;
            case 'list_messages':
              _sendError(
                socket,
                _clientStorageOnlyMessage,
                statusCode: HttpStatus.gone,
                action: action,
              );
              break;
            case 'send_message':
              _send(socket, {
                'type': 'message_processing',
                'data': {
                  'messageCount': (data['messages'] as List?)?.length ?? 0,
                  'characterId': data['characterId']?.toString(),
                },
              });

              final userId = JwtService.instance.verifyToken(
                data['token']?.toString() ?? '',
              );
              final requestedUserId = data['userId']?.toString();
              if (requestedUserId != null &&
                  requestedUserId.isNotEmpty &&
                  requestedUserId != userId.oid) {
                throw const JwtAuthException(
                  'Authorization token does not match user',
                  statusCode: HttpStatus.forbidden,
                );
              }

              final result = await ChatService.instance.sendMessage(
                userId: userId.oid,
                messages: data['messages'],
                characterId: data['characterId']?.toString(),
                systemPrompt: data['systemPrompt']?.toString(),
                appId: data['appId']?.toString() ?? data['app_id']?.toString(),
              );

              _send(socket, {
                'type': 'message_result',
                'data': result.toJson(),
              });
              break;
            default:
              _sendError(socket, 'Unsupported action: $action');
          }
        } on ChatServiceException catch (error) {
          _sendError(
            socket,
            error.message,
            statusCode: error.statusCode,
            action: action,
            errorCode: error.errorCode,
            details: error.details,
          );
        } on JwtAuthException catch (error) {
          _sendError(
            socket,
            error.message,
            statusCode: error.statusCode,
            action: action,
          );
        } catch (error) {
          _sendError(
            socket,
            error.toString(),
            statusCode: HttpStatus.internalServerError,
            action: action,
          );
        }
      },
      onError: (_) => socket.close(),
      onDone: () => socket.close(),
      cancelOnError: true,
    );
  }

  /// Функция _send: отправляет данные и возвращает ответ или результат отправки.
  /// Ничего не возвращает, только выполняет действие.
  static void _send(WebSocket socket, Map<String, dynamic> payload) {
    socket.add(jsonEncode(payload));
  }

  /// Функция _sendError: отправляет данные и возвращает ответ или результат отправки.
  /// Ничего не возвращает, только выполняет действие.
  static void _sendError(
    WebSocket socket,
    String message, {
    int statusCode = HttpStatus.badRequest,
    String? action,
    String? errorCode,
    Map<String, dynamic>? details,
  }) {
    final error = <String, dynamic>{
      'message': message,
      'statusCode': statusCode,
      'action': action,
    };

    if (errorCode != null && errorCode.isNotEmpty) {
      error['errorCode'] = errorCode;
    }

    if (details != null && details.isNotEmpty) {
      error['details'] = details;
    }

    _send(socket, {'type': 'error', 'error': error});
  }
}
