// Этот файл: lib/src/controller/wish/wish_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/wish.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// Класс WishController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class WishController {
  /// Функция listWishes: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listWishes(Request request) async {
    try {
      final appId = _resolveAppId(request);
      final rawWishes = await _wishesCollection
          .find(where.eq('appId', appId))
          .toList();
      final wishes = rawWishes.map(Wish.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return ResponseHelper.success(
        data: wishes.map((item) => item.toPublicJson()).toList(),
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция reactToWish: выполняет шаг reactToWish в этой части программы. Возвращает HTTP-ответ, который backend отправит клиенту.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> reactToWish(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid wish ID format');
      }

      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final reaction = WishReaction.parse(data['reaction']);
      final previousReaction = WishReaction.parseNullable(
        data['previousReaction'],
      );
      final wishId = ObjectId.fromHexString(id);
      final rawWish = await _wishesCollection.findOne(where.eq('_id', wishId));

      if (rawWish == null) {
        return ResponseHelper.error(
          errorMessage: 'Wish not found',
          statusCode: 404,
        );
      }

      final existingWish = Wish.fromJson(rawWish);
      if (existingWish.appId != appId) {
        return ResponseHelper.error(
          errorMessage: 'Wish not found',
          statusCode: 404,
        );
      }

      final updatedWish = existingWish.applyReaction(
        reaction: reaction,
        previousReaction: previousReaction,
      );

      if (previousReaction == reaction) {
        return ResponseHelper.success(data: updatedWish.toPublicJson());
      }

      final result = await _wishesCollection.updateOne(
        where.eq('_id', wishId),
        modify
            .set('likeCount', updatedWish.likeCount)
            .set('dislikeCount', updatedWish.dislikeCount)
            .set('updatedAt', updatedWish.updatedAt.toIso8601String()),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to update wish reaction',
          statusCode: 500,
        );
      }

      return ResponseHelper.success(data: updatedWish.toPublicJson());
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Геттер _wishesCollection: читает значение _wishesCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  static DbCollection get _wishesCollection =>
      MongoService.instance.db.collection(Collections.wishes);

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
