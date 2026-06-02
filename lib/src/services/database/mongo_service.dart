// Этот файл: lib/src/services/database/mongo_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:async';

import 'package:mongo_dart/mongo_dart.dart';
import 'package:main_api/src/services/database/collections.dart';

/// MongoService - общий сервис подключения к MongoDB.
/// Он хранит одно подключение к базе, чтобы весь backend пользовался им,
/// а не открывал новое соединение на каждый запрос.
class MongoService {
  // _instance хранит единственный объект MongoService.
  static MongoService? _instance;

  // _db хранит само соединение с MongoDB.
  static Db? _db;
  static String? _connectionString;
  static Timer? _heartbeatTimer;
  static Future<void>? _reconnectFuture;

  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // Приватный конструктор.
  // Снаружи нельзя написать MongoService(), можно только MongoService.instance.
  MongoService._();

  /// Singleton instance.
  /// Простыми словами: всегда возвращаем один и тот же MongoService.
  static MongoService get instance {
    _instance ??= MongoService._();
    return _instance!;
  }

  /// Получить подключённую базу.
  Db get db {
    // Если кто-то пытается работать с базой до connect(),
    // сразу бросаем понятную ошибку.
    if (_db == null) {
      /// Функция Exception: выполняет шаг Exception в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw Exception('Database not connected. Call connect() first.');
    }
    return _db!;
  }

  /// Подключиться к MongoDB.
  Future<void> connect(String connectionString) async {
    _connectionString = connectionString;
    await _open(connectionString);
    _startHeartbeat();
  }

