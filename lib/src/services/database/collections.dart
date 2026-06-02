// Этот файл: lib/src/services/database/collections.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

/// Database collection names
class Collections {
  static const String apps = 'apps';
  static const String users = 'users';
  static const String transactions = 'transactions';
  static const String characters = 'characters';
  static const String appSettings = 'app_settings';
  static const String wishRequests = 'wishes_requests';
  static const String wishes = 'wishes';
  static const String promoCodes = 'promo_codes';
  static const String tbankPayments = 'tbank_payments';
  static const String requestPackages = 'request_packages';
  static const String subscriptionPlans = 'subscription_plans';
}
