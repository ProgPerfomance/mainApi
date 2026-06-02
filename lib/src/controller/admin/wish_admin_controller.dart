// Этот файл: lib/src/controller/admin/wish_admin_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/wish.dart';
import 'package:main_api/src/models/wish_request.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// Класс WishAdminController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class WishAdminController {
  /// Функция listWishRequests: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listWishRequests(Request request) async {
    try {
      final appId = _resolveAppId(request);
      final rawWishRequests = await _wishRequestsCollection
          .find(where.eq('appId', appId))
          .toList();
      final wishRequests = rawWishRequests.map(WishRequest.fromJson).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return ResponseHelper.success(
        data: wishRequests.map((item) => item.toPublicJson()).toList(),
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

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

  /// Функция createWish: создаёт новую запись или объект и возвращает созданный результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> createWish(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final wish = await _wishFromRequest(data, appId: appId);

      final result = await _wishesCollection.insertOne(wish.toJson());
      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to create wish',
          statusCode: 500,
        );
      }

      final rawWish = await _wishesCollection.findOne(
        where.eq('_id', result.id),
      );
      if (rawWish == null) {
        return ResponseHelper.error(
          errorMessage: 'Failed to load created wish',
          statusCode: 500,
        );
      }

      return ResponseHelper.success(
        statusCode: 201,
        data: Wish.fromJson(rawWish).toPublicJson(),
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция updateWish: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> updateWish(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid wish ID format');
      }

      final data = await parseRequestDataHelper(request);
      final wishId = ObjectId.fromHexString(id);
      final appId = _resolveAppId(request, data);
      final existingWish = await _wishesCollection.findOne(
        where.eq('_id', wishId).eq('appId', appId),
      );
      if (existingWish == null) {
        return ResponseHelper.error(
          errorMessage: 'Wish not found',
          statusCode: 404,
        );
      }

      final wish = await _wishFromRequest(
        data,
        appId: appId,
        existing: Wish.fromJson(existingWish).copyWith(id: wishId),
      );

      final result = await _wishesCollection.updateOne(
        where.eq('_id', wishId),
        modify
            .set('text', wish.text)
            .set('requestId', wish.requestId)
            .set('appId', wish.appId)
            .set('app_id', wish.appId)
            .set('updatedAt', wish.updatedAt.toIso8601String()),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to update wish',
          statusCode: 500,
        );
      }

      final rawWish = await _wishesCollection.findOne(where.eq('_id', wishId));
      if (rawWish == null) {
        return ResponseHelper.error(
          errorMessage: 'Failed to load updated wish',
          statusCode: 500,
        );
      }

      return ResponseHelper.success(
        data: Wish.fromJson(rawWish).toPublicJson(),
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция deleteWish: удаляет данные. Возвращает результат удаления или HTTP-ответ.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> deleteWish(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid wish ID format');
      }

      final appId = _resolveAppId(request);
      final result = await _wishesCollection.deleteOne(
        where.eq('_id', ObjectId.fromHexString(id)).eq('appId', appId),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to delete wish',
          statusCode: 500,
        );
      }

      if (result.nRemoved == 0) {
        return ResponseHelper.error(
          errorMessage: 'Wish not found',
          statusCode: 404,
        );
      }

      return ResponseHelper.success(data: {'deleted': true, '_id': id});
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> deleteWishRequest(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(
          errorMessage: 'Invalid wish request ID format',
        );
      }

      final requestId = ObjectId.fromHexString(id);
      final appId = _resolveAppId(request);
      final result = await _wishRequestsCollection.deleteOne(
        where.eq('_id', requestId).eq('appId', appId),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to delete wish request',
          statusCode: 500,
        );
      }

      if (result.nRemoved == 0) {
        return ResponseHelper.error(
          errorMessage: 'Wish request not found',
          statusCode: 404,
        );
      }

      await _wishesCollection.updateMany(
        where.eq('requestId', requestId).eq('appId', appId),
        modify.set('requestId', null),
      );

      return ResponseHelper.success(data: {'deleted': true, '_id': id});
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> clearWishRequests(Request request) async {
    try {
      final appId = _resolveAppId(request);
      final result = await _wishRequestsCollection.deleteMany(
        where.eq('appId', appId),
      );
      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to clear wish requests',
          statusCode: 500,
        );
      }

      await _wishesCollection.updateMany(
        where.eq('appId', appId).ne('requestId', null),
        modify.set('requestId', null),
      );

      return ResponseHelper.success(data: {'deleted': result.nRemoved});
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

  /// Геттер _wishesCollection: читает значение _wishesCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  static DbCollection get _wishesCollection =>
      MongoService.instance.db.collection(Collections.wishes);

  /// Функция _wishFromRequest: выполняет шаг _wishFromRequest в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  static Future<Wish> _wishFromRequest(
    Map<String, dynamic> data, {
    required String appId,
    Wish? existing,
  }) async {
    final text = data['text']?.toString().trim() ?? '';

    if (text.isEmpty) {
      throw const FormatException('Text is required');
    }

    final requestId = await _resolveRequestId(
      data.containsKey('requestId') ? data['requestId']?.toString() : null,
      appId: appId,
      currentWishId: existing?.id,
      existingRequestId: existing?.requestId,
      allowKeepExisting: !data.containsKey('requestId'),
    );

    final now = DateTime.now().toUtc();

    /// Функция Wish: выполняет шаг Wish в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Wish(
      id: existing?.id,
      requestId: requestId,
      appId: appId,
      text: text,
      likeCount: existing?.likeCount ?? 0,
      dislikeCount: existing?.dislikeCount ?? 0,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  /// Функция _resolveRequestId: выполняет шаг _resolveRequestId в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  static Future<ObjectId?> _resolveRequestId(
    String? rawRequestId, {
    required String appId,
    required ObjectId? currentWishId,
    required ObjectId? existingRequestId,
    required bool allowKeepExisting,
  }) async {
    if (allowKeepExisting) {
      return existingRequestId;
    }

    final normalizedRequestId = rawRequestId?.trim();
    if (normalizedRequestId == null || normalizedRequestId.isEmpty) {
      return null;
    }

    if (!ObjectId.isValidHexId(normalizedRequestId)) {
      throw const FormatException('Invalid wish request ID format');
    }

    final requestId = ObjectId.fromHexString(normalizedRequestId);
    final existingRequest = await _wishRequestsCollection.findOne(
      where.eq('_id', requestId).eq('appId', appId),
    );

    if (existingRequest == null) {
      throw const FormatException('Wish request not found');
    }

    final linkedWish = await _wishesCollection.findOne(
      where.eq('requestId', requestId).eq('appId', appId),
    );
    if (linkedWish != null && linkedWish['_id'] != currentWishId) {
      throw const FormatException(
        'Wish request is already linked to another wish',
      );
    }

    return requestId;
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