  Future<void> _open(String connectionString) async {
    try {
      final previousDb = _db;

      // Создаём объект подключения по строке из .env.
      final nextDb = await Db.create(connectionString);

      // Открываем сетевое соединение с MongoDB.
      await nextDb.open();
      _db = nextDb;

      // После подключения создаём индексы.
      // Индексы ускоряют поиск и защищают уникальные поля от дублей.
      await _ensureIndexes();

      if (previousDb != null && !identical(previousDb, nextDb)) {
        unawaited(
          previousDb.close().catchError((Object error) {
            print('Error closing stale MongoDB connection: $error');
          }),
        );
      }
      print('Connected to MongoDB successfully');
    } catch (e) {
      print('Error connecting to MongoDB: $e');
      rethrow;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(_checkConnection());
    });
  }

  Future<void> _checkConnection() async {
    final currentDb = _db;
    if (currentDb == null || !currentDb.isConnected) {
      await _reconnect();
      return;
    }

    try {
      await currentDb.pingCommand();
    } catch (e) {
      print('MongoDB heartbeat failed: $e');
      await _reconnect();
    }
  }

  Future<void> _reconnect() {
    final activeReconnect = _reconnectFuture;
    if (activeReconnect != null) {
      return activeReconnect;
    }

    final connectionString = _connectionString;
    if (connectionString == null) {
      return Future.value();
    }

    print('Reconnecting to MongoDB...');
    final reconnect = _open(connectionString).whenComplete(() {
      _reconnectFuture = null;
    });
    _reconnectFuture = reconnect;
    return reconnect;
  }

  /// Закрыть подключение к базе.
  Future<void> close() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _db?.close();
    _db = null;
    print('MongoDB connection closed');
  }

  /// Проверка: открыто ли соединение с MongoDB прямо сейчас.
  bool get isConnected => _db?.isConnected ?? false;

  /// Функция _ensureIndexes: проверяет, что нужное значение есть, и возвращает готовый вариант.
  /// Возвращает ожидание завершения работы, но не возвращает отдельное значение.
  Future<void> _ensureIndexes() async {
    // Email должен быть уникальным: два аккаунта с одним email запрещены.
    await db
        .collection(Collections.users)
        .createIndex(
          keys: {'email': 1},
          unique: true,
          name: 'users_email_unique',
        );

    // Реферальный код пользователя тоже должен быть уникальным.
    // sparse:true позволяет документам без referralCode не конфликтовать.
    await db
        .collection(Collections.users)
        .createIndex(
          keys: {'referralCode': 1},
          unique: true,
          sparse: true,
          name: 'users_referral_code_unique',
        );

    // Индекс для быстрого поиска приглашённых пользователей.
    await db
        .collection(Collections.users)
        .createIndex(
          keys: {'referredByUserId': 1, 'createdAt': -1},
          name: 'users_referred_by_user_id_created_at_idx',
        );

    // Индекс для быстрого поиска транзакций конкретного пользователя.
    await db
        .collection(Collections.transactions)
        .createIndex(keys: {'userId': 1}, name: 'transactions_user_id_idx');

    // Индекс для выборки транзакций по типу и дате.
    await db
        .collection(Collections.transactions)
        .createIndex(
          keys: {'type': 1, 'createdAt': -1},
          name: 'transactions_type_created_at_idx',
        );

    // Индексы для админки персонажей: новые/обновлённые сверху.
    await db
        .collection(Collections.characters)
        .createIndex(
          keys: {'updatedAt': -1},
          name: 'characters_updated_at_idx',
        );

    // Индекс для сортировки заявок желаний по дате.
    await db
        .collection(Collections.subscriptionPlans)
        .createIndex(
          keys: {'updatedAt': -1},
          name: 'subscription_plans_updated_at_idx',
        );

    await db
        .collection(Collections.subscriptionPlans)
        .createIndex(keys: {'name': 1}, name: 'subscription_plans_name_idx');

    // Индекс для сортировки заявок желаний по дате.
    await db
        .collection(Collections.wishRequests)
        .createIndex(
          keys: {'appId': 1, 'createdAt': -1},
          name: 'wish_requests_app_created_at_idx',
        );

    // Индекс для истории заявок конкретного пользователя.
    await db
        .collection(Collections.wishRequests)
        .createIndex(
          keys: {'appId': 1, 'userId': 1, 'createdAt': -1},
          name: 'wish_requests_app_user_id_created_at_idx',
        );

    // Индекс для сортировки желаний по дате обновления.
    await db
        .collection(Collections.wishes)
        .createIndex(
          keys: {'appId': 1, 'updatedAt': -1},
          name: 'wishes_app_updated_at_idx',
        );

    // Индекс для связи желания с заявкой, из которой оно было создано.
    await db
        .collection(Collections.wishes)
        .createIndex(
          keys: {'appId': 1, 'requestId': 1},
          name: 'wishes_app_request_id_idx',
        );

    // Настройки приложения хранятся по уникальному ключу.
    // Например ai_request_price или referral_bonus_amount.
    await db
        .collection(Collections.appSettings)
        .createIndex(
          keys: {'key': 1},
          unique: true,
          name: 'app_settings_key_unique',
        );

    // Код промокода должен быть уникальным.
    await db
        .collection(Collections.promoCodes)
        .createIndex(
          keys: {'code': 1},
          unique: true,
          name: 'promo_codes_code_unique',
        );

    // Индекс для быстрого списка активных промокодов в админке.
    await db
        .collection(Collections.promoCodes)
        .createIndex(
          keys: {'appId': 1, 'isActive': 1, 'updatedAt': -1},
          name: 'promo_codes_app_active_updated_at_idx',
        );

    // Платежи Т-Банка ищем по paymentId и orderId.
    await db
        .collection(Collections.tbankPayments)
        .createIndex(
          keys: {'paymentId': 1},
          unique: true,
          name: 'tbank_payments_payment_id_unique',
        );

    await db
        .collection(Collections.tbankPayments)
        .createIndex(
          keys: {'orderId': 1},
          unique: true,
          name: 'tbank_payments_order_id_unique',
        );

    // Пакеты запросов показываем от меньшего количества запросов к большему.
    await db
        .collection(Collections.requestPackages)
        .createIndex(
          keys: {'scope': 1, 'appId': 1, 'requestCount': 1, 'updatedAt': -1},
          name: 'request_packages_scope_app_count_updated_idx',
        );
  }
}
