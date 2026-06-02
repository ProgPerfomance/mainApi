// Этот файл: lib/src/controller/admin/user_admin_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';

import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/referral/referral_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// Класс UserAdminController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class UserAdminController {
  static const String adminBalanceAdjustmentDescription =
      'Admin balance adjustment';
  static const String adminSubscriptionGrantDescription =
      'Admin subscription grant';
  static const String adminSubscriptionClearDescription =
      'Admin subscription removal';

  /// Функция listUsers: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listUsers(Request request) async {
    try {
      final searchQuery = _normalizeUserSearchQuery(
        request.url.queryParameters['q'],
      );
      final rawUsers = await _usersCollection
          .find(_userSearchSelector(searchQuery))
          .toList();
      final users = <User>[];

      for (final rawUser in rawUsers) {
        final ensuredUser = await ReferralService.instance
            .ensureUserReferralCode(User.fromJson(rawUser));
        users.add(ensuredUser);
      }

      users.sort((left, right) => right.createdAt.compareTo(left.createdAt));

      final usersByReferrerId = <String, List<User>>{};
      for (final user in users) {
        final referrerId = user.referredByUserId?.oid;
        if (referrerId == null) {
          continue;
        }

        usersByReferrerId.putIfAbsent(referrerId, () => []).add(user);
      }

      final response = users.map((user) {
        final referrals =
            [...(usersByReferrerId[user.id?.oid] ?? const <User>[])]
              ..sort((left, right) {
                final leftDate = left.referralAppliedAt ?? left.createdAt;
                final rightDate = right.referralAppliedAt ?? right.createdAt;
                return rightDate.compareTo(leftDate);
              });

        return {
          ...user.toPublicJson(),
          'referralsCount': referrals.length,
          'referrals': referrals.map(_toReferralJson).toList(),
        };
      }).toList();

      return ResponseHelper.success(data: response);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция getUserProfile: получает нужное значение и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> getUserProfile(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid user ID format');
      }

      final userId = ObjectId.fromHexString(id);
      final user = await _loadEnsuredUser(userId);
      final referrals = await _loadReferrals(userId);
      final transactions = await _loadUserTransactions(userId);

      return ResponseHelper.success(
        data: {
          ...user.toPublicJson(),
          'referralsCount': referrals.length,
          'referrals': referrals.map(_toReferralJson).toList(),
          'transactions': transactions
              .map((transaction) => transaction.toPublicJson())
              .toList(),
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> updateUser(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid user ID format');
      }

      final payload = await request.readAsString();
      final data = payload.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final name = data['name']?.toString().trim() ?? '';
      final email = data['email']?.toString().trim().toLowerCase() ?? '';
      final phoneNumber = data['phoneNumber']?.toString().trim();
      final avatarUrl = data['avatarUrl']?.toString().trim();

      if (name.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Name is required');
      }
      if (email.isEmpty || !email.contains('@')) {
        return ResponseHelper.error(errorMessage: 'Valid email is required');
      }

      final userId = ObjectId.fromHexString(id);
      final existingEmailUser = await _usersCollection.findOne(
        where.eq('email', email).ne('_id', userId),
      );
      if (existingEmailUser != null) {
        return ResponseHelper.error(
          errorMessage: 'Email is already used',
          statusCode: 409,
        );
      }

      final now = DateTime.now().toUtc();
      final result = await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set('name', name)
            .set('email', email)
            .set(
              'phoneNumber',
              phoneNumber?.isEmpty == true ? null : phoneNumber,
            )
            .set('avatarUrl', avatarUrl?.isEmpty == true ? null : avatarUrl)
            .set('updatedAt', now.toIso8601String()),
      );

      if (!result.isSuccess || result.nMatched == 0) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final updatedUser = await _loadEnsuredUser(userId);
      final referrals = await _loadReferrals(userId);
      final transactions = await _loadUserTransactions(userId);

      return ResponseHelper.success(
        data: {
          ...updatedUser.toPublicJson(),
          'referralsCount': referrals.length,
          'referrals': referrals.map(_toReferralJson).toList(),
          'transactions': transactions
              .map((transaction) => transaction.toPublicJson())
              .toList(),
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> deleteUser(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid user ID format');
      }

      final userId = ObjectId.fromHexString(id);
      final deleteUserResult = await _usersCollection.deleteOne(
        where.eq('_id', userId),
      );

      if (!deleteUserResult.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to delete user',
          statusCode: 500,
        );
      }
      if (deleteUserResult.nRemoved == 0) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final transactionsResult = await _transactionsCollection.deleteMany(
        where.eq('userId', userId),
      );
      await _usersCollection.updateMany(
        where.eq('referredByUserId', userId),
        modify
            .set('referredByUserId', null)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );

      return ResponseHelper.success(
        data: {
          'deleted': true,
          '_id': id,
          'transactionsDeleted': transactionsResult.nRemoved,
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция updateUserBalance: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> updateUserBalance(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid user ID format');
      }

      final payload = await request.readAsString();
      final data = payload.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(payload) as Map);

      final adminName = data['adminName']?.toString().trim() ?? '';
      if (adminName.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Admin name is required');
      }

      final targetBalance = double.tryParse(data['targetBalance'].toString());
      if (targetBalance == null || targetBalance < 0) {
        return ResponseHelper.error(
          errorMessage: 'Target balance must be a non-negative number',
        );
      }

      final userId = ObjectId.fromHexString(id);
      final user = await _loadEnsuredUser(userId);
      final normalizedTargetBalance = _normalizeMoneyAmount(targetBalance);
      final delta = _normalizeMoneyAmount(
        normalizedTargetBalance - user.balance,
      );
      final reason = data['reason']?.toString().trim();
      final now = DateTime.now().toUtc();

      final updateResult = await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set('balance', normalizedTargetBalance)
            .set('updatedAt', now.toIso8601String()),
      );

      if (!updateResult.isSuccess || updateResult.nMatched == 0) {
        return ResponseHelper.error(
          errorMessage: 'Failed to update balance',
          statusCode: 500,
        );
      }

      Transaction? transaction;
      if (delta != 0) {
        final transactionType = delta > 0
            ? TransactionType.deposit
            : TransactionType.withdrawal;
        final transactionToCreate = Transaction(
          userId: userId,
          userName: user.name,
          amount: delta.abs(),
          type: transactionType,
          description: adminBalanceAdjustmentDescription,
          metadata: {
            'provider': 'admin_adjustment',
            'adminName': adminName,
            'previousBalance': user.balance,
            'targetBalance': normalizedTargetBalance,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          },
          createdAt: now,
        );

        final transactionResult = await _transactionsCollection.insertOne(
          transactionToCreate.toJson(),
        );

        if (!transactionResult.isSuccess) {
          await _usersCollection.updateOne(
            where.eq('_id', userId),
            modify
                .set('balance', user.balance)
                .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
          );

          return ResponseHelper.error(
            errorMessage: 'Failed to create balance adjustment transaction',
            statusCode: 500,
          );
        }

        final createdTransaction = await _transactionsCollection.findOne(
          where.eq('_id', transactionResult.id),
        );
        transaction = createdTransaction != null
            ? Transaction.fromJson(createdTransaction)
            : transactionToCreate;
      }

      final updatedUser = await _loadEnsuredUser(userId);
      final referrals = await _loadReferrals(userId);
      final transactions = await _loadUserTransactions(userId);

      return ResponseHelper.success(
        data: {
          'user': {
            ...updatedUser.toPublicJson(),
            'referralsCount': referrals.length,
            'referrals': referrals.map(_toReferralJson).toList(),
            'transactions': transactions
                .map((item) => item.toPublicJson())
                .toList(),
          },
          if (transaction != null) 'transaction': transaction.toPublicJson(),
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> updateUserSubscription(
    Request request,
    String id,
  ) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid user ID format');
      }

      final payload = await request.readAsString();
      final data = payload.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(payload) as Map);

      final adminName = data['adminName']?.toString().trim() ?? '';
      if (adminName.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Admin name is required');
      }

      final days = int.tryParse(data['days'].toString());
      if (days == null || days <= 0) {
        return ResponseHelper.error(
          errorMessage: 'Subscription days must be a positive number',
        );
      }

      final userId = ObjectId.fromHexString(id);
      final user = await _loadEnsuredUser(userId);
      final reason = data['reason']?.toString().trim();
      final appId = _resolveAppId(data);
      final scope = _resolveScope(data);
      final subscriptionAppId = scope == BillingService.subscriptionScopeGlobal
          ? BillingService.globalAppId
          : appId;
      final now = DateTime.now().toUtc();
      final currentSubscription = user.subscriptionFor(
        scope: scope,
        appId: subscriptionAppId,
      );
      final currentExpiresAt = currentSubscription?.expiresAt?.toUtc();
      final startsAt = currentExpiresAt != null && currentExpiresAt.isAfter(now)
          ? currentExpiresAt
          : now;
      final expiresAt = startsAt.add(Duration(days: days));
      final nextSubscriptions = User.upsertSubscription(
        user.subscriptions,
        UserSubscription(
          scope: scope,
          appId: subscriptionAppId,
          expiresAt: expiresAt,
          autoRenewEnabled: currentSubscription?.autoRenewEnabled ?? false,
          nextChargeAt: currentSubscription?.nextChargeAt,
          rebillId: currentSubscription?.rebillId,
          recurringPaymentId: currentSubscription?.recurringPaymentId,
          recurringOrderId: currentSubscription?.recurringOrderId,
          updatedAt: now,
        ),
      );
      final legacySubscription = User.effectiveSubscriptionForAppFrom(
        nextSubscriptions,
        appId,
      );

      final updateResult = await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set(
              'subscriptions',
              nextSubscriptions.map((item) => item.toJson()).toList(),
            )
            .set(
              'subscriptionExpiresAt',
              legacySubscription?.expiresAt?.toIso8601String(),
            )
            .set(
              'subscriptionAutoRenewEnabled',
              legacySubscription?.autoRenewEnabled ?? false,
            )
            .set(
              'subscriptionNextChargeAt',
              legacySubscription?.nextChargeAt?.toIso8601String(),
            )
            .set('updatedAt', now.toIso8601String()),
      );

      if (!updateResult.isSuccess || updateResult.nMatched == 0) {
        return ResponseHelper.error(
          errorMessage: 'Failed to update subscription',
          statusCode: 500,
        );
      }

      final transactionToCreate = Transaction(
        userId: userId,
        userName: user.name,
        amount: 0,
        type: TransactionType.deposit,
        description: adminSubscriptionGrantDescription,
        metadata: {
          'provider': 'admin_subscription_grant',
          'adminName': adminName,
          'days': days,
          'appId': subscriptionAppId,
          'app_id': subscriptionAppId,
          'subscriptionScope': scope,
          'previousSubscriptionExpiresAt': currentSubscription?.expiresAt
              ?.toIso8601String(),
          'subscriptionExpiresAt': expiresAt.toIso8601String(),
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        createdAt: now,
      );

      final transactionResult = await _transactionsCollection.insertOne(
        transactionToCreate.toJson(),
      );
      if (!transactionResult.isSuccess) {
        await _usersCollection.updateOne(
          where.eq('_id', userId),
          modify
              .set(
                'subscriptions',
                user.subscriptions.map((item) => item.toJson()).toList(),
              )
              .set(
                'subscriptionExpiresAt',
                user.subscriptionExpiresAt?.toIso8601String(),
              )
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );

        return ResponseHelper.error(
          errorMessage: 'Failed to create subscription grant transaction',
          statusCode: 500,
        );
      }

      final updatedUser = await _loadEnsuredUser(userId);
      final referrals = await _loadReferrals(userId);
      final transactions = await _loadUserTransactions(userId);
      final createdTransaction = await _transactionsCollection.findOne(
        where.eq('_id', transactionResult.id),
      );

      return ResponseHelper.success(
        data: {
          'user': {
            ...updatedUser.toPublicJson(),
            'referralsCount': referrals.length,
            'referrals': referrals.map(_toReferralJson).toList(),
            'transactions': transactions
                .map((item) => item.toPublicJson())
                .toList(),
          },
          'transaction':
              (createdTransaction != null
                      ? Transaction.fromJson(createdTransaction)
                      : transactionToCreate)
                  .toPublicJson(),
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> clearUserSubscription(
    Request request,
    String id,
  ) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid user ID format');
      }

      final payload = await request.readAsString();
      final data = payload.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(payload) as Map);

      final adminName = data['adminName']?.toString().trim() ?? '';
      if (adminName.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Admin name is required');
      }

      final userId = ObjectId.fromHexString(id);
      final user = await _loadEnsuredUser(userId);
      final reason = data['reason']?.toString().trim();
      final appId = _resolveAppId(data);
      final scope = _resolveScope(data);
      final subscriptionAppId = scope == BillingService.subscriptionScopeGlobal
          ? BillingService.globalAppId
          : appId;
      final now = DateTime.now().toUtc();
      final currentSubscription = user.subscriptionFor(
        scope: scope,
        appId: subscriptionAppId,
      );
      final nextSubscriptions = User.removeSubscription(
        user.subscriptions,
        scope: scope,
        appId: subscriptionAppId,
      );
      final legacySubscription = User.effectiveSubscriptionForAppFrom(
        nextSubscriptions,
        appId,
      );

      final updateResult = await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set(
              'subscriptions',
              nextSubscriptions.map((item) => item.toJson()).toList(),
            )
            .set(
              'subscriptionExpiresAt',
              legacySubscription?.expiresAt?.toIso8601String(),
            )
            .set(
              'subscriptionAutoRenewEnabled',
              legacySubscription?.autoRenewEnabled ?? false,
            )
            .set(
              'subscriptionNextChargeAt',
              legacySubscription?.nextChargeAt?.toIso8601String(),
            )
            .set('subscriptionAutoRenewCancelledAt', now.toIso8601String())
            .set('updatedAt', now.toIso8601String()),
      );

      if (!updateResult.isSuccess || updateResult.nMatched == 0) {
        return ResponseHelper.error(
          errorMessage: 'Failed to clear subscription',
          statusCode: 500,
        );
      }

      final transactionToCreate = Transaction(
        userId: userId,
        userName: user.name,
        amount: 0,
        type: TransactionType.withdrawal,
        description: adminSubscriptionClearDescription,
        metadata: {
          'provider': 'admin_subscription_clear',
          'adminName': adminName,
          'appId': subscriptionAppId,
          'app_id': subscriptionAppId,
          'subscriptionScope': scope,
          'previousSubscriptionExpiresAt': currentSubscription?.expiresAt
              ?.toIso8601String(),
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        createdAt: now,
      );

      final transactionResult = await _transactionsCollection.insertOne(
        transactionToCreate.toJson(),
      );
      if (!transactionResult.isSuccess) {
        await _usersCollection.updateOne(
          where.eq('_id', userId),
          modify
              .set(
                'subscriptions',
                user.subscriptions.map((item) => item.toJson()).toList(),
              )
              .set(
                'subscriptionExpiresAt',
                user.subscriptionExpiresAt?.toIso8601String(),
              )
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );

        return ResponseHelper.error(
          errorMessage: 'Failed to create subscription removal transaction',
          statusCode: 500,
        );
      }

      final updatedUser = await _loadEnsuredUser(userId);
      final referrals = await _loadReferrals(userId);
      final transactions = await _loadUserTransactions(userId);
      final createdTransaction = await _transactionsCollection.findOne(
        where.eq('_id', transactionResult.id),
      );

      return ResponseHelper.success(
        data: {
          'user': {
            ...updatedUser.toPublicJson(),
            'referralsCount': referrals.length,
            'referrals': referrals.map(_toReferralJson).toList(),
            'transactions': transactions
                .map((item) => item.toPublicJson())
                .toList(),
          },
          'transaction':
              (createdTransaction != null
                      ? Transaction.fromJson(createdTransaction)
                      : transactionToCreate)
                  .toPublicJson(),
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Геттер _usersCollection: читает значение _usersCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  static DbCollection get _usersCollection =>
      MongoService.instance.db.collection(Collections.users);

  /// Геттер _transactionsCollection: читает значение _transactionsCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  static DbCollection get _transactionsCollection =>
      MongoService.instance.db.collection(Collections.transactions);

  static SelectorBuilder _userSearchSelector(String searchQuery) {
    if (searchQuery.isEmpty) {
      return where;
    }

    final pattern = RegExp.escape(searchQuery);
    return where
        .match('name', pattern, caseInsensitive: true)
        .or(where.match('email', pattern, caseInsensitive: true));
  }

  static String _normalizeUserSearchQuery(String? query) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.length <= 100) {
      return trimmed;
    }
    return trimmed.substring(0, 100);
  }

  /// Функция _loadEnsuredUser: загружает данные и возвращает результат загрузки.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  static Future<User> _loadEnsuredUser(ObjectId userId) async {
    final rawUser = await _usersCollection.findOne(where.eq('_id', userId));
    if (rawUser == null) {
      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError('User not found');
    }

    return ReferralService.instance.ensureUserReferralCode(
      /// Конструктор User.fromJson: создаёт новый объект этого класса.
      /// Возвращает готовый объект, с которым дальше работает приложение.
      User.fromJson(rawUser),
    );
  }

  /// Функция _loadReferrals: загружает данные и возвращает результат загрузки.
  /// Возвращает список значений.
  static Future<List<User>> _loadReferrals(ObjectId userId) async {
    final rawReferrals = await _usersCollection
        .find(where.eq('referredByUserId', userId))
        .toList();

    final referrals = <User>[];
    for (final rawReferral in rawReferrals) {
      referrals.add(
        await ReferralService.instance.ensureUserReferralCode(
          /// Конструктор User.fromJson: создаёт новый объект этого класса.
          /// Возвращает готовый объект, с которым дальше работает приложение.
          User.fromJson(rawReferral),
        ),
      );
    }

    referrals.sort((left, right) {
      final leftDate = left.referralAppliedAt ?? left.createdAt;
      final rightDate = right.referralAppliedAt ?? right.createdAt;
      return rightDate.compareTo(leftDate);
    });

    return referrals;
  }

  /// Функция _loadUserTransactions: загружает данные и возвращает результат загрузки.
  /// Возвращает список значений.
  static Future<List<Transaction>> _loadUserTransactions(
    ObjectId userId,
  ) async {
    final rawTransactions = await _transactionsCollection
        .find(where.eq('userId', userId))
        .toList();

    final transactions = rawTransactions.map(Transaction.fromJson).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return transactions;
  }

  /// Функция _toReferralJson: выполняет шаг _toReferralJson в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static Map<String, dynamic> _toReferralJson(User user) {
    return {
      '_id': user.id?.oid,
      'name': user.name,
      'email': user.email,
      'balance': user.balance,
      'referralCode': user.referralCode,
      'appliedReferralCode': user.appliedReferralCode,
      'createdAt': user.createdAt.toIso8601String(),
      if (user.referralAppliedAt != null)
        'referralAppliedAt': user.referralAppliedAt!.toIso8601String(),
    };
  }

  /// Функция _normalizeMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает число с копейками или дробной частью.
  static double _normalizeMoneyAmount(double amount) {
    return double.parse(amount.toStringAsFixed(2));
  }

  static String _resolveAppId(Map<String, dynamic> data) {
    return BillingService.normalizeAppId(
      data['appId']?.toString() ?? data['app_id']?.toString(),
    );
  }

  static String _resolveScope(Map<String, dynamic> data) {
    return BillingService.normalizeSubscriptionScope(
      data['scope']?.toString() ?? data['subscriptionScope']?.toString(),
    );
  }
}
