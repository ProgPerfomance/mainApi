import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/app_registry/app_registry_service.dart';
import 'package:main_api/src/services/app_version/app_version_service.dart';
import 'package:shelf/shelf.dart';

class AppController {
  static Future<Response> getVersionSettings(Request request) async {
    try {
      final settings = await AppVersionService.instance.getSettings(
        appId:
            request.url.queryParameters['appId'] ??
            request.url.queryParameters['app_id'] ??
            request.headers['x-app-id'],
      );
      return ResponseHelper.success(data: settings.toPublicJson());
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> listOtherApps(Request request) async {
    try {
      final feed = await AppRegistryService.instance.listOtherAppBlocks(
        appId:
            request.url.queryParameters['appId'] ??
            request.url.queryParameters['app_id'] ??
            request.headers['x-app-id'],
      );
      return ResponseHelper.success(data: feed);
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
}
