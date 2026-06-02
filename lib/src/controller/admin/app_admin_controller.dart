import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/app_version/app_version_service.dart';
import 'package:shelf/shelf.dart';

class AppAdminController {
  static Future<Response> getVersionSettings(Request request) async {
    try {
      final settings = await AppVersionService.instance.getSettings(
        appId: _resolveAppId(request),
      );
      return ResponseHelper.success(data: settings.toPublicJson());
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> updateVersionSettings(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final requiredVersion = data['requiredVersion']?.toString() ?? '';
      final settings = await AppVersionService.instance.setRequiredVersion(
        requiredVersion,
        appId:
            data['appId']?.toString() ??
            data['app_id']?.toString() ??
            _resolveAppId(request),
      );
      return ResponseHelper.success(data: settings.toPublicJson());
    } on AppVersionServiceException catch (error) {
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

  static String? _resolveAppId(Request request) {
    return request.url.queryParameters['appId'] ??
        request.url.queryParameters['app_id'] ??
        request.headers['x-app-id'];
  }
}
