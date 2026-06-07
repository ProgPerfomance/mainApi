import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/custom_content/custom_content_service.dart';
import 'package:shelf/shelf.dart';

class CustomContentController {
  static final CustomContentService _service = CustomContentService();

  static Future<Response> listCollections(Request request) async {
    try {
      final collections = await _service.listCollections(
        appId: _resolveAppId(request),
        includeInactive: false,
      );
      return ResponseHelper.success(data: collections);
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
        q: query['q'],
        tags: _tags(query['tags']),
        limit: int.tryParse(query['limit'] ?? '') ?? 100,
        skip: int.tryParse(query['skip'] ?? '') ?? 0,
      );
      return ResponseHelper.success(data: items);
    } catch (error) {
      return _serverError(error);
    }
  }

  static Future<Response> getItem(
    Request request,
    String collectionKey,
    String itemId,
  ) async {
    try {
      final item = await _service.getItem(
        appId: _resolveAppId(request),
        collectionKey: collectionKey,
        itemId: itemId,
      );
      if (item == null) {
        return ResponseHelper.error(
          errorMessage: 'Item not found',
          statusCode: 404,
        );
      }
      return ResponseHelper.success(data: item);
    } catch (error) {
      return _serverError(error);
    }
  }

  static String _resolveAppId(Request request) {
    return BillingService.normalizeAppId(
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
