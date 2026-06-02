// Этот файл: lib/src/services/tbank/tbank_payment_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/app_registry/app_registry_service.dart';

// Ошибка платежного сервиса.
// statusCode нужен, чтобы controller мог вернуть Flutter понятный HTTP-код.
class TBankPaymentException implements Exception {
  const TBankPaymentException(this.message, {this.statusCode = 400});

  final String message;
  final int statusCode;

  /// Функция toString: выполняет шаг toString в этой части программы. Возвращает текст.
  /// Возвращает текст.
  @override
  String toString() => message;
}

// То, что backend получает от Т-Банка после создания платежа.
// Главное поле для Flutter здесь - paymentUrl: именно эту ссылку открываем
// в мобильном приложении как платежную форму.
class TBankInitPaymentResult {
  const TBankInitPaymentResult({
    required this.paymentId,
    required this.paymentUrl,
    required this.orderId,
    required this.amountKopecks,
    required this.status,
  });

  final String paymentId;
  final String paymentUrl;
  final String orderId;
  final int amountKopecks;
  final String? status;
}

// Текущий статус платежа в Т-Банке.
// По этому статусу backend решает, можно ли начислять деньги на баланс.
class TBankPaymentState {
  const TBankPaymentState({
    required this.paymentId,
    required this.orderId,
    required this.amountKopecks,
    required this.status,
    required this.success,
    this.raw,
  });

  final String paymentId;
  final String orderId;
  final int amountKopecks;
  final String status;
  final bool success;
  final Map<String, dynamic>? raw;

  /// Геттер isConfirmed: читает значение isConfirmed и возвращает его без отдельного изменения данных.
  /// Возвращает да/нет.
  bool get isConfirmed => status == 'CONFIRMED';
}

class TBankRecurringChargeResult {
  const TBankRecurringChargeResult({
    required this.paymentId,
    required this.orderId,
    required this.amountKopecks,
    required this.initStatus,
    required this.chargeStatus,
    required this.success,
    required this.initRaw,
    required this.chargeRaw,
  });

  final String paymentId;
  final String orderId;
  final int amountKopecks;
  final String? initStatus;
  final String? chargeStatus;
  final bool success;
  final Map<String, dynamic> initRaw;
  final Map<String, dynamic> chargeRaw;

  bool get isConfirmed => chargeStatus == 'CONFIRMED';
}

