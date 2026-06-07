import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/app_config.dart';
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
        displayName: data['displayName']?.toString(),
        imageUrl: data['imageUrl']?.toString(),
        shortDescription: data['shortDescription']?.toString(),
        ruStoreUrl: data['ruStoreUrl']?.toString(),
        platform: data['platform']?.toString(),
        apiBaseUrl: data['apiBaseUrl']?.toString(),
        relatedBlockIds: _stringList(data['relatedBlockIds']),
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
        displayName: data.containsKey('displayName')
            ? data['displayName']?.toString()
            : null,
        imageUrl: data.containsKey('imageUrl')
            ? data['imageUrl']?.toString()
            : null,
        shortDescription: data.containsKey('shortDescription')
            ? data['shortDescription']?.toString()
            : null,
        ruStoreUrl: data.containsKey('ruStoreUrl')
            ? data['ruStoreUrl']?.toString()
            : null,
        platform: data.containsKey('platform')
            ? data['platform']?.toString()
            : null,
        apiBaseUrl: data.containsKey('apiBaseUrl')
            ? data['apiBaseUrl']?.toString()
            : null,
        relatedBlockIds: data.containsKey('relatedBlockIds')
            ? _stringList(data['relatedBlockIds'])
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

  static Future<Response> updateTBankSettings(
    Request request,
    String appId,
  ) async {
    try {
      final data = await parseRequestDataHelper(request);
      final app = await AppRegistryService.instance.updateTBankSettings(
        appId: appId,
        terminalKey: data.containsKey('terminalKey')
            ? data['terminalKey']?.toString()
            : null,
        password: data.containsKey('password')
            ? data['password']?.toString()
            : null,
        enabled: data.containsKey('enabled')
            ? data['enabled'] == true || data['enabled']?.toString() == 'true'
            : null,
        clearTerminalKey: data['clearTerminalKey'] == true,
        clearPassword: data['clearPassword'] == true,
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

  static Future<Response> revealTBankSettings(
    Request request,
    String appId,
  ) async {
    try {
      final data = await parseRequestDataHelper(request);
      final password = data['password']?.toString() ?? '';
      final expectedPassword = AppConfig.adminPassword;
      if (expectedPassword == null || password != expectedPassword) {
        return ResponseHelper.error(
          errorMessage: 'Invalid admin password',
          statusCode: 403,
        );
      }
      final settings = await AppRegistryService.instance.revealTBankSettings(
        appId,
      );
      return ResponseHelper.success(data: settings);
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

  static Future<Response> listRelatedAppBlocks(Request request) async {
    try {
      final blocks = await AppRegistryService.instance.listRelatedAppBlocks();
      return ResponseHelper.success(data: blocks);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> createRelatedAppBlock(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final block = await AppRegistryService.instance.createRelatedAppBlock(
        blockId: data['blockId']?.toString() ?? data['id']?.toString() ?? '',
        type: data['type']?.toString() ?? 'grid',
        title: data['title']?.toString(),
        columns: (data['columns'] as num?)?.toInt(),
        appIds: _stringList(data['appIds']),
        isActive:
            data['isActive'] == null ||
            data['isActive'] == true ||
            data['isActive']?.toString() == 'true',
      );
      return ResponseHelper.success(data: block, statusCode: 201);
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

  static Future<Response> updateRelatedAppBlock(
    Request request,
    String blockId,
  ) async {
    try {
      final data = await parseRequestDataHelper(request);
      final block = await AppRegistryService.instance.updateRelatedAppBlock(
        blockId: blockId,
        type: data.containsKey('type') ? data['type']?.toString() : null,
        title: data.containsKey('title') ? data['title']?.toString() : null,
        columns: data.containsKey('columns')
            ? (data['columns'] as num?)?.toInt()
            : null,
        appIds: data.containsKey('appIds') ? _stringList(data['appIds']) : null,
        isActive: data.containsKey('isActive')
            ? data['isActive'] == true || data['isActive']?.toString() == 'true'
            : null,
      );
      return ResponseHelper.success(data: block);
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

  static Future<Response> deleteRelatedAppBlock(
    Request request,
    String blockId,
  ) async {
    try {
      final result = await AppRegistryService.instance.deleteRelatedAppBlock(
        blockId,
      );
      return ResponseHelper.success(data: result);
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

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item?.toString().trim())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
