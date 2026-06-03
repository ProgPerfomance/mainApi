import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/security/encryption_service.dart';
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
    String? displayName,
    String? imageUrl,
    String? shortDescription,
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
      'displayName': _stringOrNull(displayName) ?? normalizedName,
      'imageUrl': _stringOrNull(imageUrl),
      'shortDescription': _stringOrNull(shortDescription),
      'platform': _normalizePlatform(platform),
      'apiBaseUrl': _stringOrNull(apiBaseUrl),
      'settings': settings ?? <String, dynamic>{},
      'isActive': true,
      'createdAt': now,
      'updatedAt': now,
    };

    final result = await _apps.insertOne(document);
    if (!result.isSuccess) {
      throw const AppRegistryException('Failed to create app', statusCode: 500);
    }

    final created = await _apps.findOne(where.eq('_id', result.id));
    return _toPublicJson(created ?? document);
  }

  Future<Map<String, dynamic>> updateApp({
    required String appId,
    String? name,
    String? displayName,
    String? imageUrl,
    String? shortDescription,
    String? platform,
    String? apiBaseUrl,
    bool? isActive,
    Map<String, dynamic>? settings,
  }) async {
    final normalizedAppId = _normalizeAppId(appId);
    final modifier = modify.set(
      'updatedAt',
      DateTime.now().toUtc().toIso8601String(),
    );

    if (name != null) {
      final normalizedName = name.trim();
      if (normalizedName.isEmpty) {
        throw const AppRegistryException('App name is required');
      }
      modifier.set('name', normalizedName);
      if (displayName == null) {
        modifier.set('displayName', normalizedName);
      }
    }
    if (displayName != null) {
      modifier.set('displayName', _stringOrNull(displayName) ?? name);
    }
    if (imageUrl != null) {
      modifier.set('imageUrl', _stringOrNull(imageUrl));
    }
    if (shortDescription != null) {
      modifier.set('shortDescription', _stringOrNull(shortDescription));
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

  Future<Map<String, dynamic>> updateTBankSettings({
    required String appId,
    String? terminalKey,
    String? password,
    bool? enabled,
    bool clearTerminalKey = false,
    bool clearPassword = false,
  }) async {
    final normalizedAppId = _normalizeAppId(appId);
    final existing = await _apps.findOne(where.eq('appId', normalizedAppId));
    if (existing == null) {
      throw const AppRegistryException('App not found', statusCode: 404);
    }

    final current = existing['tBankSettings'] is Map
        ? Map<String, dynamic>.from(existing['tBankSettings'] as Map)
        : <String, dynamic>{};
    final next = <String, dynamic>{...current};
    final normalizedTerminalKey = _stringOrNull(terminalKey);
    final normalizedPassword = _stringOrNull(password);

    if (enabled != null) {
      next['enabled'] = enabled;
    } else {
      next['enabled'] = current['enabled'] != false;
    }
    if (clearTerminalKey) {
      next.remove('terminalKeyEncrypted');
    } else if (normalizedTerminalKey != null) {
      next['terminalKeyEncrypted'] = await EncryptionService.instance
          .encryptString(normalizedTerminalKey);
    }
    if (clearPassword) {
      next.remove('passwordEncrypted');
    } else if (normalizedPassword != null) {
      next['passwordEncrypted'] = await EncryptionService.instance
          .encryptString(normalizedPassword);
    }
    next['updatedAt'] = DateTime.now().toUtc().toIso8601String();

    final result = await _apps.updateOne(
      where.eq('appId', normalizedAppId),
      modify
          .set('tBankSettings', next)
          .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
    );
    if (!result.isSuccess || result.nMatched == 0) {
      throw const AppRegistryException('App not found', statusCode: 404);
    }
    final updated = await _apps.findOne(where.eq('appId', normalizedAppId));
    return _toPublicJson(updated!);
  }

  Future<Map<String, dynamic>> revealTBankSettings(String appId) async {
    final normalizedAppId = _normalizeAppId(appId);
    final app = await _apps.findOne(where.eq('appId', normalizedAppId));
    if (app == null) {
      throw const AppRegistryException('App not found', statusCode: 404);
    }
    final settings = app['tBankSettings'] is Map
        ? Map<String, dynamic>.from(app['tBankSettings'] as Map)
        : <String, dynamic>{};
    final terminalKey = await EncryptionService.instance.decryptString(
      settings['terminalKeyEncrypted'],
    );
    final password = await EncryptionService.instance.decryptString(
      settings['passwordEncrypted'],
    );
    return {
      ..._publicTBankSettings(settings),
      'terminalKey': terminalKey,
      'password': password,
    };
  }

  Future<Map<String, String>> resolveTBankCredentials(String? appId) async {
    final normalizedAppId = appId == null || appId.trim().isEmpty
        ? null
        : _normalizeAppId(appId);
    if (normalizedAppId != null) {
      final app = await _apps.findOne(where.eq('appId', normalizedAppId));
      final settings = app?['tBankSettings'] is Map
          ? Map<String, dynamic>.from(app?['tBankSettings'] as Map)
          : null;
      if (settings != null && settings['enabled'] != false) {
        final terminalKey = await EncryptionService.instance.decryptString(
          settings['terminalKeyEncrypted'],
        );
        final password = await EncryptionService.instance.decryptString(
          settings['passwordEncrypted'],
        );
        if (_stringOrNull(terminalKey) != null &&
            _stringOrNull(password) != null) {
          return {'terminalKey': terminalKey!, 'password': password!};
        }
      }
    }
    return {
      'terminalKey': _tBankTerminalKeyFromEnv(normalizedAppId),
      'password': _tBankPasswordFromEnv(normalizedAppId),
    };
  }

  Future<Map<String, dynamic>> getApp(String appId) async {
    final normalizedAppId = _normalizeAppId(appId);
    final app = await _apps.findOne(where.eq('appId', normalizedAppId));
    if (app == null) {
      throw const AppRegistryException('App not found', statusCode: 404);
    }
    return _toPublicJson(app);
  }

  Future<Map<String, dynamic>> listOtherAppBlocks({String? appId}) async {
    final normalizedAppId = appId == null || appId.trim().isEmpty
        ? null
        : _normalizeAppId(appId);
    final rows = await _apps
        .find(where.eq('isActive', true).sortBy('createdAt'))
        .toList();
    final apps = rows
        .map(_toPublicJson)
        .where((app) => app['appId'] != normalizedAppId)
        .map(_toRelatedAppJson)
        .toList();

    final blocks = <Map<String, dynamic>>[];
    if (apps.isNotEmpty) {
      blocks.add({
        'type': 'banner',
        'title': 'Попробуйте другое приложение',
        'apps': [apps.first],
      });
    }
    if (apps.length > 1) {
      blocks.add({
        'type': 'grid',
        'title': 'Другие приложения',
        'columns': 3,
        'apps': apps.skip(1).toList(),
      });
    }

    return {'appId': normalizedAppId, 'blocks': blocks};
  }

  Map<String, dynamic> _toPublicJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    final displayName = json['displayName']?.toString();
    return {
      if (json['_id'] != null) '_id': json['_id'].toString(),
      'appId': json['appId']?.toString() ?? json['app_id']?.toString() ?? '',
      'app_id': json['appId']?.toString() ?? json['app_id']?.toString() ?? '',
      'name': name,
      'displayName': displayName == null || displayName.trim().isEmpty
          ? name
          : displayName,
      'imageUrl': json['imageUrl']?.toString(),
      'shortDescription': json['shortDescription']?.toString(),
      'platform': json['platform']?.toString() ?? 'mobile',
      'apiBaseUrl': json['apiBaseUrl']?.toString(),
      'settings': json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'] as Map)
          : <String, dynamic>{},
      'tBankSettings': _publicTBankSettings(
        json['tBankSettings'] is Map
            ? Map<String, dynamic>.from(json['tBankSettings'] as Map)
            : <String, dynamic>{},
      ),
      'isActive': json['isActive'] != false,
      'createdAt': json['createdAt']?.toString(),
      'updatedAt': json['updatedAt']?.toString(),
    };
  }

  Map<String, dynamic> _toRelatedAppJson(Map<String, dynamic> app) {
    final title = app['displayName']?.toString().trim().isNotEmpty == true
        ? app['displayName'].toString()
        : app['name']?.toString() ?? app['appId']?.toString() ?? '';
    return {
      'appId': app['appId'],
      'name': app['name'],
      'title': title,
      'displayName': title,
      'shortDescription': app['shortDescription'],
      'imageUrl': app['imageUrl'],
      'platform': app['platform'],
      'apiBaseUrl': app['apiBaseUrl'],
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

  Map<String, dynamic> _publicTBankSettings(Map<String, dynamic> settings) {
    final terminalKeyConfigured = settings['terminalKeyEncrypted'] is Map;
    final passwordConfigured = settings['passwordEncrypted'] is Map;
    return {
      'enabled': settings['enabled'] != false,
      'terminalKeyConfigured': terminalKeyConfigured,
      'passwordConfigured': passwordConfigured,
      'configured': terminalKeyConfigured && passwordConfigured,
      'updatedAt': settings['updatedAt']?.toString(),
    };
  }

  String _tBankTerminalKeyFromEnv(String? appId) {
    final appKey = _appScopedEnvKey(
      prefix: 'TBANK',
      appId: appId,
      suffix: 'TERMINAL_KEY',
    );
    final value =
        (appKey == null ? null : _envNonEmpty(appKey)) ??
        _envNonEmpty('TBANK_TERMINAL_KEY');
    if (value == null) {
      throw const AppRegistryException(
        'T-Bank terminal key is not configured',
        statusCode: 500,
      );
    }
    return value;
  }

  String _tBankPasswordFromEnv(String? appId) {
    final appKey = _appScopedEnvKey(
      prefix: 'TBANK',
      appId: appId,
      suffix: 'PASSWORD',
    );
    final value =
        (appKey == null ? null : _envNonEmpty(appKey)) ??
        _envNonEmpty('TBANK_PASSWORD');
    if (value == null) {
      throw const AppRegistryException(
        'T-Bank password is not configured',
        statusCode: 500,
      );
    }
    return value;
  }

  String? _envNonEmpty(String key) {
    final value = AppConfig.get(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _appScopedEnvKey({
    required String prefix,
    required String? appId,
    required String suffix,
  }) {
    final normalizedAppId = appId?.trim();
    if (normalizedAppId == null || normalizedAppId.isEmpty) {
      return null;
    }
    final envAppId = normalizedAppId
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (envAppId.isEmpty) {
      return null;
    }
    return '${prefix}_${envAppId}_$suffix';
  }
}