// Сервис для общения с API интернет-эквайринга Т-Банка.
// Flutter сюда напрямую не ходит: пароль терминала хранится только на backend.
class TBankPaymentService {
  /// Конструктор TBankPaymentService: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  TBankPaymentService({
    Dio? dio,
    String? apiBaseUrl,
    String? terminalKey,
    String? password,
    String? paymentReturnBaseUrl,
  }) : _dio =
           dio ??
           /// Конструктор Dio: создаёт новый объект этого класса.
           /// Возвращает готовый объект, с которым дальше работает приложение.
           Dio(BaseOptions(baseUrl: apiBaseUrl ?? AppConfig.tBankApiBaseUrl)),
       _terminalKey = terminalKey ?? AppConfig.tBankTerminalKey,
       _password = password ?? AppConfig.tBankPassword,
       _paymentReturnBaseUrl =
           paymentReturnBaseUrl ?? AppConfig.tBankPaymentReturnBaseUrl;

  static Future<TBankPaymentService> forApp(
    String? appId, {
    Dio? dio,
    String? apiBaseUrl,
    String? paymentReturnBaseUrl,
  }) async {
    final credentials = await AppRegistryService.instance
        .resolveTBankCredentials(appId);
    return TBankPaymentService(
      dio: dio,
      apiBaseUrl: apiBaseUrl,
      terminalKey: credentials['terminalKey'],
      password: credentials['password'],
      paymentReturnBaseUrl: paymentReturnBaseUrl,
    );
  }

  final Dio _dio;
  final String _terminalKey;
  final String _password;
  // Базовый адрес возврата после оплаты.
  // Из него ниже собираются два адреса:
  // success - если пользователь оплатил,
  // fail - если оплата не завершилась.
  final String _paymentReturnBaseUrl;

  /// Функция initPayment: выполняет шаг initPayment в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<TBankInitPaymentResult> initPayment({
    required String orderId,
    required int amountKopecks,
    required String description,
    required String userId,
    required String userEmail,
    String? userPhone,
    String language = 'ru',
    String? deviceOs,
    String? deviceBrowser,
    bool recurrent = false,
    String? customerKey,
    String operationInitiatorType = '0',
    String? notificationUrl,
  }) async {
    final normalizedCustomerKey = _emptyToNull(customerKey);
    if (recurrent && normalizedCustomerKey == null) {
      throw const TBankPaymentException(
        'Customer key is required for recurrent payment',
      );
    }

    // Создаем одностадийный платеж: если пользователь оплатил,
    // Т-Банк сразу списывает деньги и переводит платеж в CONFIRMED.
    final payload = <String, dynamic>{
      'TerminalKey': _terminalKey,
      'Amount': amountKopecks,
      'OrderId': orderId,
      'Description': description,
      'PayType': 'O',
      'Language': _normalizeLanguage(language),
      // СБП не требует отдельного endpoint-а в приложении.
      // Т-Банк показывает СБП внутри этой же универсальной платежной формы,
      // если способ оплаты включён в личном кабинете интернет-эквайринга.
      // Т-Банк после формы оплаты откроет один из этих адресов.
      // В продакшене это страницы сайта niami.ru, где человеку объясняем,
      // что произошло, и даём кнопку вернуться в мобильное приложение.
      'SuccessURL': '$_paymentReturnBaseUrl/success/$orderId',
      'FailURL': '$_paymentReturnBaseUrl/fail/$orderId',
      'NotificationURL': notificationUrl ?? AppConfig.tBankNotificationUrl,
      'CustomerKey': ?normalizedCustomerKey,
      if (recurrent) 'Recurrent': 'Y',
      // Боевой терминал подключён к онлайн-кассе, поэтому Т-Банк требует чек
      // уже на этапе создания платежа. Без этого банк отвечает:
      // "Неверные параметры" и "expected.receipt".
      'Receipt': _buildReceipt(
        amountKopecks: amountKopecks,
        userEmail: userEmail,
        userPhone: userPhone,
      ),
      'DATA': {
        // DATA не участвует в подписи токена, но уходит в Т-Банк как
        // дополнительные данные заказа. Это помогает потом отлаживать платеж.
        'userId': userId,
        'OperationInitiatorType': operationInitiatorType,
        'Device': 'Mobile',
        'DeviceWebView': true,
        // Эти поля помогают платежной форме корректно показать доступные
        // мобильные способы оплаты: карты, СБП, T-Pay, Mir Pay и Долями.
        'DeviceOs': ?deviceOs,
        'DeviceBrowser': ?deviceBrowser,
        'TinkoffPayWeb': true,
      },
    };
    // Token доказывает Т-Банку, что запрос отправил backend,
    // который знает пароль терминала.
    payload['Token'] = makeToken(payload, _password);

    final response = await _post('/Init', payload);
    final paymentId = response['PaymentId']?.toString();
    final paymentUrl = response['PaymentURL']?.toString();

    if (paymentId == null || paymentId.isEmpty) {
      throw const TBankPaymentException(
        'T-Bank did not return PaymentId',
        statusCode: 502,
      );
    }
    if (paymentUrl == null || paymentUrl.isEmpty) {
      throw const TBankPaymentException(
        'T-Bank did not return PaymentURL',
        statusCode: 502,
      );
    }

    /// Функция TBankInitPaymentResult: выполняет шаг TBankInitPaymentResult в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return TBankInitPaymentResult(
      paymentId: paymentId,
      paymentUrl: paymentUrl,
      orderId: orderId,
      amountKopecks: amountKopecks,
      status: response['Status']?.toString(),
    );
  }

  Future<TBankRecurringChargeResult> chargeRecurringPayment({
    required String orderId,
    required int amountKopecks,
    required String description,
    required String userId,
    required String rebillId,
    required String userEmail,
    String? userPhone,
  }) async {
    final initPayload = <String, dynamic>{
      'TerminalKey': _terminalKey,
      'Amount': amountKopecks,
      'OrderId': orderId,
      'Description': description,
      'PayType': 'O',
      'CustomerKey': userId,
      'NotificationURL': AppConfig.tBankNotificationUrl,
      'Receipt': _buildReceipt(
        amountKopecks: amountKopecks,
        userEmail: userEmail,
        userPhone: userPhone,
      ),
      'DATA': {
        'userId': userId,
        'OperationInitiatorType': 'R',
        'Device': 'Mobile',
      },
    };
    initPayload['Token'] = makeToken(initPayload, _password);

    final initResponse = await _post('/Init', initPayload);
    final paymentId = initResponse['PaymentId']?.toString();
    if (paymentId == null || paymentId.isEmpty) {
      throw const TBankPaymentException(
        'T-Bank did not return PaymentId',
        statusCode: 502,
      );
    }

    final chargePayload = <String, dynamic>{
      'TerminalKey': _terminalKey,
      'PaymentId': paymentId,
      'RebillId': rebillId,
    };
    chargePayload['Token'] = makeToken(chargePayload, _password);

    final chargeResponse = await _post('/Charge', chargePayload);
    return TBankRecurringChargeResult(
      paymentId: paymentId,
      orderId: initResponse['OrderId']?.toString() ?? orderId,
      amountKopecks: (initResponse['Amount'] as num?)?.toInt() ?? amountKopecks,
      initStatus: initResponse['Status']?.toString(),
      chargeStatus: chargeResponse['Status']?.toString(),
      success: chargeResponse['Success'] == true,
      initRaw: initResponse,
      chargeRaw: chargeResponse,
    );
  }

  /// Функция getState: получает нужное значение и возвращает его вызывающему коду.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<TBankPaymentState> getState({required String paymentId}) async {
    // После возврата пользователя из формы оплаты не доверяем deeplink-у.
    // Отдельно спрашиваем Т-Банк, какой реальный статус у платежа.
    final payload = <String, dynamic>{
      'TerminalKey': _terminalKey,
      'PaymentId': paymentId,
    };
    payload['Token'] = makeToken(payload, _password);

    final response = await _post('/GetState', payload);

    /// Функция TBankPaymentState: выполняет шаг TBankPaymentState в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return TBankPaymentState(
      paymentId: response['PaymentId']?.toString() ?? paymentId,
      orderId: response['OrderId']?.toString() ?? '',
      amountKopecks: (response['Amount'] as num?)?.toInt() ?? 0,
      status: response['Status']?.toString() ?? '',
      success: response['Success'] == true,
      raw: response,
    );
  }

  /// Функция _post: выполняет шаг _post в этой части программы. Возвращает текст.
  /// Возвращает текст.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      // Все методы Т-Банка здесь вызываются POST-запросом с JSON-телом.
      final response = await _dio.post(path, data: payload);
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['Success'] != true) {
        final message =
            data['Message']?.toString() ??
            data['Details']?.toString() ??
            'T-Bank payment request failed';
        _logTBankFailure(path: path, payload: payload, response: data);

        /// Функция TBankPaymentException: выполняет шаг TBankPaymentException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw TBankPaymentException(message, statusCode: 502);
      }
      return data;
    } on DioException catch (error) {
      final responseData = error.response?.data;
      if (responseData is Map) {
        final data = Map<String, dynamic>.from(responseData);
        final message =
            data['Message']?.toString() ??
            data['Details']?.toString() ??
            error.message ??
            'T-Bank payment request failed';
        _logTBankFailure(path: path, payload: payload, response: data);

        /// Функция TBankPaymentException: выполняет шаг TBankPaymentException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
        /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
        throw TBankPaymentException(message, statusCode: 502);
      }

      /// Функция TBankPaymentException: выполняет шаг TBankPaymentException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw TBankPaymentException(
        error.message ?? 'T-Bank payment request failed',
        statusCode: 502,
      );
    }
  }

  /// Функция makeToken: выполняет шаг makeToken в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static String makeToken(Map<String, dynamic> payload, String password) {
    // Правило Т-Банка: для подписи берем только поля верхнего уровня.
    // Вложенные объекты вроде DATA или Receipt не добавляем в строку подписи.
    final rootValues = <String, String>{};
    for (final entry in payload.entries) {
      final value = entry.value;
      if (entry.key == 'Token' || value is Map || value is Iterable) {
        continue;
      }
      rootValues[entry.key] = value.toString();
    }
    rootValues['Password'] = password;

    // Ключи сортируются по алфавиту, потом склеиваются только значения.
    // Итоговая строка хешируется SHA-256 в UTF-8.
    final sortedKeys = rootValues.keys.toList()..sort();
    final rawToken = sortedKeys.map((key) => rootValues[key]).join();
    return sha256.convert(utf8.encode(rawToken)).toString();
  }

  static bool isValidNotificationToken(
    Map<String, dynamic> payload,
    String password,
  ) {
    final token = payload['Token']?.toString();
    if (token == null || token.isEmpty) {
      return false;
    }
    return makeToken(payload, password) == token;
  }

  /// Функция _buildReceipt: собирает чек для Т-Банка.
  /// Возвращает набор данных, из которого Т-Банк создаст кассовый чек.
  static Map<String, dynamic> _buildReceipt({
    required int amountKopecks,
    required String userEmail,
    String? userPhone,
  }) {
    final email = _emptyToNull(userEmail);
    final phone = _normalizePhone(userPhone);
    if (email == null && phone == null) {
      throw const TBankPaymentException(
        'User email or phone is required for receipt',
      );
    }

    return {
      'Email': ?email,
      'Phone': ?phone,
      'Taxation': AppConfig.tBankReceiptTaxation,
      'Items': [
        {
          'Name': AppConfig.tBankReceiptItemName,
          'Price': amountKopecks,
          'Quantity': 1,
          'Amount': amountKopecks,
          'Tax': AppConfig.tBankReceiptTax,
          'PaymentMethod': AppConfig.tBankReceiptPaymentMethod,
          'PaymentObject': AppConfig.tBankReceiptPaymentObject,
        },
      ],
    };
  }

  /// Функция _emptyToNull: убирает пустой текст.
  /// Возвращает текст или null, если там ничего полезного нет.
  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Функция _normalizePhone: готовит телефон для чека.
  /// Возвращает телефон в формате +79991234567 или null, если телефона нет.
  static String? _normalizePhone(String? value) {
    final trimmed = _emptyToNull(value);
    if (trimmed == null) {
      return null;
    }
    if (trimmed.startsWith('+')) {
      return trimmed;
    }
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return null;
    }
    return '+$digitsOnly';
  }

  /// Функция _logTBankFailure: пишет в лог ответ Т-Банка без пароля и токена.
  /// Ничего не возвращает, только помогает понять причину ошибки на сервере.
  static void _logTBankFailure({
    required String path,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> response,
  }) {
    final safePayload = Map<String, dynamic>.from(payload)..remove('Token');
    developer.log(
      'request=$path payload=$safePayload response=$response',
      name: 'TBankPaymentService',
    );
  }

  /// Функция _normalizeLanguage: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает текст.
  static String _normalizeLanguage(String language) {
    // Платежная форма Т-Банка поддерживает только русский и английский.
    // Если приложение работает на другом языке, безопасно открываем русский.
    return language == 'en' ? 'en' : 'ru';
  }
}
