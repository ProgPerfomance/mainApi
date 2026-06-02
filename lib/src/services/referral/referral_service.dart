// Этот файл: lib/src/services/referral/referral_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:math';

import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Класс ReferralServiceException: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ReferralServiceException implements Exception {
  final String message;
  final int statusCode;
  final String? errorCode;

  const ReferralServiceException(
    this.message, {
    this.statusCode = 400,
    this.errorCode,
  });

  /// Функция toString: выполняет шаг toString в этой части программы. Возвращает текст.
  /// Возвращает текст.
  @override
  String toString() => message;
}

/// Класс ReferralService: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class ReferralService {
  /// Конструктор ReferralService._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  ReferralService._();

  static final ReferralService instance = ReferralService._();

  static const String referralBonusDescription = 'Referral bonus';
  static const String referralCodeAlreadyAppliedErrorCode =
      'REFERRAL_CODE_ALREADY_APPLIED';
  static const String referralCodeInvalidErrorCode = 'REFERRAL_CODE_INVALID';
  static const String referralCodeSelfErrorCode = 'REFERRAL_CODE_SELF';
  static const String referralCodeReciprocalErrorCode =
      'REFERRAL_CODE_RECIPROCAL';
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int _codeLength = 6;
  static const int _maxGenerateAttempts = 20;

  /// Геттер _db: читает значение _db и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа Db; это готовый результат для следующего шага программы.
  Db get _db => MongoService.instance.db;

  /// Геттер _usersCollection: читает значение _usersCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  DbCollection get _usersCollection => _db.collection(Collections.users);

  /// Геттер _transactionsCollection: читает значение _transactionsCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  DbCollection get _transactionsCollection =>
      _db.collection(Collections.transactions);

  /// Функция ensureUserReferralCode: проверяет, что нужное значение есть, и возвращает готовый вариант.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<User> ensureUserReferralCode(User user) async {
    final existingCode = _normalizeReferralCode(user.referralCode);
    if (existingCode != null) {
      return existingCode == user.referralCode
          ? user
          : _updateUserReferralCode(user, existingCode);
    }

    final generatedCode = await generateUniqueReferralCode();

    /// Функция _updateUserReferralCode: обновляет существующие данные и возвращает обновлённый результат.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return _updateUserReferralCode(user, generatedCode);
  }

  /// Функция applyReferralCode: применяет действие к данным и возвращает обновлённый результат.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<User> applyReferralCode({
    required ObjectId userId,
    required String rawReferralCode,
  }) async {
    final normalizedCode = _normalizeReferralCode(rawReferralCode);
    if (normalizedCode == null) {
      throw const ReferralServiceException(
        'Referral code is required',
        errorCode: referralCodeInvalidErrorCode,
      );
    }

    final currentUser = await _findUser(userId);
    final ensuredCurrentUser = await ensureUserReferralCode(currentUser);

    if (_normalizeReferralCode(ensuredCurrentUser.appliedReferralCode) !=
            null ||
        ensuredCurrentUser.referredByUserId != null) {
      throw const ReferralServiceException(
        'Referral code has already been applied',
        statusCode: 409,
        errorCode: referralCodeAlreadyAppliedErrorCode,
      );
    }

    if (normalizedCode == ensuredCurrentUser.referralCode) {
      throw const ReferralServiceException(
        'You cannot apply your own referral code',
        errorCode: referralCodeSelfErrorCode,
      );
    }

    final referrerRaw = await _usersCollection.findOne(
      where.eq('referralCode', normalizedCode),
    );

    if (referrerRaw == null) {
      throw const ReferralServiceException(
        'Referral code not found',
        statusCode: 404,
        errorCode: referralCodeInvalidErrorCode,
      );
    }

    final referrer = await ensureUserReferralCode(User.fromJson(referrerRaw));
    if (referrer.id == null || referrer.id == ensuredCurrentUser.id) {
      throw const ReferralServiceException(
        'You cannot apply your own referral code',
        errorCode: referralCodeSelfErrorCode,
      );
    }

    final currentUserCode = _normalizeReferralCode(
      ensuredCurrentUser.referralCode,
    );
    final referrerAlreadyUsedCurrentUser =
        referrer.referredByUserId?.oid == ensuredCurrentUser.id?.oid ||
        _normalizeReferralCode(referrer.appliedReferralCode) == currentUserCode;
    if (referrerAlreadyUsedCurrentUser) {
      throw const ReferralServiceException(
        'Referral code exchange between the same users is not allowed',
        statusCode: 409,
        errorCode: referralCodeReciprocalErrorCode,
      );
    }

    final now = DateTime.now().toUtc();
    final userUpdateResult = await _usersCollection.updateOne(
      where.eq('_id', ensuredCurrentUser.id),
      modify
          .set('appliedReferralCode', normalizedCode)
          .set('referredByUserId', referrer.id)
          .set('referralAppliedAt', now.toIso8601String())
          .set('updatedAt', now.toIso8601String()),
    );

    if (!userUpdateResult.isSuccess || userUpdateResult.nMatched == 0) {
      throw const ReferralServiceException(
        'Failed to apply referral code',
        statusCode: 500,
      );
    }

    final bonusAmount = await BillingService.instance.getReferralBonusAmount();
    if (bonusAmount > 0) {
      ObjectId? referrerTransactionId;
      ObjectId? invitedTransactionId;

      try {
        referrerTransactionId = await _creditReferralBonus(
          user: referrer,
          amount: bonusAmount,
          now: now,
          metadata: {
            'provider': 'referral',
            'role': 'inviter',
            'referredUserId': ensuredCurrentUser.id!.oid,
            'referredUserName': ensuredCurrentUser.name,
            'referredUserEmail': ensuredCurrentUser.email,
            'appliedReferralCode': normalizedCode,
          },
        );

        invitedTransactionId = await _creditReferralBonus(
          user: ensuredCurrentUser,
          amount: bonusAmount,
          now: now,
          metadata: {
            'provider': 'referral',
            'role': 'invited',
            'referrerUserId': referrer.id!.oid,
            'referrerUserName': referrer.name,
            'appliedReferralCode': normalizedCode,
          },
        );
      } catch (_) {
        // Если хотя бы одно начисление не получилось, откатываем всё:
        // и связь по реферальному коду, и уже начисленные бонусы.
        await _usersCollection.updateOne(
          where.eq('_id', referrer.id),
          modify
              .set('balance', referrer.balance)
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );
        await _usersCollection.updateOne(
          where.eq('_id', ensuredCurrentUser.id),
          modify
              .set('balance', ensuredCurrentUser.balance)
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );
        if (referrerTransactionId != null) {
          await _transactionsCollection.deleteOne(
            where.eq('_id', referrerTransactionId),
          );
        }
        if (invitedTransactionId != null) {
          await _transactionsCollection.deleteOne(
            where.eq('_id', invitedTransactionId),
          );
        }

        /// Функция _rollbackAppliedReferralCode: выполняет шаг _rollbackAppliedReferralCode в этой части программы. Возвращает значение типа await; это готовый результат для следующего шага программы.
        /// Возвращает значение типа await; это готовый результат для следующего шага программы.
        await _rollbackAppliedReferralCode(ensuredCurrentUser.id!);
        throw const ReferralServiceException(
          'Failed to apply referral bonus',
          statusCode: 500,
        );
      }
    }

    final updatedUser = await _findUser(ensuredCurrentUser.id!);

    /// Функция ensureUserReferralCode: проверяет, что нужное значение есть, и возвращает готовый вариант.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return ensureUserReferralCode(updatedUser);
  }

  /// Функция generateUniqueReferralCode: создаёт новое значение и возвращает его.
  /// Возвращает текст.
  Future<String> generateUniqueReferralCode() async {
    for (var attempt = 0; attempt < _maxGenerateAttempts; attempt++) {
      final code = _generateReferralCode();
      final existingUser = await _usersCollection.findOne(
        where.eq('referralCode', code),
      );

      if (existingUser == null) {
        return code;
      }
    }

    throw const ReferralServiceException(
      'Failed to generate a unique referral code',
      statusCode: 500,
    );
  }

  /// Функция normalizeReferralCode: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает текст или пустое значение, если текста нет.
  String? normalizeReferralCode(String? value) => _normalizeReferralCode(value);

  /// Функция _findUser: выполняет шаг _findUser в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<User> _findUser(ObjectId userId) async {
    final rawUser = await _usersCollection.findOne(where.eq('_id', userId));
    if (rawUser == null) {
      throw const ReferralServiceException('User not found', statusCode: 404);
    }

    return User.fromJson(rawUser);
  }

  /// Функция _updateUserReferralCode: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<User> _updateUserReferralCode(User user, String code) async {
    if (user.id == null) {
      return user.copyWith(referralCode: code);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final result = await _usersCollection.updateOne(
      where.eq('_id', user.id),
      modify.set('referralCode', code).set('updatedAt', now),
    );

    if (!result.isSuccess || result.nMatched == 0) {
      throw const ReferralServiceException(
        'Failed to assign referral code',
        statusCode: 500,
      );
    }

    return user.copyWith(referralCode: code, updatedAt: DateTime.parse(now));
  }

  /// Функция _creditReferralBonus: выполняет шаг _creditReferralBonus в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<ObjectId> _creditReferralBonus({
    required User user,
    required double amount,
    required DateTime now,
    required Map<String, dynamic> metadata,
  }) async {
    if (user.id == null) {
      throw const ReferralServiceException(
        'Failed to apply referral bonus',
        statusCode: 500,
      );
    }

    final updatedBalance = _normalizeMoneyAmount(user.balance + amount);
    final updateResult = await _usersCollection.updateOne(
      where.eq('_id', user.id),
      modify
          .set('balance', updatedBalance)
          .set('updatedAt', now.toIso8601String()),
    );

    if (!updateResult.isSuccess || updateResult.nMatched == 0) {
      throw const ReferralServiceException(
        'Failed to apply referral bonus',
        statusCode: 500,
      );
    }

    final transaction = Transaction(
      userId: user.id!,
      userName: user.name,
      amount: amount,
      type: TransactionType.deposit,
      description: referralBonusDescription,
      metadata: metadata,
      createdAt: now,
    );

    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );

    if (!transactionResult.isSuccess || transactionResult.id is! ObjectId) {
      await _usersCollection.updateOne(
        where.eq('_id', user.id),
        modify
            .set('balance', user.balance)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const ReferralServiceException(
        'Failed to save referral bonus transaction',
        statusCode: 500,
      );
    }

    return transactionResult.id as ObjectId;
  }

  /// Функция _rollbackAppliedReferralCode: выполняет шаг _rollbackAppliedReferralCode в этой части программы. Возвращает ожидание завершения работы, но не возвращает отдельное значение.
  /// Возвращает ожидание завершения работы, но не возвращает отдельное значение.
  Future<void> _rollbackAppliedReferralCode(ObjectId userId) async {
    await _usersCollection.updateOne(
      where.eq('_id', userId),
      modify
          .set('appliedReferralCode', null)
          .set('referredByUserId', null)
          .set('referralAppliedAt', null)
          .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
    );
  }

  /// Функция _generateReferralCode: создаёт новое значение и возвращает его.
  /// Возвращает текст.
  String _generateReferralCode() {
    final random = Random.secure();
    final buffer = StringBuffer();

    for (var index = 0; index < _codeLength; index++) {
      final charIndex = random.nextInt(_alphabet.length);
      buffer.write(_alphabet[charIndex]);
    }

    return buffer.toString();
  }

  /// Функция _normalizeReferralCode: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает текст или пустое значение, если текста нет.
  String? _normalizeReferralCode(String? value) {
    final normalizedValue = value?.trim().toUpperCase();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return null;
    }

    final pattern = RegExp(r'^[A-Z0-9]{4,12}$');
    if (!pattern.hasMatch(normalizedValue)) {
      throw const ReferralServiceException(
        'Referral code must contain only letters and digits',
        errorCode: referralCodeInvalidErrorCode,
      );
    }

    return normalizedValue;
  }

  /// Функция _normalizeMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает число с копейками или дробной частью.
  double _normalizeMoneyAmount(double amount) {
    return double.parse(amount.toStringAsFixed(2));
  }
}
