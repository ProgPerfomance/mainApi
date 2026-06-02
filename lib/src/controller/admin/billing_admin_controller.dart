// Этот файл: lib/src/controller/admin/billing_admin_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// Класс BillingAdminController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class BillingAdminController {
  /// Функция getAiRequestSettings: получает нужное значение и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> getAiRequestSettings(Request request) async {
    try {
      final requestPrice = await BillingService.instance.getAiRequestPrice();
      final referralBonusAmount = await BillingService.instance
          .getReferralBonusAmount();
      final appId = _resolveAppId(request);
      final scope = _resolveScope(request: request);
      final subscriptionSettings = await BillingService.instance
          .getSubscriptionSettings(appId: appId, scope: scope);

      return ResponseHelper.success(
        data: {
          'requestPrice': requestPrice,
          'referralBonusAmount': referralBonusAmount,
          'subscription': subscriptionSettings.toPublicJson(),
        },
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция updateAiRequestSettings: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> updateAiRequestSettings(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);

      final hasRequestPrice = data['requestPrice'] != null;
      final hasReferralBonusAmount = data['referralBonusAmount'] != null;
      final hasSubscriptionName = data['subscriptionName'] != null;
      final hasSubscriptionPrice = data['subscriptionPrice'] != null;
      final appId = _resolveAppId(request, data);
      final scope = _resolveScope(request: request, data: data);

      if (!hasRequestPrice &&
          !hasReferralBonusAmount &&
          !hasSubscriptionName &&
          !hasSubscriptionPrice) {
        return ResponseHelper.error(
          errorMessage:
              'Request price, referral bonus or subscription settings are required',
        );
      }

      double? requestPrice;
      if (hasRequestPrice) {
        requestPrice = double.tryParse(data['requestPrice'].toString());
        if (requestPrice == null || requestPrice < 0) {
          return ResponseHelper.error(
            errorMessage: 'Request price must be a non-negative number',
          );
        }
      }

      double? referralBonusAmount;
      if (hasReferralBonusAmount) {
        referralBonusAmount = double.tryParse(
          data['referralBonusAmount'].toString(),
        );
        if (referralBonusAmount == null || referralBonusAmount < 0) {
          return ResponseHelper.error(
            errorMessage: 'Referral bonus amount must be a non-negative number',
          );
        }
      }

      String? subscriptionName;
      if (hasSubscriptionName) {
        subscriptionName = data['subscriptionName']?.toString() ?? '';
        if (subscriptionName.trim().isEmpty) {
          return ResponseHelper.error(
            errorMessage: 'Subscription name is required',
          );
        }
      }

      double? subscriptionPrice;
      if (hasSubscriptionPrice) {
        subscriptionPrice = double.tryParse(
          data['subscriptionPrice'].toString(),
        );
        if (subscriptionPrice == null || subscriptionPrice <= 0) {
          return ResponseHelper.error(
            errorMessage: 'Subscription price must be a positive number',
          );
        }
      }

      final savedPrice = requestPrice != null
          ? await BillingService.instance.setAiRequestPrice(requestPrice)
          : await BillingService.instance.getAiRequestPrice();
      final savedReferralBonusAmount = referralBonusAmount != null
          ? await BillingService.instance.setReferralBonusAmount(
              referralBonusAmount,
            )
          : await BillingService.instance.getReferralBonusAmount();
      final currentSubscription = await BillingService.instance
          .getSubscriptionSettings(appId: appId, scope: scope);
      final savedSubscription =
          subscriptionName != null || subscriptionPrice != null
          ? await BillingService.instance.setSubscriptionSettings(
              name: subscriptionName ?? currentSubscription.name,
              price: subscriptionPrice ?? currentSubscription.price,
              appId: appId,
              scope: scope,
            )
          : currentSubscription;

      return ResponseHelper.success(
        data: {
          'requestPrice': savedPrice,
          'referralBonusAmount': savedReferralBonusAmount,
          'subscription': savedSubscription.toPublicJson(),
        },
      );
    } on BillingServiceException catch (error) {
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

  /// Функция listAiRequestCharges: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listAiRequestCharges(Request request) async {
    try {
      final limitParam = request.url.queryParameters['limit'];
      final limit =
          int.tryParse(limitParam ?? '') ??
          BillingService.defaultAdminHistoryLimit;
      final transactions = await BillingService.instance
          .listAiChargeTransactions(limit: limit);

      return ResponseHelper.success(data: transactions);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> listRequestPackages(Request request) async {
    try {
      final packages = await BillingService.instance.listRequestPackages();
      return ResponseHelper.success(
        data: packages.map((item) => item.toPublicJson()).toList(),
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> createRequestPackage(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final requestCount = int.tryParse(data['requestCount'].toString());
      final price = double.tryParse(data['price'].toString());
      if (requestCount == null || price == null) {
        return ResponseHelper.error(
          errorMessage: 'Request count and price are required',
        );
      }

      final package = await BillingService.instance.createRequestPackage(
        requestCount: requestCount,
        price: price,
        appId: _resolveAppId(request, data),
        scope: _resolveScope(request: request, data: data),
        isActive: data['isActive'] != false,
      );
      return ResponseHelper.success(
        statusCode: 201,
        data: package.toPublicJson(),
      );
    } on BillingServiceException catch (error) {
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

  static Future<Response> updateRequestPackage(
    Request request,
    String id,
  ) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid package ID format');
      }

      final data = await parseRequestDataHelper(request);
      final package = await BillingService.instance.updateRequestPackage(
        packageId: ObjectId.fromHexString(id),
        requestCount: data['requestCount'] == null
            ? null
            : int.tryParse(data['requestCount'].toString()),
        price: data['price'] == null
            ? null
            : double.tryParse(data['price'].toString()),
        appId: data['appId'] == null && data['app_id'] == null
            ? null
            : _resolveAppId(request, data),
        scope: data['scope'] == null && data['subscriptionScope'] == null
            ? null
            : _resolveScope(data: data),
        isActive: data['isActive'] as bool?,
      );
      return ResponseHelper.success(data: package.toPublicJson());
    } on BillingServiceException catch (error) {
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

  static Future<Response> deleteRequestPackage(
    Request request,
    String id,
  ) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(errorMessage: 'Invalid package ID format');
      }

      await BillingService.instance.deleteRequestPackage(
        ObjectId.fromHexString(id),
      );
      return ResponseHelper.success(data: {'deleted': true});
    } on BillingServiceException catch (error) {
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
}
