import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

class AppRegistryException implements Exception {
  const AppRegistryException(this.message, {this.statusCode = 400});

  final String message;
  final int statusCode;
}

class AppRegistryService {
  AppRegistryService._();

  static final AppRegistryService instance = AppRegistryService._();

  DbCollection get _apps =>
      MongoService.instance.db.collection(Collections.apps);

  Future<List<Map<String, dynamic>>> listApps() async {
    final rows = await _apps.find(where.sortBy('createdAt')).toList();
    return rows.map(_toPublicJson).toList();
  }

  Future<Map<String, dynamic>> createApp({
    required String appId,
    required String name,
    String? platform,
    String? apiBaseUrl,
    Map<String, dynamic>? settings,
  }) async {
    final normalizedAppId = _normalizeAppId(appId);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const AppRegistryException('App name is required');
    }

    final existing = await _apps.findOne(where.eq('appId', normalizedAppId));
    if (existing != null) {
      throw const AppRegistryException(
        'App with this appId already exists',
        statusCode: 409,
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final document = {
      'appId': normalizedAppId,
      'app_id': normalizedAppId,
      'name': normalizedName,
      'platform': _normalizePlatform(platform),
      'apiBaseUrl': _stringOrNull(apiBaseUrl),
      'settings': settings ?? <String, dynamic>{},
      'isActive': true,
      'createdAt': now,
      'updatedAt': now,
    };

    final result = await _apps.insertOne(document);
    if (!result.isSuccess) {
      throw const AppRegistryException(
        'Failed to create app',
        statusCode: 500,
      );
    }

    final created = await _apps.findOne(where.eq('_id', result.id));
    return _toPublicJson(created ?? document);
  }

  Future<Map<String, dynamic>> updateApp({
    required String appId,
    String? name,
    String? platform,
    String? apiBaseUrl,
    bool? isActive,
    Map<String, dynamic>? settings,
  }) async {
    final normalizedAppId = _normalizeAppId(appId);
    final modifier = modify.set('updatedAt', DateTime.now().toUtc().toIso8601String());

    if (name != null) {
      final normalizedName = name.trim();
      if (normalizedName.isEmpty) {
        throw const AppRegistryException('App name is required');
      }
      modifier.set('name', normalizedName);
    }
    if (platform != null) {
      modifier.set('platform', _normalizePlatform(platform));
    }
    if (apiBaseUrl != null) {
      modifier.set('apiBaseUrl', _stringOrNull(apiBaseUrl));
    }
    if (isActive != null) {
      modifier.set('isActive', isActive);
    }
    if (settings != null) {
      modifier.set('settings', settings);
    }

    final result = await _apps.updateOne(
      where.eq('appId', normalizedAppId),
      modifier,
    );
    if (!result.isSuccess || result.nMatched == 0) {
      throw const AppRegistryException('App not found', statusCode: 404);
    }

    final updated = await _apps.findOne(where.eq('appId', normalizedAppId));
    return _toPublicJson(updated!);
  }

  Future<Map<String, dynamic>> getApp(String appId) async {
    final normalizedAppId = _normalizeAppId(appId);
    final app = await _apps.findOne(where.eq('appId', normalizedAppId));
    if (app == null) {
      throw const AppRegistryException('App not found', statusCode: 404);
    }
    return _toPublicJson(app);
  }

  Map<String, dynamic> _toPublicJson(Map<String, dynamic> json) {
    return {
      if (json['_id'] != null) '_id': json['_id'].toString(),
      'appId': json['appId']?.toString() ?? json['app_id']?.toString() ?? '',
      'app_id': json['appId']?.toString() ?? json['app_id']?.toString() ?? '',
      'name': json['name']?.toString() ?? '',
      'platform': json['platform']?.toString() ?? 'mobile',
      'apiBaseUrl': json['apiBaseUrl']?.toString(),
      'settings': json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'] as Map)
          : <String, dynamic>{},
      'isActive': json['isActive'] != false,
      'createdAt': json['createdAt']?.toString(),
      'updatedAt': json['updatedAt']?.toString(),
    };
  }

  String _normalizeAppId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$').hasMatch(normalized)) {
      throw const AppRegistryException('App ID is invalid');
    }
    return normalized;
  }

  String _normalizePlatform(String? value) {
    final normalized = (value ?? 'mobile').trim().toLowerCase();
    return normalized.isEmpty ? 'mobile' : normalized;
  }

  String? _stringOrNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
