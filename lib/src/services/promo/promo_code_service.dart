// Этот файл: lib/src/services/promo/promo_code_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/models/promo_code.dart';
import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Класс PromoCodeServiceException: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class PromoCodeServiceException implements Exception {
  final String message;
  final int statusCode;
  final String? errorCode;

  const PromoCodeServiceException(
    this.message, {
    this.statusCode = 400,
    this.errorCode,
  });

  /// Функция toString: выполняет шаг toString в этой части программы. Возвращает текст.
  /// Возвращает текст.
  @override
  String toString() => message;
}

/// Класс PromoCodeApplyResult: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class PromoCodeApplyResult {
  final Transaction transaction;
  final double newBalance;

  const PromoCodeApplyResult({
    required this.transaction,
    required this.newBalance,
  });
}

/// Класс PromoCodeService: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class PromoCodeService {
  /// Конструктор PromoCodeService._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  PromoCodeService._();

  static final PromoCodeService instance = PromoCodeService._();

  static const String promoCodeDepositDescription = 'Promo code bonus';
  static const String promoCodeNotFoundErrorCode = 'PROMO_CODE_NOT_FOUND';
  static const String promoCodeAlreadyUsedErrorCode = 'PROMO_CODE_ALREADY_USED';
  static const String promoCodeInactiveErrorCode = 'PROMO_CODE_INACTIVE';
  static const String promoCodeExpiredErrorCode = 'PROMO_CODE_EXPIRED';
  static const String promoCodeLimitReachedErrorCode =
      'PROMO_CODE_LIMIT_REACHED';

  /// Геттер _db: читает значение _db и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа Db; это готовый результат для следующего шага программы.
  Db get _db => MongoService.instance.db;

  /// Геттер _promoCodesCollection: читает значение _promoCodesCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  DbCollection get _promoCodesCollection =>
      _db.collection(Collections.promoCodes);

  /// Геттер _usersCollection: читает значение _usersCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  DbCollection get _usersCollection => _db.collection(Collections.users);

  /// Геттер _transactionsCollection: читает значение _transactionsCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  DbCollection get _transactionsCollection =>
      _db.collection(Collections.transactions);

  /// Функция listPromoCodes: получает список данных и возвращает его вызывающему коду.
  /// Возвращает текст.
  Future<List<Map<String, dynamic>>> listPromoCodes({String? appId}) async {
    final normalizedAppId = appId == null ? null : _normalizeAppId(appId);
    final rawPromoCodes = await _promoCodesCollection.find().toList();
    final promoCodes = rawPromoCodes.map(PromoCode.fromJson).toList()
      ..removeWhere(
        (promoCode) =>
            normalizedAppId != null && promoCode.appId != normalizedAppId,
      )
      ..sort((left, right) {
        final usageCompare = right.redemptions.length.compareTo(
          left.redemptions.length,
        );
        if (usageCompare != 0) {
          return usageCompare;
        }
        return right.updatedAt.compareTo(left.updatedAt);
      });

    return promoCodes.map((item) => item.toPublicJson()).toList();
  }

  /// Функция createPromoCode: создаёт новую запись или объект и возвращает созданный результат.
  /// Возвращает текст.
  Future<Map<String, dynamic>> createPromoCode({
    required String code,
    String? appId,
    String? campaign,
    required double amount,
    int? maxRedemptions,
    DateTime? expiresAt,
  }) async {
    final normalizedCode = _normalizeCode(code);
    final normalizedAppId = _normalizeAppId(appId);
    final normalizedAmount = _normalizeMoneyAmount(amount);
    final now = DateTime.now().toUtc();

    final existingPromoCode = await _promoCodesCollection.findOne(
      where.eq('code', normalizedCode),
    );
    if (existingPromoCode != null) {
      throw const PromoCodeServiceException(
        'Promo code already exists',
        statusCode: 409,
      );
    }

    final promoCode = PromoCode(
      code: normalizedCode,
      appId: normalizedAppId,
      campaign: _normalizeCampaign(campaign),
      amount: normalizedAmount,
      maxRedemptions: _normalizeMaxRedemptions(maxRedemptions),
      expiresAt: expiresAt?.toUtc(),
      createdAt: now,
      updatedAt: now,
    );

    final result = await _promoCodesCollection.insertOne(promoCode.toJson());
    if (!result.isSuccess) {
      throw const PromoCodeServiceException(
        'Failed to create promo code',
        statusCode: 500,
      );
    }

    final created = await _promoCodesCollection.findOne(
      where.eq('_id', result.id),
    );
    if (created == null) {
      throw const PromoCodeServiceException(
        'Failed to load created promo code',
        statusCode: 500,
      );
    }

    return PromoCode.fromJson(created).toPublicJson();
  }

  /// Функция updatePromoCode: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает текст.
  Future<Map<String, dynamic>> updatePromoCode({
    required ObjectId promoCodeId,
    String? appId,
    String? code,
    String? campaign,
    double? amount,
    bool? isActive,
    int? maxRedemptions,
    bool updateMaxRedemptions = false,
    DateTime? expiresAt,
    bool updateExpiresAt = false,
  }) async {
    final existingRaw = await _promoCodesCollection.findOne(
      where.eq('_id', promoCodeId),
    );
    if (existingRaw == null) {
      throw const PromoCodeServiceException(
        'Promo code not found',
        statusCode: 404,
      );
    }

    final existingPromoCode = PromoCode.fromJson(existingRaw);
    final nextAppId = appId != null
        ? _normalizeAppId(appId)
        : existingPromoCode.appId;
    final nextCode = code != null
        ? _normalizeCode(code)
        : existingPromoCode.code;
    final nextCampaign = campaign != null
        ? _normalizeCampaign(campaign)
        : existingPromoCode.campaign;
    final nextAmount = amount != null
        ? _normalizeMoneyAmount(amount)
        : existingPromoCode.amount;
    final nextIsActive = isActive ?? existingPromoCode.isActive;
    final nextMaxRedemptions = updateMaxRedemptions
        ? _normalizeMaxRedemptions(maxRedemptions)
        : existingPromoCode.maxRedemptions;
    final nextExpiresAt = updateExpiresAt
        ? expiresAt?.toUtc()
        : existingPromoCode.expiresAt;

    if (nextCode != existingPromoCode.code) {
      final duplicate = await _promoCodesCollection.findOne(
        where.eq('code', nextCode),
      );
      if (duplicate != null && duplicate['_id'] != promoCodeId) {
        throw const PromoCodeServiceException(
          'Promo code already exists',
          statusCode: 409,
        );
      }
    }

    final updateResult = await _promoCodesCollection.updateOne(
      where.eq('_id', promoCodeId),
      modify
          .set('code', nextCode)
          .set('appId', nextAppId)
          .set('app_id', nextAppId)
          .set('campaign', nextCampaign)
          .set('amount', nextAmount)
          .set('isActive', nextIsActive)
          .set('maxRedemptions', nextMaxRedemptions)
          .set('expiresAt', nextExpiresAt?.toIso8601String())
          .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
    );

    if (!updateResult.isSuccess || updateResult.nMatched == 0) {
      throw const PromoCodeServiceException(
        'Failed to update promo code',
        statusCode: 500,
      );
    }

    final updated = await _promoCodesCollection.findOne(
      where.eq('_id', promoCodeId),
    );
    if (updated == null) {
      throw const PromoCodeServiceException(
        'Failed to load updated promo code',
        statusCode: 500,
      );
    }

    return PromoCode.fromJson(updated).toPublicJson();
  }

  /// Функция deletePromoCode: удаляет данные. Возвращает результат удаления или HTTP-ответ.
  /// Возвращает ожидание завершения работы, но не возвращает отдельное значение.
  Future<void> deletePromoCode({required ObjectId promoCodeId}) async {
    final deleteResult = await _promoCodesCollection.deleteOne(
      where.eq('_id', promoCodeId),
    );

    if (!deleteResult.isSuccess) {
      throw const PromoCodeServiceException(
        'Failed to delete promo code',
        statusCode: 500,
      );
    }

    if (deleteResult.nRemoved == 0) {
      throw const PromoCodeServiceException(
        'Promo code not found',
        statusCode: 404,
        errorCode: promoCodeNotFoundErrorCode,
      );
    }
  }

  /// Функция applyPromoCode: применяет действие к данным и возвращает обновлённый результат.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<PromoCodeApplyResult> applyPromoCode({
    required ObjectId userId,
    required String code,
    String? appId,
  }) async {
    final normalizedCode = _normalizeCode(code);
    final normalizedAppId = _normalizeAppId(appId);
    final user = await _findUser(userId);
    final promoCode = await _findPromoCodeByCode(
      normalizedCode,
      appId: normalizedAppId,
    );

    if (!promoCode.isActive) {
      throw const PromoCodeServiceException(
        'Promo code is inactive',
        statusCode: 409,
        errorCode: promoCodeInactiveErrorCode,
      );
    }

    if (promoCode.isExpired) {
      throw const PromoCodeServiceException(
        'Promo code has expired',
        statusCode: 409,
        errorCode: promoCodeExpiredErrorCode,
      );
    }

    if (promoCode.maxRedemptions != null &&
        promoCode.redemptions.length >= promoCode.maxRedemptions!) {
      throw const PromoCodeServiceException(
        'Promo code usage limit has been reached',
        statusCode: 409,
        errorCode: promoCodeLimitReachedErrorCode,
      );
    }

    final alreadyUsed = promoCode.redemptions.any(
      (item) => item.userId == userId,
    );
    if (alreadyUsed) {
      throw const PromoCodeServiceException(
        'Promo code has already been used by this user',
        statusCode: 409,
        errorCode: promoCodeAlreadyUsedErrorCode,
      );
    }

    final now = DateTime.now().toUtc();
    final updatedBalance = _normalizeMoneyAmount(
      user.balance + promoCode.amount,
    );
    final redemption = PromoCodeRedemption(
      userId: userId,
      userName: user.name,
      userEmail: user.email,
      redeemedAt: now,
    );
    final updatedRedemptions = [...promoCode.redemptions, redemption];

    final userUpdateResult = await _usersCollection.updateOne(
      where.eq('_id', userId),
      modify
          .set('balance', updatedBalance)
          .set('updatedAt', now.toIso8601String()),
    );

    if (!userUpdateResult.isSuccess || userUpdateResult.nMatched == 0) {
      throw const PromoCodeServiceException(
        'Failed to update user balance',
        statusCode: 500,
      );
    }

    final promoUpdateResult = await _promoCodesCollection.updateOne(
      where.eq('_id', promoCode.id),
      modify
          .set(
            'redemptions',
            updatedRedemptions.map((item) => item.toJson()).toList(),
          )
          .set('updatedAt', now.toIso8601String()),
    );

    if (!promoUpdateResult.isSuccess || promoUpdateResult.nMatched == 0) {
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set('balance', user.balance)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const PromoCodeServiceException(
        'Failed to save promo code redemption',
        statusCode: 500,
      );
    }

    final transaction = Transaction(
      userId: userId,
      userName: user.name,
      amount: promoCode.amount,
      type: TransactionType.deposit,
      description: promoCodeDepositDescription,
      metadata: {
        'provider': 'promo_code',
        'promoCode': promoCode.code,
        'appId': normalizedAppId,
        'app_id': normalizedAppId,
        'contextAppId': normalizedAppId,
        'context_app_id': normalizedAppId,
      },
      createdAt: now,
    );

    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );

    if (!transactionResult.isSuccess) {
      await _promoCodesCollection.updateOne(
        where.eq('_id', promoCode.id),
        modify
            .set(
              'redemptions',
              promoCode.redemptions.map((item) => item.toJson()).toList(),
            )
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set('balance', user.balance)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const PromoCodeServiceException(
        'Failed to create promo transaction',
        statusCode: 500,
      );
    }

    final createdTransaction = await _transactionsCollection.findOne(
      where.eq('_id', transactionResult.id),
    );
    final transactionModel = createdTransaction != null
        ? Transaction.fromJson(createdTransaction)
        : transaction;

    /// Функция PromoCodeApplyResult: выполняет шаг PromoCodeApplyResult в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return PromoCodeApplyResult(
      transaction: transactionModel,
      newBalance: updatedBalance,
    );
  }

  /// Функция _findPromoCodeByCode: выполняет шаг _findPromoCodeByCode в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<PromoCode> _findPromoCodeByCode(
    String code, {
    required String appId,
  }) async {
    final rawPromoCodes = await _promoCodesCollection
        .find(where.eq('code', code))
        .toList();
    final matchingPromoCodes = rawPromoCodes
        .map(PromoCode.fromJson)
        .where((promoCode) => promoCode.appId == appId)
        .toList(growable: false);
    if (matchingPromoCodes.isEmpty) {
      throw const PromoCodeServiceException(
        'Promo code not found',
        statusCode: 404,
        errorCode: promoCodeNotFoundErrorCode,
      );
    }

    return matchingPromoCodes.first;
  }

  /// Функция _findUser: выполняет шаг _findUser в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<User> _findUser(ObjectId userId) async {
    final rawUser = await _usersCollection.findOne(where.eq('_id', userId));
    if (rawUser == null) {
      throw const PromoCodeServiceException('User not found', statusCode: 404);
    }

    return User.fromJson(rawUser);
  }

  /// Функция _normalizeCode: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает текст.
  String _normalizeCode(String value) {
    final normalizedValue = value.trim().toUpperCase();
    if (normalizedValue.isEmpty) {
      throw const PromoCodeServiceException('Promo code is required');
    }

    if (!RegExp(r'^[A-Z0-9_-]{4,24}$').hasMatch(normalizedValue)) {
      throw const PromoCodeServiceException(
        'Promo code must contain 4-24 letters, digits, "_" or "-"',
      );
    }

    return normalizedValue;
  }

  String _normalizeAppId(String? value) {
    final normalizedValue = (value ?? AppConfig.appId).trim().toLowerCase();
    if (normalizedValue.isEmpty) {
      return 'psychology';
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$').hasMatch(normalizedValue)) {
      throw const PromoCodeServiceException('App ID is invalid');
    }
    return normalizedValue;
  }

  /// Функция _normalizeCampaign: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает текст или пустое значение, если текста нет.
  String? _normalizeCampaign(String? value) {
    final normalizedValue = value?.trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  /// Функция _normalizeMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает число с копейками или дробной частью.
  double _normalizeMoneyAmount(double amount) {
    return double.parse(amount.toStringAsFixed(2));
  }

  /// Функция _normalizeMaxRedemptions: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает целое число.
  int? _normalizeMaxRedemptions(int? value) {
    if (value == null) {
      return null;
    }

    if (value <= 0) {
      throw const PromoCodeServiceException(
        'Promo code activation limit must be a positive integer',
      );
    }

    return value;
  }
}
