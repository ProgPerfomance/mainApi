// Этот файл: lib/src/services/app_config.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:io';

/// Класс AppConfig: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class AppConfig {
  /// Конструктор AppConfig._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  AppConfig._();

  static final Map<String, String> _env = {...Platform.environment};

  static bool _isLoaded = false;

  /// Функция loadEnv: загружает данные и возвращает результат загрузки.
  /// Ничего не возвращает, только выполняет действие.
  static void loadEnv([Iterable<String> filenames = const ['.env']]) {
    if (_isLoaded) {
      return;
    }

    for (final filename in filenames) {
      final file = File(filename);
      if (!file.existsSync()) {
        continue;
      }

      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }

        final normalizedLine = trimmed.startsWith('export ')
            ? trimmed.substring('export '.length).trim()
            : trimmed;

        final separatorIndex = normalizedLine.indexOf('=');
        if (separatorIndex <= 0) {
          continue;
        }

        final key = normalizedLine.substring(0, separatorIndex).trim();
        final value = normalizedLine.substring(separatorIndex + 1).trim();
        if (key.isNotEmpty && !_env.containsKey(key)) {
          _env[key] = _stripQuotes(value);
        }
      }
    }

    _isLoaded = true;
  }

  /// Функция get: получает нужное значение и возвращает его вызывающему коду.
  /// Возвращает текст или пустое значение, если текста нет.
  static String? get(String key) => _env[key];

  /// Геттер mongoUri: читает значение mongoUri и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get mongoUri =>
      get('MONGO_URI') ?? 'mongodb://localhost:27017/main_api';

  /// Геттер port: читает значение port и возвращает его без отдельного изменения данных.
  /// Возвращает целое число.
  static int get port {
    final rawPort = get('PORT');
    return int.tryParse(rawPort ?? '') ?? 5195;
  }

  static int get accountBillingPort {
    final rawPort = get('ACCOUNT_BILLING_PORT');
    return int.tryParse(rawPort ?? '') ?? 5184;
  }

  static String get appId {
    final value = get('APP_ID')?.trim();
    if (value == null || value.isEmpty) {
      return 'psychology';
    }
    return value;
  }

  static String? get accountBillingServiceUrl {
    final value = get('ACCOUNT_BILLING_SERVICE_URL')?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  /// Геттер deepSeekApiKey: читает значение deepSeekApiKey и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get deepSeekApiKey {
    final value = get('DEEPSEEK_API_KEY');
    if (value == null || value.isEmpty) {
      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError('DEEPSEEK_API_KEY is not configured');
    }
    return value;
  }

  /// Геттер uploadsDir: читает значение uploadsDir и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get uploadsDir => get('UPLOADS_DIR') ?? 'uploads';

  /// Геттер adminUsername: читает логин менеджера для входа в админку.
  /// Возвращает текст, который вводится на визуальном экране авторизации.
  static String get adminUsername {
    final value = get('ADMIN_USERNAME')?.trim();
    if (value == null || value.isEmpty) {
      return 'admin';
    }
    return value;
  }

  /// Геттер adminPassword: читает пароль менеджера для входа в админку.
  /// Возвращает текст или пустое значение, если пароль ещё не настроили.
  static String? get adminPassword {
    final value = get('ADMIN_PASSWORD');
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// Геттер adminSessionSecret: читает секрет для подписи входа в админку.
  /// Возвращает длинный секрет, чтобы cookie нельзя было подделать.
  static String get adminSessionSecret {
    final value = get('ADMIN_SESSION_SECRET');
    if (value != null && value.length >= 32) {
      return value;
    }
    return jwtSecret;
  }

  /// Геттер adminCookieSecure: решает, требовать ли HTTPS для cookie админки.
  /// Возвращает да/нет для продакшен-настройки.
  static bool get adminCookieSecure {
    final value = get('ADMIN_COOKIE_SECURE')?.toLowerCase().trim();
    return value == 'true' || value == '1' || value == 'yes';
  }

  static String? get adminApiToken {
    final value = get('ADMIN_API_TOKEN')?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String get jwtSecret {
    final value = get('JWT_SECRET');
    if (value == null || value.length < 32) {
      throw StateError('JWT_SECRET must contain at least 32 characters');
    }
    return value;
  }

  static String? get smtpHost => _nonEmpty('SMTP_HOST');

  static int get smtpPort {
    final value = int.tryParse(get('SMTP_PORT') ?? '');
    return value ?? 465;
  }

  static String? get smtpUsername => _nonEmpty('SMTP_USERNAME');

  static String? get smtpPassword => _nonEmpty('SMTP_PASSWORD');

  static bool get smtpSsl {
    final value = get('SMTP_SSL')?.toLowerCase().trim();
    return value == null || value == 'true' || value == '1' || value == 'yes';
  }

  static bool get smtpAllowInsecure {
    final value = get('SMTP_ALLOW_INSECURE')?.toLowerCase().trim();
    return value == 'true' || value == '1' || value == 'yes';
  }

  static String get smtpFromEmail =>
      _nonEmpty('SMTP_FROM_EMAIL') ?? smtpUsername ?? 'info@niami.ru';

  static String get smtpFromName => _nonEmpty('SMTP_FROM_NAME') ?? 'NIAMI';

  static String get passwordResetSecret {
    final value = _nonEmpty('PASSWORD_RESET_SECRET');
    if (value != null && value.length >= 32) {
      return value;
    }
    return jwtSecret;
  }

  static int get passwordResetCodeTtlMinutes {
    final value = int.tryParse(get('PASSWORD_RESET_CODE_TTL_MINUTES') ?? '');
    if (value == null || value <= 0) {
      return 15;
    }
    return value;
  }

  static int get passwordResetMinIntervalSeconds {
    final value = int.tryParse(
      get('PASSWORD_RESET_MIN_INTERVAL_SECONDS') ?? '',
    );
    if (value == null || value <= 0) {
      return 60;
    }
    return value;
  }

  /// Геттер tBankApiBaseUrl: читает значение tBankApiBaseUrl и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get tBankApiBaseUrl =>
      get('TBANK_API_BASE_URL') ?? 'https://securepay.tinkoff.ru/v2';

  /// Геттер tBankTerminalKey: читает значение tBankTerminalKey и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get tBankTerminalKey {
    final value = get('TBANK_TERMINAL_KEY');
    if (value == null || value.isEmpty) {
      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError('TBANK_TERMINAL_KEY is not configured');
    }
    return value;
  }

  /// Геттер tBankPassword: читает значение tBankPassword и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get tBankPassword {
    final value = get('TBANK_PASSWORD');
    if (value == null || value.isEmpty) {
      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError('TBANK_PASSWORD is not configured');
    }
    return value;
  }

  static String tBankTerminalKeyForApp(String? appId) {
    final appKey = _appScopedEnvKey(
      prefix: 'TBANK',
      appId: appId,
      suffix: 'TERMINAL_KEY',
    );
    return (appKey == null ? null : _nonEmpty(appKey)) ?? tBankTerminalKey;
  }

  static String tBankPasswordForApp(String? appId) {
    final appKey = _appScopedEnvKey(
      prefix: 'TBANK',
      appId: appId,
      suffix: 'PASSWORD',
    );
    return (appKey == null ? null : _nonEmpty(appKey)) ?? tBankPassword;
  }

  /// Геттер tBankPaymentScheme: читает значение tBankPaymentScheme и возвращает его без отдельного изменения данных.
  /// Возвращает текст.
  static String get tBankPaymentScheme =>
      get('TBANK_PAYMENT_SCHEME') ?? 'kirillapppay';

  // Это начало адреса, куда Т-Банк отправит человека после оплаты.
  // Для локальной проверки можно сразу вести в приложение:
  // kirillapppay://payment
  // Для продакшена лучше вести на сайт:
  // https://niami.ru/payment
  // Тогда человек сначала увидит понятную страницу "успешно/неуспешно",
  // а уже оттуда сможет вернуться в приложение кнопкой.
  static String get tBankPaymentReturnBaseUrl =>
      get('TBANK_PAYMENT_RETURN_BASE_URL') ?? '$tBankPaymentScheme://payment';

  static String get tBankNotificationUrl =>
      _nonEmpty('TBANK_NOTIFICATION_URL') ??
      'https://admin.niami.ru/api/v1/billing/tbank/notification';

  static bool get recurringSubscriptionJobEnabled {
    final value = get(
      'RECURRING_SUBSCRIPTION_JOB_ENABLED',
    )?.toLowerCase().trim();
    return value != 'false' && value != '0' && value != 'no';
  }

  /// Геттер tBankReceiptTaxation: читает систему налогообложения для чека Т-Банка.
  /// Возвращает текст, который Т-Банк кладёт в чек для налоговой.
  static String get tBankReceiptTaxation =>
      _nonEmpty('TBANK_RECEIPT_TAXATION') ?? 'usn_income';

  /// Геттер tBankReceiptTax: читает ставку НДС для позиции в чеке.
  /// Возвращает текст; по умолчанию чек идёт без НДС.
  static String get tBankReceiptTax => _nonEmpty('TBANK_RECEIPT_TAX') ?? 'none';

  /// Геттер tBankReceiptPaymentMethod: читает способ расчёта для чека.
  /// Возвращает текст, который объясняет кассе, что оплата списана полностью.
  static String get tBankReceiptPaymentMethod =>
      _nonEmpty('TBANK_RECEIPT_PAYMENT_METHOD') ?? 'full_payment';

  /// Геттер tBankReceiptPaymentObject: читает тип того, что продаём.
  /// Возвращает текст; для приложения это услуга.
  static String get tBankReceiptPaymentObject =>
      _nonEmpty('TBANK_RECEIPT_PAYMENT_OBJECT') ?? 'service';

  /// Геттер tBankReceiptItemName: читает название строки в чеке.
  /// Возвращает короткий понятный текст для покупателя.
  static String get tBankReceiptItemName =>
      _nonEmpty('TBANK_RECEIPT_ITEM_NAME') ?? 'Пополнение баланса NIAMI';

  static String? _nonEmpty(String key) {
    final value = get(key)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String? _appScopedEnvKey({
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

  /// Функция _stripQuotes: выполняет шаг _stripQuotes в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static String _stripQuotes(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }
}
