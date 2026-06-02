// Этот файл: lib/src/services/billing/recurring_subscription_service.dart.
// Простыми словами: это фоновая проверка автопродления подписок.

import 'dart:async';
import 'dart:developer' as developer;

import 'package:main_api/src/controller/user/user_billing_controller.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/tbank/tbank_payment_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

class RecurringSubscriptionService {
  RecurringSubscriptionService._();

  static final RecurringSubscriptionService instance =
      RecurringSubscriptionService._();

  Timer? _timer;
  bool _isProcessing = false;

  void start() {
    if (!AppConfig.recurringSubscriptionJobEnabled || _timer != null) {
      return;
    }

    _timer = Timer.periodic(
      const Duration(hours: 1),
      (_) => processDueSubscriptions(),
    );
    unawaited(processDueSubscriptions());
  }

  Future<void> processDueSubscriptions() async {
    if (_isProcessing) {
      return;
    }

    _isProcessing = true;
    try {
      final now = DateTime.now().toUtc();
      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final rawUsers = await usersCollection.find().toList();

      for (final rawUser in rawUsers) {
        final user = User.fromJson(rawUser);
        final userId = rawUser['_id'];
        if (userId is! ObjectId) {
          continue;
        }

        for (final subscription in user.subscriptions) {
          final nextChargeAt = subscription.nextChargeAt;
          final rebillId = subscription.rebillId;
          if (!subscription.autoRenewEnabled ||
              rebillId == null ||
              rebillId.isEmpty ||
              nextChargeAt == null ||
              nextChargeAt.toUtc().isAfter(now)) {
            continue;
          }

          await _processUser(
            userId: userId,
            rawUser: rawUser,
            subscription: subscription,
            rebillId: rebillId,
          );
        }
      }
    } catch (error, stackTrace) {
      developer.log(
        'processDueSubscriptions:error $error',
        name: 'RecurringSubscriptionService',
        stackTrace: stackTrace,
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processUser({
    required ObjectId userId,
    required Map<String, dynamic> rawUser,
    required UserSubscription subscription,
    required String rebillId,
  }) async {
    final now = DateTime.now().toUtc();
    final paymentsCollection = MongoService.instance.db.collection(
      Collections.tbankPayments,
    );
    final user = User.fromJson(rawUser);
    final settings = await BillingService.instance.getSubscriptionSettings(
      appId: subscription.appId,
      scope: subscription.scope,
    );
    final amountKopecks = (settings.price * 100).round();
    final orderId =
        'subscription_recurring_${settings.scope}_${settings.appId}_${now.millisecondsSinceEpoch}_${userId.oid}';

    try {
      final charge = await TBankPaymentService.forApp(settings.appId)
          .chargeRecurringPayment(
            orderId: orderId,
            amountKopecks: amountKopecks,
            description: 'Subscription ${settings.name}',
            userId: userId.oid,
            rebillId: rebillId,
            userEmail: user.email,
            userPhone: user.phoneNumber,
          );
      final savedPayment = {
        'userId': userId,
        'userName': user.name,
        'orderId': charge.orderId,
        'paymentId': charge.paymentId,
        'amount': settings.price,
        'amountKopecks': charge.amountKopecks,
        'status': charge.chargeStatus ?? charge.initStatus,
        'applied': false,
        'purpose': 'subscription_recurring',
        'appId': settings.appId,
        'app_id': settings.appId,
        'scope': settings.scope,
        'autoRenewRequested': true,
        'subscriptionAutoRenewEnabled': true,
        'rebillId': rebillId,
        'subscription': settings.toPublicJson(),
        'rawInit': charge.initRaw,
        'rawCharge': charge.chargeRaw,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      await paymentsCollection.insertOne(savedPayment);

      if (!charge.isConfirmed) {
        await _postponeSubscription(
          userId: userId,
          user: user,
          subscription: subscription,
          nextChargeAt: now.add(const Duration(days: 1)),
          metadata: {'subscriptionRecurringLastStatus': charge.chargeStatus},
        );
        return;
      }

      final result = await UserBillingController.applySavedSubscriptionPayment(
        userId: userId,
        payment: savedPayment,
      );
      await paymentsCollection.updateOne(
        where.eq('paymentId', charge.paymentId),
        modify
            .set('applied', true)
            .set('appliedAt', now.toIso8601String())
            .set(
              'subscriptionExpiresAt',
              result.subscriptionExpiresAt.toIso8601String(),
            )
            .set('updatedAt', now.toIso8601String()),
      );
      await UserBillingController.enableUserSubscriptionAutoRenew(
        userId: userId,
        appId: settings.appId,
        scope: settings.scope,
        rebillId: rebillId,
        nextChargeAt: result.subscriptionExpiresAt,
        paymentId: charge.paymentId,
        orderId: charge.orderId,
      );
    } catch (error, stackTrace) {
      developer.log(
        'user=${userId.oid} error=$error',
        name: 'RecurringSubscriptionService',
        stackTrace: stackTrace,
      );
      await _postponeSubscription(
        userId: userId,
        user: user,
        subscription: subscription,
        nextChargeAt: now.add(const Duration(days: 1)),
        metadata: {'subscriptionRecurringLastError': error.toString()},
      );
    }
  }

  Future<void> _postponeSubscription({
    required ObjectId userId,
    required User user,
    required UserSubscription subscription,
    required DateTime nextChargeAt,
    required Map<String, dynamic> metadata,
  }) async {
    final now = DateTime.now().toUtc();
    final nextSubscriptions = User.upsertSubscription(
      user.subscriptions,
      subscription.copyWith(nextChargeAt: nextChargeAt, updatedAt: now),
    );
    final legacySubscription = User.effectiveSubscriptionForAppFrom(
      nextSubscriptions,
      subscription.scope == BillingService.subscriptionScopeGlobal
          ? BillingService.globalAppId
          : subscription.appId,
    );
    final modifier = modify
        .set(
          'subscriptions',
          nextSubscriptions.map((item) => item.toJson()).toList(),
        )
        .set(
          'subscriptionNextChargeAt',
          legacySubscription?.nextChargeAt?.toIso8601String(),
        )
        .set('updatedAt', now.toIso8601String());
    for (final entry in metadata.entries) {
      modifier.set(entry.key, entry.value);
    }
    await MongoService.instance.db
        .collection(Collections.users)
        .updateOne(where.eq('_id', userId), modifier);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
