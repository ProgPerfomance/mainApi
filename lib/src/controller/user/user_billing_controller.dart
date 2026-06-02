// Этот файл: lib/src/controller/user/user_billing_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/auth/jwt_service.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/promo/promo_code_service.dart';
import 'package:main_api/src/services/tbank/tbank_payment_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

// Controller - это слой, который принимает HTTP-запрос,
// проверяет входные данные и возвращает HTTP-ответ.
// В этом файле все пользовательские запросы, связанные с балансом.
class UserBillingController {
  static const double _minimumTopUpAmount = 99.0;

  // Код ошибки, по которому клиент может понять:
  // такой внешний платёж уже был начислен раньше.
  static const String purchaseAlreadyAppliedErrorCode =
      'PURCHASE_ALREADY_APPLIED';
  static const String _tBankProvider = 'tbank';

  static Future<Response> getSubscriptionSettings(Request request) async {
    try {
      final settings = await BillingService.instance.getSubscriptionSettings(
        appId: _resolveAppId(request),
        scope: _resolveScope(request: request),
      );
      return ResponseHelper.success(data: settings.toPublicJson());
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> prepareAiRequest(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final preparation = await BillingService.instance.prepareAiRequestCharge(
        userObjectId,
        appId: appId,
      );
      final paymentSource = preparation.hasActiveSubscription
          ? 'subscription'
          : preparation.willUseRequestBalance
          ? 'request_balance'
          : 'balance';

      return ResponseHelper.success(
        data: {
          'userId': userObjectId.oid,
          'userName': preparation.user.name,
          'requestPrice': preparation.requestPrice,
          'willUseRequestBalance': preparation.willUseRequestBalance,
          'hasActiveSubscription': preparation.hasActiveSubscription,
          'sessionStartedAt': preparation.sessionStartedAt.toIso8601String(),
          'sessionRequestIndex': preparation.sessionRequestIndex,
          'paymentSource': paymentSource,
          'appId': appId,
          'app_id': appId,
        },
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> chargeAiRequest(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final requestPrice = double.tryParse(
        data['requestPrice']?.toString() ?? '',
      );
      final sessionStartedAt = DateTime.tryParse(
        data['sessionStartedAt']?.toString() ?? '',
      );
      final sessionRequestIndex = int.tryParse(
        data['sessionRequestIndex']?.toString() ?? '',
      );
      if (requestPrice == null ||
          sessionStartedAt == null ||
          sessionRequestIndex == null ||
          sessionRequestIndex <= 0) {
        return ResponseHelper.error(
          errorMessage:
              'Request price, session start and session index are required',
        );
      }

      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }
      final user = User.fromJson(userData);
      final result = await BillingService.instance.chargeSuccessfulAiRequest(
        userId: userObjectId,
        userName: user.name,
        requestPrice: requestPrice,
        sessionStartedAt: sessionStartedAt.toUtc(),
        sessionRequestIndex: sessionRequestIndex,
        appId: appId,
      );

      return ResponseHelper.success(
        data: {...result.toJson(), 'appId': appId, 'app_id': appId},
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> initTBankSubscription(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final scope = _resolveScope(request: request, data: data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final settings = await BillingService.instance.getSubscriptionSettings(
        appId: appId,
        scope: scope,
      );
      final amountKopecks = (settings.price * 100).round();
      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final user = User.fromJson(userData);
      final autoRenew = _parseBool(data['autoRenew']);
      final orderId = _buildTBankOrderId(prefix: 'subscription');
      final payment = await TBankPaymentService.forApp(appId).initPayment(
        orderId: orderId,
        amountKopecks: amountKopecks,
        description:
            data['description']?.toString() ?? 'Subscription ${settings.name}',
        userId: userObjectId.oid,
        userEmail: user.email,
        userPhone: user.phoneNumber,
        language: data['language']?.toString() ?? 'ru',
        deviceOs: data['deviceOs']?.toString(),
        deviceBrowser: data['deviceBrowser']?.toString(),
        recurrent: autoRenew,
        customerKey: autoRenew ? userObjectId.oid : null,
        operationInitiatorType: autoRenew ? '1' : '0',
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await MongoService.instance.db
          .collection(Collections.tbankPayments)
          .insertOne({
            'userId': userObjectId,
            'userName': user.name,
            'orderId': payment.orderId,
            'paymentId': payment.paymentId,
            'paymentUrl': payment.paymentUrl,
            'amount': settings.price,
            'amountKopecks': payment.amountKopecks,
            'status': payment.status,
            'applied': false,
            'purpose': 'subscription',
            'appId': settings.appId,
            'app_id': settings.appId,
            'contextAppId': appId,
            'context_app_id': appId,
            'scope': settings.scope,
            'autoRenewRequested': autoRenew,
            'subscriptionAutoRenewEnabled': false,
            'subscription': settings.toPublicJson(),
            'createdAt': now,
            'updatedAt': now,
          });

      return ResponseHelper.success(
        data: {
          'provider': _tBankProvider,
          'paymentId': payment.paymentId,
          'orderId': payment.orderId,
          'paymentUrl': payment.paymentUrl,
          'amount': settings.price,
          'amountKopecks': payment.amountKopecks,
          'status': payment.status,
          'subscription': settings.toPublicJson(),
          'autoRenew': autoRenew,
          'appId': settings.appId,
          'app_id': settings.appId,
          'contextAppId': appId,
          'context_app_id': appId,
          'scope': settings.scope,
        },
      );
    } on TBankPaymentException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> confirmTBankSubscription(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final paymentId = data['paymentId']?.toString();
      final orderId = data['orderId']?.toString();
      if ((paymentId == null || paymentId.isEmpty) &&
          (orderId == null || orderId.isEmpty)) {
        return ResponseHelper.error(
          errorMessage: 'Payment ID or Order ID is required',
        );
      }

      final paymentsCollection = MongoService.instance.db.collection(
        Collections.tbankPayments,
      );
      final paymentData = await paymentsCollection.findOne(
        paymentId != null && paymentId.isNotEmpty
            ? where.eq('paymentId', paymentId)
            : where.eq('orderId', orderId),
      );
      if (paymentData == null) {
        return ResponseHelper.error(
          errorMessage: 'Payment not found',
          statusCode: 404,
        );
      }
      if (paymentData['userId'] != userObjectId) {
        return ResponseHelper.error(
          errorMessage: 'Payment belongs to another user',
          statusCode: 403,
        );
      }
      if (paymentData['purpose'] != 'subscription') {
        return ResponseHelper.error(
          errorMessage: 'Payment is not a subscription purchase',
          statusCode: 409,
        );
      }

      final savedPaymentId = paymentData['paymentId']?.toString();
      if (savedPaymentId == null || savedPaymentId.isEmpty) {
        return ResponseHelper.error(
          errorMessage: 'Payment ID is missing in saved payment',
          statusCode: 500,
        );
      }

      final state = await TBankPaymentService.forApp(
        _paymentAppId(paymentData),
      ).getState(paymentId: savedPaymentId);
      final expectedAmountKopecks = (paymentData['amountKopecks'] as num)
          .toInt();
      final now = DateTime.now().toUtc().toIso8601String();
      final rebillId = _readString(state.raw, 'RebillId');
      final stateModifier = modify
          .set('status', state.status)
          .set('rawState', state.raw)
          .set('updatedAt', now);
      if (rebillId != null) {
        stateModifier.set('rebillId', rebillId);
      }
      await paymentsCollection.updateOne(
        where.eq('paymentId', savedPaymentId),
        stateModifier,
      );

      if (!state.isConfirmed) {
        return ResponseHelper.success(
          data: {
            'provider': _tBankProvider,
            'paymentId': savedPaymentId,
            'orderId': paymentData['orderId'],
            'status': state.status,
            'confirmed': false,
            'applied': paymentData['applied'] == true,
          },
        );
      }

      if (state.amountKopecks != expectedAmountKopecks) {
        return ResponseHelper.error(
          errorMessage: 'Payment amount mismatch',
          statusCode: 409,
        );
      }

      final result = await _applyConfirmedTBankSubscriptionPayment(
        userId: userObjectId,
        payment: {...paymentData, 'rebillId': ?rebillId},
      );
      final modifier = modify
          .set('applied', true)
          .set('appliedAt', now)
          .set('updatedAt', now);
      if (paymentData['autoRenewRequested'] == true && rebillId != null) {
        modifier
            .set('subscriptionAutoRenewEnabled', true)
            .set(
              'subscriptionNextChargeAt',
              result.subscriptionExpiresAt.toIso8601String(),
            );
        await _enableUserSubscriptionAutoRenew(
          userId: userObjectId,
          appId:
              paymentData['contextAppId']?.toString() ??
              paymentData['context_app_id']?.toString() ??
              paymentData['appId']?.toString() ??
              paymentData['app_id']?.toString(),
          scope: paymentData['scope']?.toString(),
          rebillId: rebillId,
          nextChargeAt: result.subscriptionExpiresAt,
          paymentId: savedPaymentId,
          orderId: paymentData['orderId']?.toString(),
        );
      }
      await paymentsCollection.updateOne(
        where.eq('paymentId', savedPaymentId),
        modifier,
      );

      return ResponseHelper.success(
        data: {
          'provider': _tBankProvider,
          'paymentId': savedPaymentId,
          'orderId': paymentData['orderId'],
          'status': state.status,
          'confirmed': true,
          'applied': true,
          'autoRenew': paymentData['autoRenewRequested'] == true,
          ...result.toJson(),
        },
      );
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on TBankPaymentException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> cancelSubscriptionAutoRenew(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final scope = _resolveScope(request: request, data: data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final user = User.fromJson(userData);
      final targetSubscription = user.subscriptionFor(
        scope: scope,
        appId: scope == BillingService.subscriptionScopeGlobal
            ? BillingService.globalAppId
            : appId,
      );
      final nextSubscriptions = targetSubscription == null
          ? user.subscriptions
          : User.upsertSubscription(
              user.subscriptions,
              UserSubscription(
                scope: targetSubscription.scope,
                appId: targetSubscription.appId,
                expiresAt: targetSubscription.expiresAt,
                autoRenewEnabled: false,
                nextChargeAt: null,
                rebillId: targetSubscription.rebillId,
                recurringPaymentId: targetSubscription.recurringPaymentId,
                recurringOrderId: targetSubscription.recurringOrderId,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      final legacySubscription = User.effectiveSubscriptionForAppFrom(
        nextSubscriptions,
        appId,
      );
      final result = await usersCollection.updateOne(
        where.eq('_id', userObjectId),
        modify
            .set(
              'subscriptions',
              nextSubscriptions.map((item) => item.toJson()).toList(),
            )
            .set(
              'subscriptionAutoRenewEnabled',
              legacySubscription?.autoRenewEnabled ?? false,
            )
            .set(
              'subscriptionNextChargeAt',
              legacySubscription?.nextChargeAt?.toIso8601String(),
            )
            .set('subscriptionAutoRenewCancelledAt', now)
            .set('updatedAt', now),
      );

      if (!result.isSuccess || result.nMatched == 0) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final updatedUserData = await MongoService.instance.db
          .collection(Collections.users)
          .findOne(where.eq('_id', userObjectId));
      return ResponseHelper.success(
        data: User.fromJson(updatedUserData!).toPublicJson(appId: appId),
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> buySubscriptionWithBalance(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final scope = _resolveScope(request: request, data: data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );

      final result = await BillingService.instance
          .purchaseSubscriptionWithBalance(
            userId: userObjectId,
            appId: appId,
            scope: scope,
          );
      return ResponseHelper.success(
        data: {
          'provider': 'balance',
          'paymentId': '',
          'orderId': '',
          'status': 'CONFIRMED',
          'confirmed': true,
          'applied': true,
          ...result.toJson(),
        },
      );
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> handleTBankNotification(Request request) async {
    try {
      final data = await _parseTBankNotificationData(request);
      final paymentId = _readString(data, 'PaymentId');
      final orderId = _readString(data, 'OrderId');
      final status = _readString(data, 'Status') ?? '';
      final rebillId = _readString(data, 'RebillId');
      final now = DateTime.now().toUtc();
      final paymentsCollection = MongoService.instance.db.collection(
        Collections.tbankPayments,
      );
      final paymentData = await paymentsCollection.findOne(
        paymentId != null && paymentId.isNotEmpty
            ? where.eq('paymentId', paymentId)
            : where.eq('orderId', orderId),
      );
      if (!TBankPaymentService.isValidNotificationToken(
        data,
        AppConfig.tBankPasswordForApp(_paymentAppId(paymentData)),
      )) {
        return Response.forbidden('Invalid token');
      }

      if (paymentData != null) {
        final savedPaymentId = paymentData['paymentId']?.toString();
        final savedOrderId = paymentData['orderId']?.toString();
        final modifier = modify
            .set('status', status)
            .set('rawNotification', data)
            .set('updatedAt', now.toIso8601String());
        if (rebillId != null && rebillId.isNotEmpty) {
          modifier.set('rebillId', rebillId);
        }

        await paymentsCollection.updateOne(
          savedPaymentId != null && savedPaymentId.isNotEmpty
              ? where.eq('paymentId', savedPaymentId)
              : where.eq('orderId', savedOrderId),
          modifier,
        );

        if (rebillId != null &&
            rebillId.isNotEmpty &&
            paymentData['autoRenewRequested'] == true &&
            paymentData['userId'] is ObjectId) {
          final userId = paymentData['userId'] as ObjectId;
          final userData = await MongoService.instance.db
              .collection(Collections.users)
              .findOne(where.eq('_id', userId));
          final user = userData == null ? null : User.fromJson(userData);
          final paymentAppId = BillingService.normalizeAppId(
            paymentData['contextAppId']?.toString() ??
                paymentData['context_app_id']?.toString() ??
                paymentData['appId']?.toString() ??
                paymentData['app_id']?.toString(),
          );
          final paymentScope = BillingService.normalizeSubscriptionScope(
            paymentData['scope']?.toString(),
          );
          final nextChargeAt =
              user
                  ?.subscriptionFor(
                    scope: paymentScope,
                    appId:
                        paymentScope == BillingService.subscriptionScopeGlobal
                        ? BillingService.globalAppId
                        : paymentAppId,
                  )
                  ?.expiresAt ??
              now.add(
                const Duration(days: BillingService.subscriptionPeriodDays),
              );
          await _enableUserSubscriptionAutoRenew(
            userId: userId,
            appId: paymentAppId,
            scope: paymentScope,
            rebillId: rebillId,
            nextChargeAt: nextChargeAt,
            paymentId: savedPaymentId,
            orderId: savedOrderId,
          );
        }

        if (status == 'CONFIRMED' &&
            paymentData['applied'] != true &&
            paymentData['userId'] is ObjectId &&
            (paymentData['purpose'] == 'subscription' ||
                paymentData['purpose'] == 'subscription_recurring')) {
          final amount = _parseInt(data['Amount']);
          final expectedAmount = (paymentData['amountKopecks'] as num?)
              ?.toInt();
          if (amount == null ||
              expectedAmount == null ||
              amount == expectedAmount) {
            final result = await _applyConfirmedTBankSubscriptionPayment(
              userId: paymentData['userId'] as ObjectId,
              payment: {
                ...paymentData,
                'paymentId': ?paymentId,
                'orderId': ?orderId,
                'rebillId': ?rebillId,
              },
            );
            final applyModifier = modify
                .set('applied', true)
                .set('appliedAt', now.toIso8601String())
                .set(
                  'subscriptionExpiresAt',
                  result.subscriptionExpiresAt.toIso8601String(),
                )
                .set('updatedAt', now.toIso8601String());
            if (paymentData['autoRenewRequested'] == true && rebillId != null) {
              applyModifier
                  .set('subscriptionAutoRenewEnabled', true)
                  .set(
                    'subscriptionNextChargeAt',
                    result.subscriptionExpiresAt.toIso8601String(),
                  );
              await _enableUserSubscriptionAutoRenew(
                userId: paymentData['userId'] as ObjectId,
                appId:
                    paymentData['contextAppId']?.toString() ??
                    paymentData['context_app_id']?.toString() ??
                    paymentData['appId']?.toString() ??
                    paymentData['app_id']?.toString(),
                scope: paymentData['scope']?.toString(),
                rebillId: rebillId,
                nextChargeAt: result.subscriptionExpiresAt,
                paymentId: paymentId,
                orderId: orderId,
              );
            }
            await paymentsCollection.updateOne(
              paymentId != null && paymentId.isNotEmpty
                  ? where.eq('paymentId', paymentId)
                  : where.eq('orderId', orderId),
              applyModifier,
            );
          }
        }
      }

      return Response.ok('OK');
    } catch (error) {
      developer.log('notification:error $error', name: 'UserBillingController');
      return Response.internalServerError(body: 'ERROR');
    }
  }

  static Future<Response> listRequestPackages(Request request) async {
    try {
      final packages = await BillingService.instance.listRequestPackages(
        activeOnly: true,
        appId: _resolveAppId(request),
        scope: _resolveNullableScope(request: request),
      );
      return ResponseHelper.success(
        data: packages.map((item) => item.toPublicJson()).toList(),
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> buyRequestPackageWithBalance(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final packageId = data['packageId']?.toString() ?? '';
      if (!ObjectId.isValidHexId(packageId)) {
        return ResponseHelper.error(errorMessage: 'Invalid package ID format');
      }

      final result = await BillingService.instance
          .purchaseRequestPackageWithBalance(
            userId: userObjectId,
            packageId: ObjectId.fromHexString(packageId),
            appId: appId,
          );
      return ResponseHelper.success(data: result.toJson());
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        details: error.details,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> initTBankRequestPackage(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final packageId = data['packageId']?.toString() ?? '';
      if (!ObjectId.isValidHexId(packageId)) {
        return ResponseHelper.error(errorMessage: 'Invalid package ID format');
      }

      final package = await BillingService.instance.findRequestPackage(
        ObjectId.fromHexString(packageId),
      );
      BillingService.instance.assertRequestPackageAvailableForApp(
        package,
        appId,
      );
      final amountKopecks = (package.price * 100).round();
      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final user = User.fromJson(userData);
      final orderId = _buildTBankOrderId(prefix: 'requests');
      final payment = await TBankPaymentService.forApp(appId).initPayment(
        orderId: orderId,
        amountKopecks: amountKopecks,
        description:
            data['description']?.toString() ??
            'Request package ${package.requestCount}',
        userId: userObjectId.oid,
        userEmail: user.email,
        userPhone: user.phoneNumber,
        language: data['language']?.toString() ?? 'ru',
        deviceOs: data['deviceOs']?.toString(),
        deviceBrowser: data['deviceBrowser']?.toString(),
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await MongoService.instance.db
          .collection(Collections.tbankPayments)
          .insertOne({
            'userId': userObjectId,
            'userName': user.name,
            'orderId': payment.orderId,
            'paymentId': payment.paymentId,
            'paymentUrl': payment.paymentUrl,
            'amount': package.price,
            'amountKopecks': payment.amountKopecks,
            'status': payment.status,
            'applied': false,
            'purpose': 'request_package',
            'appId': appId,
            'app_id': appId,
            'requestPackage': package.toPublicJson(),
            'createdAt': now,
            'updatedAt': now,
          });

      return ResponseHelper.success(
        data: {
          'provider': _tBankProvider,
          'paymentId': payment.paymentId,
          'orderId': payment.orderId,
          'paymentUrl': payment.paymentUrl,
          'amount': package.price,
          'amountKopecks': payment.amountKopecks,
          'status': payment.status,
          'package': package.toPublicJson(),
          'appId': appId,
          'app_id': appId,
        },
      );
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on TBankPaymentException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> confirmTBankRequestPackage(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final paymentId = data['paymentId']?.toString();
      final orderId = data['orderId']?.toString();
      if ((paymentId == null || paymentId.isEmpty) &&
          (orderId == null || orderId.isEmpty)) {
        return ResponseHelper.error(
          errorMessage: 'Payment ID or Order ID is required',
        );
      }

      final paymentsCollection = MongoService.instance.db.collection(
        Collections.tbankPayments,
      );
      final paymentData = await paymentsCollection.findOne(
        paymentId != null && paymentId.isNotEmpty
            ? where.eq('paymentId', paymentId)
            : where.eq('orderId', orderId),
      );
      if (paymentData == null) {
        return ResponseHelper.error(
          errorMessage: 'Payment not found',
          statusCode: 404,
        );
      }
      if (paymentData['userId'] != userObjectId) {
        return ResponseHelper.error(
          errorMessage: 'Payment belongs to another user',
          statusCode: 403,
        );
      }
      if (paymentData['purpose'] != 'request_package') {
        return ResponseHelper.error(
          errorMessage: 'Payment is not a request package purchase',
          statusCode: 409,
        );
      }

      final savedPaymentId = paymentData['paymentId']?.toString();
      if (savedPaymentId == null || savedPaymentId.isEmpty) {
        return ResponseHelper.error(
          errorMessage: 'Payment ID is missing in saved payment',
          statusCode: 500,
        );
      }

      final state = await TBankPaymentService.forApp(
        _paymentAppId(paymentData),
      ).getState(paymentId: savedPaymentId);
      final expectedAmountKopecks = (paymentData['amountKopecks'] as num)
          .toInt();
      final now = DateTime.now().toUtc().toIso8601String();
      await paymentsCollection.updateOne(
        where.eq('paymentId', savedPaymentId),
        modify
            .set('status', state.status)
            .set('rawState', state.raw)
            .set('updatedAt', now),
      );

      if (!state.isConfirmed) {
        return ResponseHelper.success(
          data: {
            'provider': _tBankProvider,
            'paymentId': savedPaymentId,
            'orderId': paymentData['orderId'],
            'status': state.status,
            'confirmed': false,
            'applied': paymentData['applied'] == true,
          },
        );
      }

      if (state.amountKopecks != expectedAmountKopecks) {
        return ResponseHelper.error(
          errorMessage: 'Payment amount mismatch',
          statusCode: 409,
        );
      }

      final result = await _applyConfirmedTBankRequestPackagePayment(
        userId: userObjectId,
        payment: paymentData,
      );
      await paymentsCollection.updateOne(
        where.eq('paymentId', savedPaymentId),
        modify.set('applied', true).set('appliedAt', now).set('updatedAt', now),
      );

      return ResponseHelper.success(
        data: {
          'provider': _tBankProvider,
          'paymentId': savedPaymentId,
          'orderId': paymentData['orderId'],
          'status': state.status,
          'confirmed': true,
          'applied': true,
          ...result.toJson(),
        },
      );
    } on BillingServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on TBankPaymentException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Создать платеж Т-Банка и вернуть приложению ссылку на платежную форму.
  static Future<Response> initTBankTopUp(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final userId = userObjectId.oid;

      final rawAmount = double.tryParse(data['amount'].toString());
      if (rawAmount == null || rawAmount < _minimumTopUpAmount) {
        return ResponseHelper.error(
          errorMessage: 'Amount must be at least 99 RUB',
        );
      }

      final amount = _normalizeMoneyAmount(rawAmount);
      final amountKopecks = (amount * 100).round();
      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final user = User.fromJson(userData);
      final orderId = _buildTBankOrderId();
      final payment = await TBankPaymentService.forApp(appId).initPayment(
        orderId: orderId,
        amountKopecks: amountKopecks,
        description: data['description']?.toString() ?? 'Balance top-up',
        userId: userId,
        userEmail: user.email,
        userPhone: user.phoneNumber,
        language: data['language']?.toString() ?? 'ru',
        deviceOs: data['deviceOs']?.toString(),
        deviceBrowser: data['deviceBrowser']?.toString(),
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await MongoService.instance.db
          .collection(Collections.tbankPayments)
          .insertOne({
            'userId': userObjectId,
            'userName': user.name,
            'orderId': payment.orderId,
            'paymentId': payment.paymentId,
            'paymentUrl': payment.paymentUrl,
            'amount': amount,
            'amountKopecks': payment.amountKopecks,
            'status': payment.status,
            'applied': false,
            'appId': appId,
            'app_id': appId,
            'createdAt': now,
            'updatedAt': now,
          });

      return ResponseHelper.success(
        data: {
          'provider': _tBankProvider,
          'paymentId': payment.paymentId,
          'orderId': payment.orderId,
          'paymentUrl': payment.paymentUrl,
          'amount': amount,
          'amountKopecks': payment.amountKopecks,
          'status': payment.status,
          'appId': appId,
          'app_id': appId,
        },
      );
    } on TBankPaymentException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      _log('initTBankTopUp:error $error');
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Проверить платеж в Т-Банке и начислить баланс только после CONFIRMED.
  static Future<Response> confirmTBankTopUp(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final paymentId = data['paymentId']?.toString();
      final orderId = data['orderId']?.toString();
      if ((paymentId == null || paymentId.isEmpty) &&
          (orderId == null || orderId.isEmpty)) {
        return ResponseHelper.error(
          errorMessage: 'Payment ID or Order ID is required',
        );
      }

      final paymentsCollection = MongoService.instance.db.collection(
        Collections.tbankPayments,
      );
      final paymentData = await paymentsCollection.findOne(
        paymentId != null && paymentId.isNotEmpty
            ? where.eq('paymentId', paymentId)
            : where.eq('orderId', orderId),
      );
      if (paymentData == null) {
        return ResponseHelper.error(
          errorMessage: 'Payment not found',
          statusCode: 404,
        );
      }
      if (paymentData['userId'] != userObjectId) {
        return ResponseHelper.error(
          errorMessage: 'Payment belongs to another user',
          statusCode: 403,
        );
      }

      final savedPaymentId = paymentData['paymentId']?.toString();
      if (savedPaymentId == null || savedPaymentId.isEmpty) {
        return ResponseHelper.error(
          errorMessage: 'Payment ID is missing in saved payment',
          statusCode: 500,
        );
      }

      final state = await TBankPaymentService.forApp(
        _paymentAppId(paymentData),
      ).getState(paymentId: savedPaymentId);
      final expectedAmountKopecks = (paymentData['amountKopecks'] as num)
          .toInt();
      final now = DateTime.now().toUtc().toIso8601String();
      await paymentsCollection.updateOne(
        where.eq('paymentId', savedPaymentId),
        modify
            .set('status', state.status)
            .set('rawState', state.raw)
            .set('updatedAt', now),
      );

      if (!state.isConfirmed) {
        return ResponseHelper.success(
          data: {
            'provider': _tBankProvider,
            'paymentId': savedPaymentId,
            'orderId': paymentData['orderId'],
            'status': state.status,
            'confirmed': false,
            'applied': paymentData['applied'] == true,
          },
        );
      }

      if (state.amountKopecks != expectedAmountKopecks) {
        return ResponseHelper.error(
          errorMessage: 'Payment amount mismatch',
          statusCode: 409,
        );
      }

      final result = await _applyConfirmedTBankPayment(
        userId: userObjectId,
        payment: paymentData,
      );
      await paymentsCollection.updateOne(
        where.eq('paymentId', savedPaymentId),
        modify.set('applied', true).set('appliedAt', now).set('updatedAt', now),
      );

      return ResponseHelper.success(
        data: {
          'provider': _tBankProvider,
          'paymentId': savedPaymentId,
          'orderId': paymentData['orderId'],
          'status': state.status,
          'confirmed': true,
          'applied': true,
          'transaction': result.transaction.toPublicJson(),
          'newBalance': result.newBalance,
          'paidAmount': (paymentData['amount'] as num).toDouble(),
          'bonusAmount': BillingService.topUpBonusAmount(
            (paymentData['amount'] as num).toDouble(),
          ),
          'creditedAmount': result.transaction.amount,
        },
      );
    } on TBankPaymentException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (error) {
      _log('confirmTBankTopUp:error $error');
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${error.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Пополнение баланса пользователя через старый общий endpoint.
  /// Сейчас основной платежный путь для приложения - Т-Банк выше.
  static Future<Response> depositBalance(Request request) async {
    try {
      // Читаем JSON из body запроса.
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);

      // userId говорит, кому начислять деньги.
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );
      final userId = userObjectId.oid;

      // amount - сумма пополнения.
      if (data['amount'] == null) {
        return ResponseHelper.error(errorMessage: 'Amount is required');
      }

      // Превращаем amount в double и сразу отсекаем ноль/минус.
      final rawAmount = double.tryParse(data['amount'].toString());
      if (rawAmount == null || rawAmount < _minimumTopUpAmount) {
        return ResponseHelper.error(
          errorMessage: 'Amount must be at least 99 RUB',
        );
      }

      // Деньги нормализуем до двух знаков после запятой.
      final amount = _normalizeMoneyAmount(rawAmount);

      // metadata - данные платежной системы:
      // provider, purchaseId, invoiceId и т.д.
      final metadata = _parseMetadata(data['metadata']);
      _log(
        'depositBalance:start userId=$userId amount=$amount provider=${metadata?['provider']} purchaseId=${metadata?['purchaseId']} invoiceId=${metadata?['invoiceId']}',
      );

      // Достаём нужные коллекции MongoDB.
      final db = MongoService.instance.db;
      final usersCollection = db.collection(Collections.users);
      final transactionsCollection = db.collection(Collections.transactions);

      // Превращаем строковый userId в ObjectId для MongoDB.
      // Проверяем, что пользователь существует.
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );

      if (userData == null) {
        _log('depositBalance:userNotFound userId=$userId');
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final user = User.fromJson(userData);

      // Перед начислением ищем такую же покупку в истории.
      // Это защита от повторного начисления одного внешнего платежа.
      final duplicateTransaction = await _findDuplicateDepositTransaction(
        transactionsCollection: transactionsCollection,
        provider: _stringOrNull(metadata?['provider']),
        purchaseId: _stringOrNull(metadata?['purchaseId']),
        invoiceId: _stringOrNull(metadata?['invoiceId']),
      );

      if (duplicateTransaction != null) {
        // Если платеж уже был начислен другому пользователю,
        // это конфликт и мы не трогаем баланс.
        final duplicateUserId = duplicateTransaction['userId'] as ObjectId?;
        if (duplicateUserId != null && duplicateUserId != userObjectId) {
          _log(
            'depositBalance:duplicateConflict userId=$userId duplicateUserId=${duplicateUserId.oid}',
          );
          return ResponseHelper.error(
            errorMessage: 'Purchase already applied to another user',
            statusCode: 409,
            errorCode: purchaseAlreadyAppliedErrorCode,
          );
        }

        // Если платеж уже был начислен этому же пользователю,
        // не создаём дубль, а возвращаем старую транзакцию.
        _log(
          'depositBalance:duplicateReuse userId=$userId transactionId=${duplicateTransaction['_id']}',
        );
        return ResponseHelper.success(
          data: {
            'transaction': Transaction.fromJson(
              duplicateTransaction,
            ).toPublicJson(),
            'newBalance': user.balance,
          },
        );
      }

      // Пользователь платит amount, но на баланс зачисляем amount + 10%.
      // Бонус нужен как приятный сюрприз за любое пополнение.
      final bonusAmount = BillingService.topUpBonusAmount(amount);
      final creditedAmount = BillingService.creditedTopUpAmount(amount);

      // Считаем новый баланс уже по сумме с бонусом.
      final newBalance = _normalizeMoneyAmount(user.balance + creditedAmount);

      // Обновляем баланс пользователя в MongoDB.
      final updateResult = await usersCollection.updateOne(
        where.eq('_id', userObjectId),
        modify
            .set('balance', newBalance)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );

      if (!updateResult.isSuccess || updateResult.nMatched == 0) {
        _log('depositBalance:updateFailed userId=$userId');
        return ResponseHelper.error(
          errorMessage: 'Failed to update balance',
          statusCode: 500,
        );
      }

      // Создаём объект транзакции для истории.
      final transaction = Transaction(
        userId: userObjectId,
        userName: user.name,
        amount: creditedAmount,
        type: TransactionType.deposit,
        description: data['description']?.toString() ?? 'Balance deposit',
        metadata: {
          ...?metadata,
          'appId': appId,
          'app_id': appId,
          'paidAmount': amount,
          'bonusAmount': bonusAmount,
          'creditedAmount': creditedAmount,
          'bonusPercent': BillingService.topUpBonusPercent,
        },
      );

      // Сохраняем транзакцию в отдельную коллекцию.
      final transactionResult = await transactionsCollection.insertOne(
        transaction.toJson(),
      );

      // Если баланс уже обновили, но транзакция не сохранилась,
      // возвращаем баланс назад. Иначе история и баланс разъедутся.
      if (!transactionResult.isSuccess) {
        _log('depositBalance:transactionInsertFailed userId=$userId');
        await usersCollection.updateOne(
          where.eq('_id', userObjectId),
          modify
              .set('balance', user.balance)
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );

        return ResponseHelper.error(
          errorMessage: 'Failed to create transaction',
          statusCode: 500,
        );
      }

      // Перечитываем созданную транзакцию, чтобы вернуть клиенту полный JSON.
      final createdTransaction = await transactionsCollection.findOne(
        where.eq('_id', transactionResult.id),
      );
      _log(
        'depositBalance:success userId=$userId transactionId=${transactionResult.id} newBalance=$newBalance',
      );

      // Успешный ответ для Flutter:
      // транзакция + новый баланс.
      return ResponseHelper.success(
        data: {
          'transaction': createdTransaction != null
              ? Transaction.fromJson(createdTransaction).toPublicJson()
              : null,
          'newBalance': newBalance,
          'paidAmount': amount,
          'bonusAmount': bonusAmount,
          'creditedAmount': creditedAmount,
        },
      );
    } on JwtAuthException catch (e) {
      return ResponseHelper.error(
        errorMessage: e.message,
        statusCode: e.statusCode,
      );
    } catch (e) {
      // Любая неожиданная ошибка превращается в 500.
      _log('depositBalance:error $e');
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// История транзакций и текущий баланс пользователя.
  static Future<Response> listTransactions(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);

      // Без userId не знаем, чью историю показывать.
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );

      // limit ограничивает, сколько транзакций вернуть.
      final limit = int.tryParse(data['limit']?.toString() ?? '') ?? 50;
      final normalizedLimit = limit.clamp(1, 200);

      final db = MongoService.instance.db;
      final usersCollection = db.collection(Collections.users);
      final transactionsCollection = db.collection(Collections.transactions);
      // Сначала проверяем пользователя, чтобы вернуть 404 при неверном userId.
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );

      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final user = User.fromJson(userData);

      // Берём все транзакции этого пользователя.
      final rawTransactions = await transactionsCollection
          .find(where.eq('userId', userObjectId))
          .toList();

      // Превращаем сырые документы MongoDB в модели и сортируем новые сверху.
      final transactions = rawTransactions.map(Transaction.fromJson).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return ResponseHelper.success(
        data: {
          'balance': user.balance,
          'requestBalance': user.effectiveRequestBalanceForApp(appId),
          'transactions': transactions
              .take(normalizedLimit)
              .map((item) => item.toPublicJson())
              .toList(),
        },
      );
    } on JwtAuthException catch (e) {
      return ResponseHelper.error(
        errorMessage: e.message,
        statusCode: e.statusCode,
      );
    } catch (e) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Применение промокода к балансу пользователя.
  static Future<Response> applyPromoCode(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(request, data);

      // Проверяем userId.
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );

      // Проверяем, что код вообще пришёл.
      final promoCode = data['promoCode']?.toString() ?? '';
      if (promoCode.trim().isEmpty) {
        return ResponseHelper.error(errorMessage: 'Promo code is required');
      }

      // Вся сложная логика промокодов находится в PromoCodeService.
      final result = await PromoCodeService.instance.applyPromoCode(
        userId: userObjectId,
        code: promoCode,
        appId: appId,
      );

      // Возвращаем созданную транзакцию и новый баланс.
      return ResponseHelper.success(
        data: {
          'transaction': result.transaction.toPublicJson(),
          'newBalance': result.newBalance,
          'appId': appId,
          'app_id': appId,
        },
      );
    } on PromoCodeServiceException catch (error) {
      // Ошибки промокодов ожидаемые:
      // код не найден, уже использован, выключен и т.д.
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
      );
    } on JwtAuthException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
      );
    } catch (e) {
      // Неожиданная ошибка сервера.
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Функция _findDuplicateDepositTransaction: выполняет шаг _findDuplicateDepositTransaction в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static Future<Map<String, dynamic>?> _findDuplicateDepositTransaction({
    required DbCollection transactionsCollection,
    required String? provider,
    required String? purchaseId,
    required String? invoiceId,
  }) async {
    // Если provider нет, мы не можем понять, откуда платёж.
    // Тогда проверку дублей по данным платежной системы не делаем.
    if (provider == null || provider.isEmpty) {
      return null;
    }

    // Для поиска дубля нужен хотя бы purchaseId или invoiceId.
    final hasPurchaseId = purchaseId != null && purchaseId.isNotEmpty;
    final hasInvoiceId = invoiceId != null && invoiceId.isNotEmpty;
    if (!hasPurchaseId && !hasInvoiceId) {
      return null;
    }

    // Берём все deposit-транзакции этого provider-а.
    // Потом проверяем metadata вручную.
    final existingTransactions = await transactionsCollection
        .find(
          where
              .eq('type', TransactionType.deposit.name)
              .eq('metadata.provider', provider),
        )
        .toList();

    for (final rawTransaction in existingTransactions) {
      final transaction = Map<String, dynamic>.from(rawTransaction);
      final metadata = _parseMetadata(transaction['metadata']);
      if (metadata == null) {
        continue;
      }

      // Совпадение хотя бы по одному надёжному id означает:
      // покупка уже была обработана.
      final samePurchaseId =
          hasPurchaseId && metadata['purchaseId']?.toString() == purchaseId;
      final sameInvoiceId =
          hasInvoiceId && metadata['invoiceId']?.toString() == invoiceId;

      if (samePurchaseId || sameInvoiceId) {
        return transaction;
      }
    }

    return null;
  }

  /// Функция _parseMetadata: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает текст.
  static Map<String, dynamic>? _parseMetadata(dynamic rawMetadata) {
    // metadata может прийти как Map из JSON.
    // Приводим ключи к строкам, чтобы дальше безопасно читать поля.
    if (rawMetadata is Map) {
      return rawMetadata.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  /// Функция _stringOrNull: выполняет шаг _stringOrNull в этой части программы. Возвращает текст или пустое значение, если текста нет.
  /// Возвращает текст или пустое значение, если текста нет.
  static String? _stringOrNull(dynamic value) {
    // Удобный helper:
    // пустая строка считается отсутствующим значением.
    final stringValue = value?.toString().trim();
    if (stringValue == null || stringValue.isEmpty) {
      return null;
    }

    return stringValue;
  }

  /// Функция _normalizeMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает число с копейками или дробной частью.
  static double _normalizeMoneyAmount(double amount) {
    // Округляем деньги до копеек.
    return double.parse(amount.toStringAsFixed(2));
  }

  /// Функция _buildTBankOrderId: собирает и возвращает видимый кусок экрана, который пользователь видит в приложении.
  /// Возвращает текст.
  static String _buildTBankOrderId({String prefix = 'topup'}) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  static Future<RequestPackagePurchaseResult>
  _applyConfirmedTBankRequestPackagePayment({
    required ObjectId userId,
    required Map<String, dynamic> payment,
  }) async {
    final rawPackage = payment['requestPackage'];
    if (rawPackage is! Map) {
      throw const TBankPaymentException(
        'Request package is missing in saved payment',
        statusCode: 500,
      );
    }

    final rawPackageId = rawPackage['_id']?.toString();
    if (rawPackageId == null || !ObjectId.isValidHexId(rawPackageId)) {
      throw const TBankPaymentException(
        'Request package ID is invalid',
        statusCode: 500,
      );
    }

    final package = await BillingService.instance.findRequestPackage(
      ObjectId.fromHexString(rawPackageId),
      activeOnly: false,
    );
    return BillingService.instance.applyRequestPackageCardPurchase(
      userId: userId,
      package: package,
      paymentId: payment['paymentId']?.toString(),
      orderId: payment['orderId']?.toString(),
      appId: payment['appId']?.toString() ?? payment['app_id']?.toString(),
    );
  }

  static Future<SubscriptionPurchaseResult>
  _applyConfirmedTBankSubscriptionPayment({
    required ObjectId userId,
    required Map<String, dynamic> payment,
  }) async {
    final rawSubscription = payment['subscription'];
    if (rawSubscription is! Map) {
      throw const TBankPaymentException(
        'Subscription is missing in saved payment',
        statusCode: 500,
      );
    }

    final subscription = Map<String, dynamic>.from(rawSubscription);
    final name = subscription['name']?.toString() ?? '';
    final price = (subscription['price'] as num?)?.toDouble();
    final appId = BillingService.normalizeAppId(
      subscription['appId']?.toString() ??
          subscription['app_id']?.toString() ??
          payment['appId']?.toString() ??
          payment['app_id']?.toString(),
    );
    final scope = BillingService.normalizeSubscriptionScope(
      subscription['scope']?.toString() ?? payment['scope']?.toString(),
    );
    if (name.trim().isEmpty || price == null || price <= 0) {
      throw const TBankPaymentException(
        'Subscription settings are invalid',
        statusCode: 500,
      );
    }

    final settings = SubscriptionSettings(
      name: name,
      price: price,
      appId: scope == BillingService.subscriptionScopeGlobal
          ? BillingService.globalAppId
          : appId,
      scope: scope,
      updatedAt: DateTime.now().toUtc(),
    );
    return BillingService.instance.applySubscriptionCardPurchase(
      userId: userId,
      settings: settings,
      paymentId: payment['paymentId']?.toString(),
      orderId: payment['orderId']?.toString(),
      appId:
          payment['contextAppId']?.toString() ??
          payment['context_app_id']?.toString() ??
          appId,
    );
  }

  static Future<SubscriptionPurchaseResult> applySavedSubscriptionPayment({
    required ObjectId userId,
    required Map<String, dynamic> payment,
  }) {
    return _applyConfirmedTBankSubscriptionPayment(
      userId: userId,
      payment: payment,
    );
  }

  static Future<void> enableUserSubscriptionAutoRenew({
    required ObjectId userId,
    String? appId,
    String? scope,
    required String rebillId,
    required DateTime nextChargeAt,
    String? paymentId,
    String? orderId,
  }) {
    return _enableUserSubscriptionAutoRenew(
      userId: userId,
      appId: appId,
      scope: scope,
      rebillId: rebillId,
      nextChargeAt: nextChargeAt,
      paymentId: paymentId,
      orderId: orderId,
    );
  }

  static Future<void> _enableUserSubscriptionAutoRenew({
    required ObjectId userId,
    String? appId,
    String? scope,
    required String rebillId,
    required DateTime nextChargeAt,
    String? paymentId,
    String? orderId,
  }) async {
    final usersCollection = MongoService.instance.db.collection(
      Collections.users,
    );
    final rawUser = await usersCollection.findOne(where.eq('_id', userId));
    if (rawUser == null) {
      return;
    }

    final user = User.fromJson(rawUser);
    final normalizedAppId = BillingService.normalizeAppId(appId);
    final normalizedScope = BillingService.normalizeSubscriptionScope(scope);
    final subscriptionAppId =
        normalizedScope == BillingService.subscriptionScopeGlobal
        ? BillingService.globalAppId
        : normalizedAppId;
    final existingSubscription = user.subscriptionFor(
      scope: normalizedScope,
      appId: subscriptionAppId,
    );
    final now = DateTime.now().toUtc();
    final nextSubscriptions = User.upsertSubscription(
      user.subscriptions,
      UserSubscription(
        scope: normalizedScope,
        appId: subscriptionAppId,
        expiresAt: existingSubscription?.expiresAt ?? nextChargeAt,
        autoRenewEnabled: true,
        nextChargeAt: nextChargeAt,
        rebillId: rebillId,
        recurringPaymentId: paymentId,
        recurringOrderId: orderId,
        updatedAt: now,
      ),
    );
    final legacySubscription = User.effectiveSubscriptionForAppFrom(
      nextSubscriptions,
      normalizedAppId,
    );
    await usersCollection.updateOne(
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
          .set('subscriptionRebillId', legacySubscription?.rebillId)
          .set(
            'subscriptionNextChargeAt',
            legacySubscription?.nextChargeAt?.toIso8601String(),
          )
          .set('subscriptionRecurringPaymentId', paymentId)
          .set('subscriptionRecurringOrderId', orderId)
          .set('subscriptionAutoRenewUpdatedAt', now.toIso8601String())
          .set('updatedAt', now.toIso8601String()),
    );
  }

  static String _resolveAppId(Request request, [Map<String, dynamic>? data]) {
    return BillingService.normalizeAppId(
      data?['appId']?.toString() ??
          data?['app_id']?.toString() ??
          request.url.queryParameters['appId'] ??
          request.url.queryParameters['app_id'] ??
          request.headers['x-app-id'],
    );
  }

  static String _resolveScope({Request? request, Map<String, dynamic>? data}) {
    return BillingService.normalizeSubscriptionScope(
      data?['scope']?.toString() ??
          data?['subscriptionScope']?.toString() ??
          request?.url.queryParameters['scope'] ??
          request?.url.queryParameters['subscriptionScope'] ??
          request?.headers['x-subscription-scope'],
    );
  }

  static String? _resolveNullableScope({
    Request? request,
    Map<String, dynamic>? data,
  }) {
    final rawScope =
        data?['scope']?.toString() ??
        data?['subscriptionScope']?.toString() ??
        request?.url.queryParameters['scope'] ??
        request?.url.queryParameters['subscriptionScope'] ??
        request?.headers['x-subscription-scope'];
    if (rawScope == null || rawScope.trim().isEmpty) {
      return null;
    }
    return BillingService.normalizeSubscriptionScope(rawScope);
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final normalized = value?.toString().toLowerCase().trim();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static Future<Map<String, dynamic>> _parseTBankNotificationData(
    Request request,
  ) async {
    final body = await request.readAsString();
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // T-Банк может прислать callback как form-urlencoded.
    }

    return Map<String, dynamic>.from(Uri.splitQueryString(trimmedBody));
  }

  static int? _parseInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _readString(Map<String, dynamic>? data, String key) {
    final value = data?[key] ?? data?[key.toLowerCase()];
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static String? _paymentAppId(Map<String, dynamic>? payment) {
    if (payment == null) {
      return null;
    }
    return _stringOrNull(payment['contextAppId']) ??
        _stringOrNull(payment['context_app_id']) ??
        _stringOrNull(payment['appId']) ??
        _stringOrNull(payment['app_id']);
  }

  static Future<({Transaction transaction, double newBalance})>
  _applyConfirmedTBankPayment({
    required ObjectId userId,
    required Map<String, dynamic> payment,
  }) async {
    final db = MongoService.instance.db;
    final usersCollection = db.collection(Collections.users);
    final transactionsCollection = db.collection(Collections.transactions);
    final paymentId = payment['paymentId']?.toString();
    final orderId = payment['orderId']?.toString();
    final appId =
        _stringOrNull(payment['appId']) ?? _stringOrNull(payment['app_id']);

    final userData = await usersCollection.findOne(where.eq('_id', userId));
    if (userData == null) {
      throw const TBankPaymentException('User not found', statusCode: 404);
    }
    final user = User.fromJson(userData);

    final duplicateTransaction = await _findDuplicateDepositTransaction(
      transactionsCollection: transactionsCollection,
      provider: _tBankProvider,
      purchaseId: paymentId,
      invoiceId: orderId,
    );
    if (duplicateTransaction != null) {
      return (
        transaction: Transaction.fromJson(duplicateTransaction),
        newBalance: user.balance,
      );
    }

    final amount = _normalizeMoneyAmount((payment['amount'] as num).toDouble());
    final bonusAmount = BillingService.topUpBonusAmount(amount);
    final creditedAmount = BillingService.creditedTopUpAmount(amount);
    final newBalance = _normalizeMoneyAmount(user.balance + creditedAmount);
    final updateResult = await usersCollection.updateOne(
      where.eq('_id', userId),
      modify
          .set('balance', newBalance)
          .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
    );
    if (!updateResult.isSuccess || updateResult.nMatched == 0) {
      throw const TBankPaymentException(
        'Failed to update balance',
        statusCode: 500,
      );
    }

    final transaction = Transaction(
      userId: userId,
      userName: user.name,
      amount: creditedAmount,
      type: TransactionType.deposit,
      description: 'T-Bank balance top-up',
      metadata: {
        'provider': _tBankProvider,
        'paymentId': paymentId,
        'purchaseId': paymentId,
        'orderId': orderId,
        'invoiceId': orderId,
        'amountKopecks': payment['amountKopecks'],
        'appId': ?appId,
        'app_id': ?appId,
        'paidAmount': amount,
        'bonusAmount': bonusAmount,
        'creditedAmount': creditedAmount,
        'bonusPercent': BillingService.topUpBonusPercent,
      },
    );
    final transactionResult = await transactionsCollection.insertOne(
      transaction.toJson(),
    );
    if (!transactionResult.isSuccess) {
      await usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set('balance', user.balance)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const TBankPaymentException(
        'Failed to create transaction',
        statusCode: 500,
      );
    }

    final createdTransaction = await transactionsCollection.findOne(
      where.eq('_id', transactionResult.id),
    );
    return (
      transaction: createdTransaction != null
          ? Transaction.fromJson(createdTransaction)
          : transaction,
      newBalance: newBalance,
    );
  }

  /// Функция _log: выполняет шаг _log в этой части программы. Ничего не возвращает, только выполняет действие.
  /// Ничего не возвращает, только выполняет действие.
  static void _log(String message) {
    // Логи контроллера удобно фильтровать по имени UserBillingController.
    developer.log(message, name: 'UserBillingController');
  }
}
