// Этот файл: lib/src/controller/admin/promo_code_admin_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/promo/promo_code_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// Класс PromoCodeAdminController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class PromoCodeAdminController {
  /// Функция listPromoCodes: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listPromoCodes(Request request) async {
    try {
      final promoCodes = await PromoCodeService.instance.listPromoCodes(
        appId: request.url.queryParameters['appId'],
      );
      return ResponseHelper.success(data: promoCodes);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция createPromoCode: создаёт новую запись или объект и возвращает созданный результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> createPromoCode(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final code = data['code']?.toString() ?? '';
      final amount = double.tryParse(data['amount']?.toString() ?? '');
      final maxRedemptions = _parseMaxRedemptions(data, allowMissing: true);
      if (amount == null || amount <= 0) {
        return ResponseHelper.error(
          errorMessage: 'Amount must be a positive number',
        );
      }

      final promoCode = await PromoCodeService.instance.createPromoCode(
        code: code,
        appId: data['appId']?.toString() ?? data['app_id']?.toString(),
        campaign: data['campaign']?.toString(),
        amount: amount,
        maxRedemptions: maxRedemptions,
      );
      return ResponseHelper.success(statusCode: 201, data: promoCode);
    } on PromoCodeServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция updatePromoCode: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> updatePromoCode(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(
          errorMessage: 'Invalid promo code ID format',
        );
      }

      final data = await parseRequestDataHelper(request);
      final amount = data.containsKey('amount')
          ? double.tryParse(data['amount']?.toString() ?? '')
          : null;
      final maxRedemptions = _parseMaxRedemptions(data, allowMissing: true);
      if (data.containsKey('amount') && (amount == null || amount <= 0)) {
        return ResponseHelper.error(
          errorMessage: 'Amount must be a positive number',
        );
      }

      final isActive = data.containsKey('isActive')
          ? data['isActive'] == true || data['isActive']?.toString() == 'true'
          : null;

      final promoCode = await PromoCodeService.instance.updatePromoCode(
        promoCodeId: ObjectId.fromHexString(id),
        appId: data.containsKey('appId')
            ? data['appId']?.toString()
            : data['app_id']?.toString(),
        code: data.containsKey('code') ? data['code']?.toString() : null,
        campaign: data.containsKey('campaign')
            ? data['campaign']?.toString()
            : null,
        amount: amount,
        isActive: isActive,
        maxRedemptions: data.containsKey('maxRedemptions')
            ? maxRedemptions
            : null,
      );
      return ResponseHelper.success(data: promoCode);
    } on PromoCodeServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция deletePromoCode: удаляет данные. Возвращает результат удаления или HTTP-ответ.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> deletePromoCode(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(
          errorMessage: 'Invalid promo code ID format',
        );
      }

      await PromoCodeService.instance.deletePromoCode(
        promoCodeId: ObjectId.fromHexString(id),
      );

      return ResponseHelper.success(data: {'deleted': true, '_id': id});
    } on PromoCodeServiceException catch (error) {
      return ResponseHelper.error(
        errorMessage: error.message,
        statusCode: error.statusCode,
        errorCode: error.errorCode,
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция _parseMaxRedemptions: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает целое число.
  static int? _parseMaxRedemptions(
    Map<String, dynamic> data, {
    required bool allowMissing,
  }) {
    if (!data.containsKey('maxRedemptions')) {
      return allowMissing ? null : 0;
    }

    final rawValue = data['maxRedemptions']?.toString().trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    final parsed = int.tryParse(rawValue);
    if (parsed == null || parsed <= 0) {
      throw const PromoCodeServiceException(
        'Promo code activation limit must be a positive integer',
      );
    }

    return parsed;
  }
}
