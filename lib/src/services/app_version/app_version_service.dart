import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

class AppVersionServiceException implements Exception {
  const AppVersionServiceException(this.message, {this.statusCode = 400});

  final String message;
  final int statusCode;
}

class AppVersionSettings {
  const AppVersionSettings({
    required this.appId,
    required this.requiredVersion,
    required this.updatedAt,
  });

  final String appId;
  final String requiredVersion;
  final DateTime updatedAt;

  Map<String, dynamic> toPublicJson() {
    return {
      'appId': appId,
      'app_id': appId,
      'requiredVersion': requiredVersion,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class AppVersionService {
  AppVersionService._();

  static final AppVersionService instance = AppVersionService._();
  static const String _legacyPsychologySettingsKey = 'mobile_app_version';
  static const String _settingsKeyPrefix = 'mobile_app_version';
  static const String defaultPsychologyRequiredVersion = 'v1.0.2+6';
  static const String defaultMedRequiredVersion = 'v1.0.0+1';
  static const String defaultCalloriesRequiredVersion = 'v1.0.0+1';
  static const String defaultGdzRequiredVersion = 'v1.0.0+1';
  static const String defaultRequiredVersion = 'v1.0.0+1';

  DbCollection get _settingsCollection =>
      MongoService.instance.db.collection(Collections.appSettings);

  Future<AppVersionSettings> getSettings({String? appId}) async {
    final normalizedAppId = _normalizeAppId(appId);
    final settingsKey = _settingsKey(normalizedAppId);
    var rawSettings = await _settingsCollection.findOne(
      where.eq('key', settingsKey),
    );

    if (rawSettings == null && normalizedAppId == 'psychology') {
      rawSettings = await _settingsCollection.findOne(
        where.eq('key', _legacyPsychologySettingsKey),
      );
    }

    if (rawSettings == null) {
      return setRequiredVersion(
        _defaultRequiredVersion(normalizedAppId),
        appId: normalizedAppId,
      );
    }

    final requiredVersion =
        rawSettings['requiredVersion']?.toString().trim() ?? '';
    final updatedAt = _parseDateTime(rawSettings['updatedAt']);
    return AppVersionSettings(
      appId: normalizedAppId,
      requiredVersion: requiredVersion.isEmpty
          ? _defaultRequiredVersion(normalizedAppId)
          : requiredVersion,
      updatedAt: updatedAt,
    );
  }

  Future<AppVersionSettings> setRequiredVersion(
    String rawVersion, {
    String? appId,
  }) async {
    final normalizedAppId = _normalizeAppId(appId);
    final settingsKey = _settingsKey(normalizedAppId);
    final requiredVersion = _normalizeVersion(rawVersion);
    final now = DateTime.now().toUtc();

    final result = await _settingsCollection.updateOne(
      where.eq('key', settingsKey),
      modify
          .set('key', settingsKey)
          .set('appId', normalizedAppId)
          .set('app_id', normalizedAppId)
          .set('requiredVersion', requiredVersion)
          .set('updatedAt', now.toIso8601String()),
      upsert: true,
    );

    if (!result.isSuccess) {
      throw const AppVersionServiceException(
        'Failed to save app version',
        statusCode: 500,
      );
    }

    return AppVersionSettings(
      appId: normalizedAppId,
      requiredVersion: requiredVersion,
      updatedAt: now,
    );
  }

  String _settingsKey(String appId) => '$_settingsKeyPrefix:$appId';

  String _defaultRequiredVersion(String appId) {
    return switch (appId) {
      'psychology' => defaultPsychologyRequiredVersion,
      'med_app' => defaultMedRequiredVersion,
      'callories' => defaultCalloriesRequiredVersion,
      'gdz' => defaultGdzRequiredVersion,
      _ => defaultRequiredVersion,
    };
  }

  String _normalizeAppId(String? value) {
    final normalized = (value ?? 'psychology').trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'psychology';
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$').hasMatch(normalized)) {
      throw const AppVersionServiceException('App ID is invalid');
    }
    return normalized;
  }

  String _normalizeVersion(String rawVersion) {
    final version = rawVersion.trim();
    if (version.isEmpty || version.length > 40) {
      throw const AppVersionServiceException('App version is invalid');
    }

    final isValid = RegExp(r'^[a-zA-Z0-9._+\-]+$').hasMatch(version);
    if (!isValid) {
      throw const AppVersionServiceException(
        'App version may contain only letters, digits, ".", "_", "+", "-"',
      );
    }

    return version;
  }

  DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value.toUtc();
    }

    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value).toUtc();
    }

    return DateTime.now().toUtc();
  }
}
