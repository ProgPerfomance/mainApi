import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/custom_content/custom_content_service.dart';
import 'package:shelf/shelf.dart';

class CustomContentAdminController {
  static final CustomContentService _service = CustomContentService();

  static Future<Response> listCollections(Request request) async {
    try {
      final appId = _resolveAppId(request);
      final collections = await _service.listCollections(appId: appId);
      return ResponseHelper.success(data: collections);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> createCollection(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final collection = await _service.createCollection(
        appId: _resolveAppId(request, data),
        data: data,
      );
      return ResponseHelper.success(data: collection, statusCode: 201);
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> updateCollection(
    Request request,
    String collectionKey,
  ) async {
    try {
      final data = await parseRequestDataHelper(request);
      final collection = await _service.updateCollection(
        appId: _resolveAppId(request, data),
        collectionKey: collectionKey,
        data: data,
      );
      if (collection == null) {
        return ResponseHelper.error(
          errorMessage: 'Collection not found',
          statusCode: 404,
        );
      }
      return ResponseHelper.success(data: collection);
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> deleteCollection(
    Request request,
    String collectionKey,
  ) async {
    try {
      final removed = await _service.deleteCollection(
        appId: _resolveAppId(request),
        collectionKey: collectionKey,
        deleteItems: request.url.queryParameters['deleteItems'] == 'true',
      );
      if (removed == 0) {
        return ResponseHelper.error(
          errorMessage: 'Collection not found',
          statusCode: 404,
        );
      }
      return ResponseHelper.success(
        data: {'deleted': true, 'collectionKey': collectionKey},
      );
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> listItems(
    Request request,
    String collectionKey,
  ) async {
    try {
      final query = request.url.queryParameters;
      final items = await _service.listItems(
        appId: _resolveAppId(request),
        collectionKey: collectionKey,
        includeInactive: true,
        q: query['q'],
        tags: _tags(query['tags']),
        limit: int.tryParse(query['limit'] ?? '') ?? 200,
        skip: int.tryParse(query['skip'] ?? '') ?? 0,
      );
      return ResponseHelper.success(data: items);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> createItem(
    Request request,
    String collectionKey,
  ) async {
    try {
      final data = await parseRequestDataHelper(request);
      final item = await _service.createItem(
        appId: _resolveAppId(request, data),
        collectionKey: collectionKey,
        data: data,
      );
      return ResponseHelper.success(data: item, statusCode: 201);
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> updateItem(
    Request request,
    String collectionKey,
    String itemId,
  ) async {
    try {
      final data = await parseRequestDataHelper(request);
      final item = await _service.updateItem(
        appId: _resolveAppId(request, data),
        collectionKey: collectionKey,
        itemId: itemId,
        data: data,
      );
      if (item == null) {
        return ResponseHelper.error(
          errorMessage: 'Item not found',
          statusCode: 404,
        );
      }
      return ResponseHelper.success(data: item);
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> deleteItem(
    Request request,
    String collectionKey,
    String itemId,
  ) async {
    try {
      final removed = await _service.deleteItem(
        appId: _resolveAppId(request),
        collectionKey: collectionKey,
        itemId: itemId,
      );
      if (removed == 0) {
        return ResponseHelper.error(
          errorMessage: 'Item not found',
          statusCode: 404,
        );
      }
      return ResponseHelper.success(data: {'deleted': true, 'itemId': itemId});
    } catch (error) {
      return _serverError(error);
    }
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

  static List<String> _tags(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Response _serverError(Object error) {
    return ResponseHelper.error(
      errorMessage: 'Internal server error: $error',
      statusCode: 500,
    );
  }
}
