import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/app_registry/app_registry_service.dart';
import 'package:shelf/shelf.dart';

class AppRegistryAdminController {
  static Future<Response> listApps(Request request) async {
    try {
      final apps = await AppRegistryService.instance.listApps();
      return ResponseHelper.success(data: apps);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> createApp(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final app = await AppRegistryService.instance.createApp(
        appId: data['appId']?.toString() ?? data['app_id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        platform: data['platform']?.toString(),
        apiBaseUrl: data['apiBaseUrl']?.toString(),
        settings: _settingsFrom(data),
      );
      return ResponseHelper.success(data: app, statusCode: 201);
    } on AppRegistryException catch (error) {
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

  static Future<Response> getApp(Request request, String appId) async {
    try {
      final app = await AppRegistryService.instance.getApp(appId);
      return ResponseHelper.success(data: app);
    } on AppRegistryException catch (error) {
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

  static Future<Response> updateApp(Request request, String appId) async {
    try {
      final data = await parseRequestDataHelper(request);
      final app = await AppRegistryService.instance.updateApp(
        appId: appId,
        name: data.containsKey('name') ? data['name']?.toString() : null,
        platform: data.containsKey('platform')
            ? data['platform']?.toString()
            : null,
        apiBaseUrl: data.containsKey('apiBaseUrl')
            ? data['apiBaseUrl']?.toString()
            : null,
        isActive: data.containsKey('isActive')
            ? data['isActive'] == true || data['isActive']?.toString() == 'true'
            : null,
        settings: data.containsKey('settings') ? _settingsFrom(data) : null,
      );
      return ResponseHelper.success(data: app);
    } on AppRegistryException catch (error) {
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

  static Map<String, dynamic>? _settingsFrom(Map<String, dynamic> data) {
    final settings = data['settings'];
    if (settings == null) {
      return null;
    }
    if (settings is Map) {
      return Map<String, dynamic>.from(settings);
    }
    return <String, dynamic>{};
  }
}
