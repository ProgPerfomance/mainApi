// Этот файл: lib/src/controller/wish/wish_request_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/wish_request.dart';
import 'package:main_api/src/services/auth/jwt_service.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// Класс WishRequestController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class WishRequestController {
  /// Функция createWishRequest: создаёт новую запись или объект и возвращает созданный результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> createWishRequest(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final userId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final wishRequest = _wishRequestFromRequest(
        data,
        userId: userId,
        appId: appId,
      );

      final result = await _wishRequestsCollection.insertOne(
        wishRequest.toJson(),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to create wish request',
          statusCode: 500,
        );
      }

      final rawWishRequest = await _wishRequestsCollection.findOne(
        where.eq('_id', result.id),
      );

      if (rawWishRequest == null) {
        return ResponseHelper.error(
          errorMessage: 'Failed to load created wish request',
          statusCode: 500,
        );
      }

      return ResponseHelper.success(
        statusCode: 201,
        data: WishRequest.fromJson(rawWishRequest).toPublicJson(),
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Геттер _wishRequestsCollection: читает значение _wishRequestsCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  static DbCollection get _wishRequestsCollection =>
      MongoService.instance.db.collection(Collections.wishRequests);

  /// Функция _wishRequestFromRequest: выполняет шаг _wishRequestFromRequest в этой части программы. Возвращает значение типа WishRequest; это готовый результат для следующего шага программы.
  /// Возвращает значение типа WishRequest; это готовый результат для следующего шага программы.
  static WishRequest _wishRequestFromRequest(
    Map<String, dynamic> data, {
    required ObjectId userId,
    required String appId,
  }) {
    final text = data['text']?.toString().trim() ?? '';

    if (text.isEmpty) {
      throw const FormatException('Text is required');
    }

    final now = DateTime.now().toUtc();

    /// Функция WishRequest: выполняет шаг WishRequest в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return WishRequest(
      userId: userId,
      appId: appId,
      text: text,
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _resolveAppId(Request request, [Map<String, dynamic>? data]) {
    return BillingService.normalizeAppId(
      data?['appId']?.toString() ??
          data?['app_id']?.toString() ??
          request.url.queryParameters['appId'] ??
          request.url.queryParameters['app_id'] ??
          request.headers['x-app-id'],
    );
  }
}
