// Этот файл: lib/src/services/billing/billing_service.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/request_package.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Класс BillingServiceException: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class BillingServiceException implements Exception {
  final String message;
  final int statusCode;
  final String? errorCode;
  final Map<String, dynamic>? details;

  const BillingServiceException(
    this.message, {
    this.statusCode = 400,
    this.errorCode,
    this.details,
  });

  /// Функция toString: выполняет шаг toString в этой части программы. Возвращает текст.
  /// Возвращает текст.
  @override
  String toString() => message;
}

// Это результат "предварительной проверки" AI-запроса.
//
// Здесь мы ещё никого не списали.
// Мы только:
// - нашли пользователя
// - посмотрели текущую цену AI-запроса
// - убедились, что денег хватает
class AiRequestChargePreparation {
  final User user;
  final double requestPrice;
  final bool willUseRequestBalance;
  final bool hasActiveSubscription;
  final DateTime sessionStartedAt;
  final int sessionRequestIndex;

  const AiRequestChargePreparation({
    required this.user,
    required this.requestPrice,
    required this.willUseRequestBalance,
    required this.hasActiveSubscription,
    required this.sessionStartedAt,
    required this.sessionRequestIndex,
  });
}

// Это уже результат фактического успешного списания.
//
// Используется после того, как AI действительно ответил.
class AiRequestChargeResult {
  final double chargedAmount;
  final double newBalance;
  final int newRequestBalance;
  final String paymentSource;

  const AiRequestChargeResult({
    required this.chargedAmount,
    required this.newBalance,
    required this.newRequestBalance,
    required this.paymentSource,
  });

  /// Функция toJson: превращает Dart-объект в JSON, который можно отправить или сохранить.
  /// Возвращает текст.
  Map<String, dynamic> toJson() {
    return {
      'chargedAmount': chargedAmount,
      'newBalance': newBalance,
      'newRequestBalance': newRequestBalance,
      'paymentSource': paymentSource,
    };
  }
}

// Результат покупки пакета запросов.
// Его получает приложение после оплаты с баланса или после подтверждения оплаты картой.
class RequestPackagePurchaseResult {
  const RequestPackagePurchaseResult({
    required this.package,
    required this.transaction,
    required this.newBalance,
    required this.newRequestBalance,
  });

  final RequestPackage package;
  final Transaction transaction;
  final double newBalance;
  final int newRequestBalance;

  Map<String, dynamic> toJson() {
    return {
      'package': package.toPublicJson(),
      'transaction': transaction.toPublicJson(),
      'newBalance': newBalance,
      'newRequestBalance': newRequestBalance,
    };
  }
}

class SubscriptionSettings {
  const SubscriptionSettings({
    required this.name,
    required this.price,
    required this.appId,
    required this.scope,
    required this.updatedAt,
  });

  final String name;
  final double price;
  final String appId;
  final String scope;
  final DateTime updatedAt;

  Map<String, dynamic> toPublicJson() {
    return {
      'name': name,
      'price': price,
      'appId': appId,
      'app_id': appId,
      'scope': scope,
      'periodDays': BillingService.subscriptionPeriodDays,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class SubscriptionPurchaseResult {
  const SubscriptionPurchaseResult({
    required this.settings,
    required this.transaction,
    required this.subscriptionExpiresAt,
    required this.newBalance,
  });

  final SubscriptionSettings settings;
  final Transaction transaction;
  final DateTime subscriptionExpiresAt;
  final double newBalance;

  Map<String, dynamic> toJson() {
    return {
      'subscription': settings.toPublicJson(),
      'transaction': transaction.toPublicJson(),
      'subscriptionExpiresAt': subscriptionExpiresAt.toIso8601String(),
      'newBalance': newBalance,
    };
  }
}

/// Класс BillingService: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class BillingService {
  /// Конструктор BillingService._: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  BillingService._();

  static final BillingService instance = BillingService._();

  static const String aiRequestChargeDescription = 'AI request charge';
  static const String aiRequestPackageChargeDescription =
      'AI request package charge';
  static const String requestPackagePurchaseDescription =
      'Request package purchase';
  static const String subscriptionPurchaseDescription = 'Subscription purchase';
  static const int defaultAdminHistoryLimit = 100;
  static const int subscriptionPeriodDays = 30;
  static const String insufficientBalanceErrorCode = 'INSUFFICIENT_BALANCE';
  static const String _subscriptionSettingsKey = 'monthly_subscription';
  static const String subscriptionScopeApp = User.subscriptionScopeApp;
  static const String subscriptionScopeGlobal = User.subscriptionScopeGlobal;
  static const String globalAppId = User.globalAppId;
  static const String defaultSubscriptionName = 'Плюс';
  static const double defaultSubscriptionPrice = 999.0;
  static const double startingBalanceAmount = 300.0;
  static const int startingAppRequestCount = 1;
  static const String startingAppRequestDescription =
      'Starting app request bonus';
  static const double referralBonusAmount = 300.0;
  static const double topUpBonusPercent = 0.10;
  static const int aiSessionDurationHours = 4;
  static const double firstAiRequestPrice = 299.0;
  static const double secondAiRequestPrice = 149.0;
  static const double nextAiRequestPrice = 99.0;

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

  DbCollection get _settingsCollection =>
      _db.collection(Collections.appSettings);

  DbCollection get _requestPackagesCollection =>
      _db.collection(Collections.requestPackages);

  Future<SubscriptionSettings> getSubscriptionSettings({
    String? appId,
    String scope = subscriptionScopeApp,
  }) async {
    final normalizedScope = normalizeSubscriptionScope(scope);
    final normalizedAppId = normalizedScope == subscriptionScopeGlobal
        ? globalAppId
        : normalizeAppId(appId);
    final settingsKey = _subscriptionSettingsKeyFor(
      appId: normalizedAppId,
      scope: normalizedScope,
    );
    var rawSettings = await _settingsCollection.findOne(
      where.eq('key', settingsKey),
    );
    if (rawSettings == null &&
        normalizedScope == subscriptionScopeApp &&
        normalizedAppId == normalizeAppId(AppConfig.appId)) {
      rawSettings = await _settingsCollection.findOne(
        where.eq('key', _subscriptionSettingsKey),
      );
    }
    if (rawSettings == null) {
      return setSubscriptionSettings(
        name: defaultSubscriptionName,
        price: defaultSubscriptionPrice,
        appId: normalizedAppId,
        scope: normalizedScope,
      );
    }

    final name = rawSettings['name']?.toString().trim() ?? '';
    final price = (rawSettings['price'] as num?)?.toDouble();
    return SubscriptionSettings(
      name: name.isEmpty ? defaultSubscriptionName : name,
      price: price == null || price <= 0 ? defaultSubscriptionPrice : price,
      appId: normalizeAppId(
        rawSettings['appId']?.toString() ??
            rawSettings['app_id']?.toString() ??
            normalizedAppId,
      ),
      scope: normalizeSubscriptionScope(
        rawSettings['scope']?.toString() ?? normalizedScope,
      ),
      updatedAt: _parseDateTime(rawSettings['updatedAt']),
    );
  }

  Future<SubscriptionSettings> setSubscriptionSettings({
    required String name,
    required double price,
    String? appId,
    String scope = subscriptionScopeApp,
  }) async {
    // Единственная месячная подписка управляется из админки:
    // менеджер задаёт название тарифа и цену, которую увидит приложение.
    final normalizedName = _normalizeSubscriptionName(name);
    final normalizedPrice = _normalizePackagePrice(price);
    final normalizedScope = normalizeSubscriptionScope(scope);
    final normalizedAppId = normalizedScope == subscriptionScopeGlobal
        ? globalAppId
        : normalizeAppId(appId);
    final settingsKey = _subscriptionSettingsKeyFor(
      appId: normalizedAppId,
      scope: normalizedScope,
    );
    final now = DateTime.now().toUtc();
    final result = await _settingsCollection.updateOne(
      where.eq('key', settingsKey),
      modify
          .set('key', settingsKey)
          .set('name', normalizedName)
          .set('price', normalizedPrice)
          .set('appId', normalizedAppId)
          .set('app_id', normalizedAppId)
          .set('scope', normalizedScope)
          .set('periodDays', subscriptionPeriodDays)
          .set('updatedAt', now.toIso8601String()),
      upsert: true,
    );
    if (!result.isSuccess) {
      throw const BillingServiceException(
        'Failed to save subscription settings',
        statusCode: 500,
      );
    }

    return SubscriptionSettings(
      name: normalizedName,
      price: normalizedPrice,
      appId: normalizedAppId,
      scope: normalizedScope,
      updatedAt: now,
    );
  }

  Future<List<RequestPackage>> listRequestPackages({
    bool activeOnly = false,
    String? appId,
    String? scope,
  }) async {
    // Пакеты - это витрина товаров для запросов.
    // В приложении показываем только активные, в админке можно видеть все.
    final rawPackages = await _requestPackagesCollection.find().toList();
    final normalizedAppId = appId == null ? null : normalizeAppId(appId);
    final normalizedScope = scope == null
        ? null
        : normalizeSubscriptionScope(scope);
    final packages = rawPackages.map(RequestPackage.fromJson).toList()
      ..removeWhere((item) {
        if (activeOnly && !item.isActive) {
          return true;
        }
        if (normalizedScope != null && item.scope != normalizedScope) {
          return true;
        }
        if (normalizedAppId == null) {
          return false;
        }
        if (item.scope == subscriptionScopeGlobal) {
          return false;
        }
        return !item.appIds.contains(normalizedAppId);
      })
      ..sort((left, right) => left.requestCount.compareTo(right.requestCount));
    return packages;
  }

  Future<RequestPackage> createRequestPackage({
    required int requestCount,
    required double price,
    String? appId,
    List<String>? appIds,
    String scope = subscriptionScopeApp,
    bool isActive = true,
  }) async {
    // Админ создаёт товар: сколько запросов покупатель получит и сколько это стоит.
    final normalizedScope = normalizeSubscriptionScope(scope);
    final normalizedAppIds = normalizedScope == subscriptionScopeGlobal
        ? const <String>[globalAppId]
        : _normalizeRequestPackageAppIds(appIds, appId);
    final package = RequestPackage(
      requestCount: _normalizeRequestCount(requestCount),
      price: _normalizePackagePrice(price),
      appId: normalizedAppIds.first,
      appIds: normalizedAppIds,
      scope: normalizedScope,
      isActive: isActive,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final result = await _requestPackagesCollection.insertOne(package.toJson());
    if (!result.isSuccess) {
      throw const BillingServiceException(
        'Failed to create request package',
        statusCode: 500,
      );
    }

    final rawPackage = await _requestPackagesCollection.findOne(
      where.eq('_id', result.id),
    );
    return RequestPackage.fromJson(rawPackage ?? package.toJson());
  }

  Future<RequestPackage> updateRequestPackage({
    required ObjectId packageId,
    int? requestCount,
    double? price,
    String? appId,
    List<String>? appIds,
    String? scope,
    bool? isActive,
  }) async {
    // Админ может менять цену, размер пакета и доступность товара.
    final existing = await findRequestPackage(packageId, activeOnly: false);
    final now = DateTime.now().toUtc();
    final nextRequestCount = requestCount == null
        ? existing.requestCount
        : _normalizeRequestCount(requestCount);
    final nextPrice = price == null
        ? existing.price
        : _normalizePackagePrice(price);
    final nextScope = scope == null
        ? existing.scope
        : normalizeSubscriptionScope(scope);
    final nextAppIds = nextScope == subscriptionScopeGlobal
        ? const <String>[globalAppId]
        : (appIds != null || appId != null)
        ? _normalizeRequestPackageAppIds(appIds, appId ?? existing.appId)
        : existing.appIds;
    final nextAppId = nextAppIds.first;

    final result = await _requestPackagesCollection.updateOne(
      where.eq('_id', packageId),
      modify
          .set('requestCount', nextRequestCount)
          .set('price', nextPrice)
          .set('appId', nextAppId)
          .set('app_id', nextAppId)
          .set('appIds', nextAppIds)
          .set('app_ids', nextAppIds)
          .set('scope', nextScope)
          .set('isActive', isActive ?? existing.isActive)
          .set('updatedAt', now.toIso8601String()),
    );
    if (!result.isSuccess || result.nMatched == 0) {
      throw const BillingServiceException(
        'Failed to update request package',
        statusCode: 500,
      );
    }

    return findRequestPackage(packageId, activeOnly: false);
  }

  Future<void> deleteRequestPackage(ObjectId packageId) async {
    // Удаление нужно для админки, если товар больше не должен существовать.
    final result = await _requestPackagesCollection.deleteOne(
      where.eq('_id', packageId),
    );
    if (!result.isSuccess) {
      throw const BillingServiceException(
        'Failed to delete request package',
        statusCode: 500,
      );
    }
  }

  Future<RequestPackage> findRequestPackage(
    ObjectId packageId, {
    bool activeOnly = true,
  }) async {
    final rawPackage = await _requestPackagesCollection.findOne(
      activeOnly
          ? where.eq('_id', packageId).eq('isActive', true)
          : where.eq('_id', packageId),
    );
    if (rawPackage == null) {
      throw const BillingServiceException(
        'Request package not found',
        statusCode: 404,
      );
    }

    return RequestPackage.fromJson(rawPackage);
  }

  void assertRequestPackageAvailableForApp(RequestPackage package, String appId) {
    _assertRequestPackageAvailableForApp(package, normalizeAppId(appId));
  }

  /// Функция getAiRequestPrice: получает нужное значение и возвращает его вызывающему коду.
  /// Возвращает число с копейками или дробной частью.
  Future<double> getAiRequestPrice() async {
    // Раньше цена была одной настройкой в админке.
    // Сейчас цена зависит от 4-часовой сессии:
    // первый запрос 299, второй 149, все следующие 99.
    // Для старых мест, где всё ещё нужен "общий прайс", возвращаем первую цену.
    return firstAiRequestPrice;
  }

  /// Функция setAiRequestPrice: записывает новое значение. Обычно ничего полезного не возвращает.
  /// Возвращает число с копейками или дробной частью.
  Future<double> setAiRequestPrice(double price) async {
    // Цена больше не настраивается одним числом.
    // Метод оставлен для совместимости старой админки, но продуктово
    // используется фиксированная лестница 299 -> 149 -> 99.
    return firstAiRequestPrice;
  }

  /// Функция getReferralBonusAmount: получает нужное значение и возвращает его вызывающему коду.
  /// Возвращает число с копейками или дробной частью.
  Future<double> getReferralBonusAmount() async {
    // По текущим условиям рефералка фиксированная:
    // пригласивший получает 300 ₽ и приглашённый тоже получает 300 ₽.
    return referralBonusAmount;
  }

  /// Функция setReferralBonusAmount: записывает новое значение. Обычно ничего полезного не возвращает.
  /// Возвращает число с копейками или дробной частью.
  Future<double> setReferralBonusAmount(double amount) async {
    // Бонус больше не управляется из админки одним числом.
    // Метод оставлен, чтобы старая HTML-админка не падала при сохранении.
    return referralBonusAmount;
  }

  Future<User> ensureStartingAppRequestBalance({
    required ObjectId userId,
    String? appId,
  }) async {
    final normalizedAppId = normalizeAppId(appId);
    final user = await _findUser(userId);
    if (startingAppRequestCount <= 0) {
      return user;
    }

    final existingGrant = await _transactionsCollection.findOne(
      where
          .eq('userId', userId)
          .eq('description', startingAppRequestDescription)
          .eq('metadata.provider', 'starting_app_request')
          .eq('metadata.appId', normalizedAppId),
    );
    if (existingGrant != null) {
      return user;
    }

    final now = DateTime.now().toUtc();
    final targetBalance = _requestBalanceForScope(
      user.requestBalances,
      appId: normalizedAppId,
      scope: subscriptionScopeApp,
    );
    final nextRequestBalances = User.upsertRequestBalance(
      user.requestBalances,
      targetBalance.copyWith(
        balance: targetBalance.balance + startingAppRequestCount,
        updatedAt: now,
      ),
    );

    final updateResult = await _usersCollection.updateOne(
      where.eq('_id', userId),
      modify
          .set(
            'requestBalances',
            nextRequestBalances.map((item) => item.toJson()).toList(),
          )
          .set(
            'requestBalance',
            User.effectiveRequestBalanceForAppFrom(
              nextRequestBalances,
              normalizedAppId,
            ),
          )
          .set('updatedAt', now.toIso8601String()),
    );
    if (!updateResult.isSuccess || updateResult.nMatched == 0) {
      throw const BillingServiceException(
        'Failed to apply starting app request bonus',
        statusCode: 500,
      );
    }

    final transaction = Transaction(
      userId: userId,
      userName: user.name,
      amount: 0,
      type: TransactionType.deposit,
      description: startingAppRequestDescription,
      metadata: {
        'provider': 'starting_app_request',
        'reason': 'new_user_trial',
        'requestCount': startingAppRequestCount,
        'scope': subscriptionScopeApp,
        'appId': normalizedAppId,
        'app_id': normalizedAppId,
      },
      createdAt: now,
    );
    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );
    if (!transactionResult.isSuccess) {
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set(
              'requestBalances',
              user.requestBalances.map((item) => item.toJson()).toList(),
            )
            .set(
              'requestBalance',
              user.effectiveRequestBalanceForApp(normalizedAppId),
            )
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const BillingServiceException(
        'Failed to save starting app request transaction',
        statusCode: 500,
      );
    }

    return _findUser(userId);
  }

  /// Функция prepareAiRequestCharge: выполняет шаг prepareAiRequestCharge в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<AiRequestChargePreparation> prepareAiRequestCharge(
    ObjectId userId, {
    String? appId,
  }) async {
    // Это "сухая проверка" перед вызовом AI.
    //
    // Идея такая:
    // 1. Ещё ничего не списываем
    // 2. Но заранее убеждаемся, что пользователь существует
    // 3. И что у него есть купленный запрос или хватает денег на будущий ответ
    //
    // Так мы не зовём внешнюю модель для пользователя,
    // который всё равно не сможет оплатить ответ.
    final normalizedAppId = normalizeAppId(appId);
    final user = await ensureStartingAppRequestBalance(
      userId: userId,
      appId: normalizedAppId,
    );
    final sessionState = await _resolveAiSessionState(userId);
    if (user.hasActiveSubscriptionForApp(normalizedAppId)) {
      return AiRequestChargePreparation(
        user: user,
        requestPrice: 0,
        willUseRequestBalance: false,
        hasActiveSubscription: true,
        sessionStartedAt: sessionState.startedAt,
        sessionRequestIndex: sessionState.requestIndex,
      );
    }

    if (user.effectiveRequestBalanceForApp(normalizedAppId) > 0) {
      return AiRequestChargePreparation(
        user: user,
        requestPrice: 0,
        willUseRequestBalance: true,
        hasActiveSubscription: false,
        sessionStartedAt: sessionState.startedAt,
        sessionRequestIndex: sessionState.requestIndex,
      );
    }

    final requestPrice = priceForSessionRequestIndex(sessionState.requestIndex);

    if (requestPrice > 0 && user.balance < requestPrice) {
      /// Функция BillingServiceException: выполняет шаг BillingServiceException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw BillingServiceException(
        'Insufficient balance for AI request',
        statusCode: 402,
        errorCode: insufficientBalanceErrorCode,
        details: _buildInsufficientBalanceDetails(
          currentBalance: user.balance,
          requiredAmount: requestPrice,
        ),
      );
    }

    /// Функция AiRequestChargePreparation: выполняет шаг AiRequestChargePreparation в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return AiRequestChargePreparation(
      user: user,
      requestPrice: requestPrice,
      willUseRequestBalance: false,
      hasActiveSubscription: false,
      sessionStartedAt: sessionState.startedAt,
      sessionRequestIndex: sessionState.requestIndex,
    );
  }

  /// Функция chargeSuccessfulAiRequest: выполняет шаг chargeSuccessfulAiRequest в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<AiRequestChargeResult> chargeSuccessfulAiRequest({
    required ObjectId userId,
    required String userName,
    required double requestPrice,
    required DateTime sessionStartedAt,
    required int sessionRequestIndex,
    String? appId,
  }) async {
    // Это уже "боевое" списание после успешного ответа модели.
    final normalizedAppId = normalizeAppId(appId);
    final currentUserBeforeCharge = await _findUser(userId);
    if (currentUserBeforeCharge.hasActiveSubscriptionForApp(normalizedAppId)) {
      return AiRequestChargeResult(
        chargedAmount: 0,
        newBalance: currentUserBeforeCharge.balance,
        newRequestBalance: currentUserBeforeCharge
            .effectiveRequestBalanceForApp(normalizedAppId),
        paymentSource: 'subscription',
      );
    }

    final requestBalanceResult = await _tryChargeRequestBalance(
      userId: userId,
      userName: userName,
      appId: normalizedAppId,
      sessionStartedAt: sessionStartedAt,
      sessionRequestIndex: sessionRequestIndex,
    );
    if (requestBalanceResult != null) {
      return requestBalanceResult;
    }

    final normalizedPrice = _normalizeMoneyAmount(requestPrice);

    // Если цена = 0, просто возвращаем текущий баланс без изменений.
    if (normalizedPrice <= 0) {
      final currentUser = await _findUser(userId);
      final paymentSource =
          currentUser.hasActiveSubscriptionForApp(normalizedAppId)
          ? 'subscription'
          : 'free';

      /// Функция AiRequestChargeResult: выполняет шаг AiRequestChargeResult в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
      /// Возвращает значение типа return; это готовый результат для следующего шага программы.
      return AiRequestChargeResult(
        chargedAmount: 0,
        newBalance: currentUser.balance,
        newRequestBalance: currentUser.effectiveRequestBalanceForApp(
          normalizedAppId,
        ),
        paymentSource: paymentSource,
      );
    }

    final now = DateTime.now().toUtc();

    // Здесь важный момент:
    // в where добавлен gte('balance', normalizedPrice).
    //
    // Это значит: списывать деньги только если в момент обновления
    // баланс всё ещё достаточный.
    //
    // Зачем это нужно:
    // между prepareAiRequestCharge(...) и фактическим списанием
    // баланс пользователя уже мог измениться.
    final updateResult = await _usersCollection.updateOne(
      where.eq('_id', userId).gte('balance', normalizedPrice),
      modify
          .inc('balance', -normalizedPrice)
          .set('updatedAt', now.toIso8601String()),
    );

    if (!updateResult.isSuccess) {
      throw const BillingServiceException(
        'Failed to charge successful AI request',
        statusCode: 500,
      );
    }

    // Если документ не обновился, значит денег уже не хватило
    // прямо в момент фактического списания.
    if (updateResult.nMatched == 0 || updateResult.nModified == 0) {
      final currentUser = await _findUser(userId);

      /// Функция BillingServiceException: выполняет шаг BillingServiceException в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw BillingServiceException(
        'Insufficient balance for AI request',
        statusCode: 402,
        errorCode: insufficientBalanceErrorCode,
        details: _buildInsufficientBalanceDetails(
          currentBalance: currentUser.balance,
          requiredAmount: normalizedPrice,
        ),
      );
    }

    // После изменения balance обязательно пишем отдельную транзакцию в историю.
    final transaction = Transaction(
      userId: userId,
      userName: userName,
      amount: normalizedPrice,
      type: TransactionType.payment,
      description: aiRequestChargeDescription,
      metadata: {
        'sessionStartedAt': sessionStartedAt.toIso8601String(),
        'sessionDurationHours': aiSessionDurationHours,
        'sessionRequestIndex': sessionRequestIndex,
        'priceRule': '299-149-99',
        'appId': normalizedAppId,
        'app_id': normalizedAppId,
      },
      createdAt: now,
    );

    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );

    // Если баланс уже уменьшили, а транзакцию сохранить не смогли,
    // откатываем списание обратно. Иначе деньги "исчезнут" из баланса
    // без записи в историю, а это уже плохое состояние данных.
    if (!transactionResult.isSuccess) {
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .inc('balance', normalizedPrice)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );

      throw const BillingServiceException(
        'Failed to save AI charge transaction',
        statusCode: 500,
      );
    }

    final updatedUser = await _findUser(userId);

    /// Функция AiRequestChargeResult: выполняет шаг AiRequestChargeResult в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return AiRequestChargeResult(
      chargedAmount: normalizedPrice,
      newBalance: updatedUser.balance,
      newRequestBalance: updatedUser.effectiveRequestBalanceForApp(
        normalizedAppId,
      ),
      paymentSource: 'balance',
    );
  }

  /// Функция listAiChargeTransactions: получает список данных и возвращает его вызывающему коду.
  /// Возвращает текст.
  Future<List<Map<String, dynamic>>> listAiChargeTransactions({
    int limit = defaultAdminHistoryLimit,
  }) async {
    // Для админки собираем только AI-списания:
    // type=payment + description=AI request charge
    final normalizedLimit = limit <= 0 ? defaultAdminHistoryLimit : limit;
    final rawTransactions = await _transactionsCollection
        .find(
          where
              .eq('type', TransactionType.payment.name)
              .eq('description', aiRequestChargeDescription),
        )
        .toList();

    // Сортируем вручную по дате от новых к старым.
    rawTransactions.sort((left, right) {
      final leftDate = _parseDateTime(right['createdAt']);
      final rightDate = _parseDateTime(left['createdAt']);
      return leftDate.compareTo(rightDate);
    });

    // Старые транзакции могут не содержать userName.
    // Тогда подтягиваем имя пользователя отдельно по userId,
    // чтобы в админке не было пустых строк.
    final limitedTransactions = rawTransactions.take(normalizedLimit).toList();
    final missingUserIds = limitedTransactions
        .where((item) => item['userName'] == null || item['userName'] == '')
        .map((item) => item['userId'])
        .whereType<ObjectId>()
        .toSet()
        .toList();

    final usersById = <String, String>{};
    for (final userId in missingUserIds) {
      final rawUser = await _usersCollection.findOne(where.eq('_id', userId));
      if (rawUser == null) {
        continue;
      }

      final user = User.fromJson(rawUser);
      if (user.id != null) {
        usersById[user.id!.oid] = user.name;
      }
    }

    return limitedTransactions.map((rawTransaction) {
      final transaction = Transaction.fromJson(rawTransaction);
      final fallbackUserName = usersById[transaction.userId.oid];
      final publicJson = transaction.toPublicJson();
      if ((publicJson['userName'] == null || publicJson['userName'] == '') &&
          fallbackUserName != null) {
        publicJson['userName'] = fallbackUserName;
      }
      return publicJson;
    }).toList();
  }

  Future<RequestPackagePurchaseResult> purchaseRequestPackageWithBalance({
    required ObjectId userId,
    required ObjectId packageId,
    String? appId,
  }) async {
    // Покупка пакета с внутреннего баланса:
    // пользователь тратит рубли на счёте и получает запас AI-запросов.
    final package = await findRequestPackage(packageId);
    final normalizedAppId = normalizeAppId(appId);
    _assertRequestPackageAvailableForApp(package, normalizedAppId);
    final user = await _findUser(userId);
    if (user.balance < package.price) {
      throw BillingServiceException(
        'Insufficient balance for request package',
        statusCode: 402,
        errorCode: insufficientBalanceErrorCode,
        details: _buildInsufficientBalanceDetails(
          currentBalance: user.balance,
          requiredAmount: package.price,
        ),
      );
    }

    return _applyRequestPackagePurchase(
      userId: userId,
      package: package,
      paymentSource: 'balance',
      paidAmount: package.price,
      externalPaymentId: null,
      externalOrderId: null,
      contextAppId: appId,
    );
  }

  Future<RequestPackagePurchaseResult> applyRequestPackageCardPurchase({
    required ObjectId userId,
    required RequestPackage package,
    required String? paymentId,
    required String? orderId,
    String? appId,
  }) async {
    // Покупка пакета картой:
    // деньги идут через банк, а пользователю начисляются запросы, не рубли.
    return _applyRequestPackagePurchase(
      userId: userId,
      package: package,
      paymentSource: 'card',
      paidAmount: package.price,
      externalPaymentId: paymentId,
      externalOrderId: orderId,
      contextAppId: appId,
    );
  }

  Future<SubscriptionPurchaseResult> applySubscriptionCardPurchase({
    required ObjectId userId,
    required SubscriptionSettings settings,
    required String? paymentId,
    required String? orderId,
    String? appId,
  }) async {
    return _applySubscriptionPurchase(
      userId: userId,
      settings: settings,
      paymentSource: 'card',
      paidAmount: settings.price,
      paymentId: paymentId,
      orderId: orderId,
      contextAppId: appId,
    );
  }

  Future<SubscriptionPurchaseResult> purchaseSubscriptionWithBalance({
    required ObjectId userId,
    String? appId,
    String scope = subscriptionScopeApp,
  }) async {
    final settings = await getSubscriptionSettings(appId: appId, scope: scope);
    final user = await _findUser(userId);
    if (user.balance < settings.price) {
      throw BillingServiceException(
        'Insufficient balance for subscription',
        statusCode: 402,
        errorCode: insufficientBalanceErrorCode,
        details: _buildInsufficientBalanceDetails(
          currentBalance: user.balance,
          requiredAmount: settings.price,
        ),
      );
    }

    return _applySubscriptionPurchase(
      userId: userId,
      settings: settings,
      paymentSource: 'balance',
      paidAmount: settings.price,
      paymentId: null,
      orderId: null,
      contextAppId: appId,
    );
  }

  Future<SubscriptionPurchaseResult> _applySubscriptionPurchase({
    required ObjectId userId,
    required SubscriptionSettings settings,
    required String paymentSource,
    required double paidAmount,
    required String? paymentId,
    required String? orderId,
    String? contextAppId,
  }) async {
    // Подписка покупается на месяц и снимает лимиты по AI-ответам.
    // Если подписка уже активна, новый месяц добавляется к текущей дате окончания.
    final user = await _findUser(userId);
    final existingTransaction = await _findSubscriptionDuplicateTransaction(
      paymentId: paymentId,
      orderId: orderId,
    );
    if (existingTransaction != null) {
      final exactSubscription = user.subscriptionFor(
        scope: settings.scope,
        appId: settings.appId,
      );
      return SubscriptionPurchaseResult(
        settings: settings,
        transaction: Transaction.fromJson(existingTransaction),
        subscriptionExpiresAt:
            exactSubscription?.expiresAt ??
            user
                .effectiveSubscriptionForApp(normalizeAppId(contextAppId))
                ?.expiresAt ??
            DateTime.now().toUtc(),
        newBalance: user.balance,
      );
    }

    final now = DateTime.now().toUtc();
    final normalizedPaidAmount = _normalizeMoneyAmount(paidAmount);
    final currentSubscription = user.subscriptionFor(
      scope: settings.scope,
      appId: settings.appId,
    );
    final currentExpiresAt = currentSubscription?.expiresAt?.toUtc();
    final startsAt = currentExpiresAt != null && currentExpiresAt.isAfter(now)
        ? currentExpiresAt
        : now;
    final expiresAt = startsAt.add(
      const Duration(days: subscriptionPeriodDays),
    );

    final nextSubscriptions = User.upsertSubscription(
      user.subscriptions,
      UserSubscription(
        scope: settings.scope,
        appId: settings.appId,
        expiresAt: expiresAt,
        autoRenewEnabled: currentSubscription?.autoRenewEnabled ?? false,
        nextChargeAt: currentSubscription?.nextChargeAt,
        rebillId: currentSubscription?.rebillId,
        recurringPaymentId: currentSubscription?.recurringPaymentId,
        recurringOrderId: currentSubscription?.recurringOrderId,
        updatedAt: now,
      ),
    );
    final legacyAppId = normalizeAppId(contextAppId);
    final legacySubscription = User.effectiveSubscriptionForAppFrom(
      nextSubscriptions,
      legacyAppId,
    );
    final modifier = modify
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
        .set('updatedAt', now.toIso8601String());
    SelectorBuilder selector = where.eq('_id', userId);
    if (paymentSource == 'balance') {
      selector = selector.gte('balance', normalizedPaidAmount);
      modifier.inc('balance', -normalizedPaidAmount);
    }

    final result = await _usersCollection.updateOne(selector, modifier);
    if (!result.isSuccess) {
      throw const BillingServiceException(
        'Failed to apply subscription',
        statusCode: 500,
      );
    }
    if (result.nMatched == 0 || result.nModified == 0) {
      final currentUser = await _findUser(userId);
      throw BillingServiceException(
        'Insufficient balance for subscription',
        statusCode: 402,
        errorCode: insufficientBalanceErrorCode,
        details: _buildInsufficientBalanceDetails(
          currentBalance: currentUser.balance,
          requiredAmount: normalizedPaidAmount,
        ),
      );
    }

    final transaction = Transaction(
      userId: userId,
      userName: user.name,
      amount: normalizedPaidAmount,
      type: TransactionType.payment,
      description: subscriptionPurchaseDescription,
      metadata: {
        'paymentSource': paymentSource,
        'subscriptionName': settings.name,
        'subscriptionScope': settings.scope,
        'appId': settings.appId,
        'app_id': settings.appId,
        'subscriptionPeriodDays': subscriptionPeriodDays,
        'subscriptionExpiresAt': expiresAt.toIso8601String(),
        'paymentId': ?paymentId,
        'purchaseId': ?paymentId,
        'orderId': ?orderId,
        'invoiceId': ?orderId,
        'provider': paymentSource == 'card' ? 'tbank' : 'balance',
      },
      createdAt: now,
    );
    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );
    if (!transactionResult.isSuccess) {
      final rollbackModifier = modify
          .set(
            'subscriptions',
            user.subscriptions.map((item) => item.toJson()).toList(),
          )
          .set(
            'subscriptionExpiresAt',
            user.subscriptionExpiresAt?.toIso8601String(),
          )
          .set(
            'subscriptionAutoRenewEnabled',
            user.subscriptionAutoRenewEnabled,
          )
          .set(
            'subscriptionNextChargeAt',
            user.subscriptionNextChargeAt?.toIso8601String(),
          )
          .set('updatedAt', DateTime.now().toUtc().toIso8601String());
      if (paymentSource == 'balance') {
        rollbackModifier.inc('balance', normalizedPaidAmount);
      }
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        rollbackModifier,
      );
      throw const BillingServiceException(
        'Failed to save subscription transaction',
        statusCode: 500,
      );
    }

    final createdTransaction = await _transactionsCollection.findOne(
      where.eq('_id', transactionResult.id),
    );
    final updatedUser = await _findUser(userId);
    return SubscriptionPurchaseResult(
      settings: settings,
      transaction: createdTransaction != null
          ? Transaction.fromJson(createdTransaction)
          : transaction,
      subscriptionExpiresAt: expiresAt,
      newBalance: updatedUser.balance,
    );
  }

  Future<RequestPackagePurchaseResult> _applyRequestPackagePurchase({
    required ObjectId userId,
    required RequestPackage package,
    required String paymentSource,
    required double paidAmount,
    required String? externalPaymentId,
    required String? externalOrderId,
    String? contextAppId,
  }) async {
    final user = await _findUser(userId);
    final normalizedPaidAmount = _normalizeMoneyAmount(paidAmount);
    final now = DateTime.now().toUtc();
    final legacyAppId = normalizeAppId(contextAppId);
    _assertRequestPackageAvailableForApp(package, legacyAppId);
    final targetAppId = package.scope == subscriptionScopeGlobal
        ? globalAppId
        : legacyAppId;

    final existingTransaction = await _findRequestPackageDuplicateTransaction(
      paymentSource: paymentSource,
      externalPaymentId: externalPaymentId,
      externalOrderId: externalOrderId,
    );
    if (existingTransaction != null) {
      return RequestPackagePurchaseResult(
        package: package,
        transaction: Transaction.fromJson(existingTransaction),
        newBalance: user.balance,
        newRequestBalance: user.effectiveRequestBalanceForApp(legacyAppId),
      );
    }

    final targetBalance = _requestBalanceForScope(
      user.requestBalances,
      appId: targetAppId,
      scope: package.scope,
    );
    final nextRequestBalances = User.upsertRequestBalance(
      user.requestBalances,
      targetBalance.copyWith(
        balance: targetBalance.balance + package.requestCount,
        updatedAt: now,
      ),
    );
    final modifier = modify
        .set(
          'requestBalances',
          nextRequestBalances.map((item) => item.toJson()).toList(),
        )
        .set(
          'requestBalance',
          User.effectiveRequestBalanceForAppFrom(
            nextRequestBalances,
            legacyAppId,
          ),
        )
        .set('updatedAt', now.toIso8601String());
    SelectorBuilder selector = where.eq('_id', userId);
    if (paymentSource == 'balance') {
      selector = selector.gte('balance', normalizedPaidAmount);
      modifier.inc('balance', -normalizedPaidAmount);
    }

    final updateResult = await _usersCollection.updateOne(selector, modifier);
    if (!updateResult.isSuccess) {
      throw const BillingServiceException(
        'Failed to apply request package',
        statusCode: 500,
      );
    }
    if (updateResult.nMatched == 0 || updateResult.nModified == 0) {
      final currentUser = await _findUser(userId);
      throw BillingServiceException(
        'Insufficient balance for request package',
        statusCode: 402,
        errorCode: insufficientBalanceErrorCode,
        details: _buildInsufficientBalanceDetails(
          currentBalance: currentUser.balance,
          requiredAmount: normalizedPaidAmount,
        ),
      );
    }

    final transaction = Transaction(
      userId: userId,
      userName: user.name,
      amount: normalizedPaidAmount,
      type: TransactionType.payment,
      description: requestPackagePurchaseDescription,
      metadata: {
        'paymentSource': paymentSource,
        'requestPackageId': package.id?.oid,
        'requestCount': package.requestCount,
        'packagePrice': package.price,
        'requestPackageScope': package.scope,
        'appId': package.appId,
        'app_id': package.appId,
        'appIds': package.appIds,
        'app_ids': package.appIds,
        'contextAppId': legacyAppId,
        'context_app_id': legacyAppId,
        'paymentId': ?externalPaymentId,
        'purchaseId': ?externalPaymentId,
        'orderId': ?externalOrderId,
        'invoiceId': ?externalOrderId,
      },
      createdAt: now,
    );
    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );
    if (!transactionResult.isSuccess) {
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        paymentSource == 'balance'
            ? modify
                  .inc('balance', normalizedPaidAmount)
                  .set(
                    'requestBalances',
                    user.requestBalances.map((item) => item.toJson()).toList(),
                  )
                  .set(
                    'requestBalance',
                    user.effectiveRequestBalanceForApp(legacyAppId),
                  )
                  .set('updatedAt', DateTime.now().toUtc().toIso8601String())
            : modify
                  .set(
                    'requestBalances',
                    user.requestBalances.map((item) => item.toJson()).toList(),
                  )
                  .set(
                    'requestBalance',
                    user.effectiveRequestBalanceForApp(legacyAppId),
                  )
                  .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const BillingServiceException(
        'Failed to save request package transaction',
        statusCode: 500,
      );
    }

    final createdTransaction = await _transactionsCollection.findOne(
      where.eq('_id', transactionResult.id),
    );
    final updatedUser = await _findUser(userId);
    return RequestPackagePurchaseResult(
      package: package,
      transaction: createdTransaction != null
          ? Transaction.fromJson(createdTransaction)
          : transaction,
      newBalance: updatedUser.balance,
      newRequestBalance: updatedUser.effectiveRequestBalanceForApp(legacyAppId),
    );
  }

  Future<AiRequestChargeResult?> _tryChargeRequestBalance({
    required ObjectId userId,
    required String userName,
    required String appId,
    required DateTime sessionStartedAt,
    required int sessionRequestIndex,
  }) async {
    // Если у пользователя есть купленные запросы, сначала тратим их.
    // Баланс в рублях нужен только когда запас запросов закончился.
    final now = DateTime.now().toUtc();
    final user = await _findUser(userId);
    final chargeTarget = _findRequestBalanceChargeTarget(
      user.requestBalances,
      appId: appId,
    );
    if (chargeTarget == null) {
      return null;
    }
    final nextRequestBalances = User.upsertRequestBalance(
      user.requestBalances,
      chargeTarget.copyWith(balance: chargeTarget.balance - 1, updatedAt: now),
    );
    final updateResult = await _usersCollection.updateOne(
      where.eq('_id', userId),
      modify
          .set(
            'requestBalances',
            nextRequestBalances.map((item) => item.toJson()).toList(),
          )
          .set(
            'requestBalance',
            User.effectiveRequestBalanceForAppFrom(nextRequestBalances, appId),
          )
          .set('updatedAt', now.toIso8601String()),
    );
    if (!updateResult.isSuccess) {
      throw const BillingServiceException(
        'Failed to charge request balance',
        statusCode: 500,
      );
    }
    if (updateResult.nMatched == 0 || updateResult.nModified == 0) {
      return null;
    }

    final transaction = Transaction(
      userId: userId,
      userName: userName,
      amount: 0,
      type: TransactionType.payment,
      description: aiRequestPackageChargeDescription,
      metadata: {
        'paymentSource': 'requestBalance',
        'requestsCharged': 1,
        'requestPackageScope': chargeTarget.scope,
        'appId': chargeTarget.appId,
        'app_id': chargeTarget.appId,
        'contextAppId': appId,
        'context_app_id': appId,
        'sessionStartedAt': sessionStartedAt.toIso8601String(),
        'sessionDurationHours': aiSessionDurationHours,
        'sessionRequestIndex': sessionRequestIndex,
      },
      createdAt: now,
    );
    final transactionResult = await _transactionsCollection.insertOne(
      transaction.toJson(),
    );
    if (!transactionResult.isSuccess) {
      await _usersCollection.updateOne(
        where.eq('_id', userId),
        modify
            .set(
              'requestBalances',
              user.requestBalances.map((item) => item.toJson()).toList(),
            )
            .set('requestBalance', user.effectiveRequestBalanceForApp(appId))
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );
      throw const BillingServiceException(
        'Failed to save request balance transaction',
        statusCode: 500,
      );
    }

    final updatedUser = await _findUser(userId);
    return AiRequestChargeResult(
      chargedAmount: 0,
      newBalance: updatedUser.balance,
      newRequestBalance: updatedUser.effectiveRequestBalanceForApp(appId),
      paymentSource: 'requestBalance',
    );
  }

  UserRequestBalance _requestBalanceForScope(
    List<UserRequestBalance> requestBalances, {
    required String appId,
    required String scope,
  }) {
    final normalizedAppId = normalizeAppId(appId);
    final normalizedScope = normalizeSubscriptionScope(scope);
    for (final requestBalance in requestBalances) {
      if (requestBalance.scope == normalizedScope &&
          requestBalance.appId == normalizedAppId) {
        return requestBalance;
      }
    }
    return UserRequestBalance(
      scope: normalizedScope,
      appId: normalizedAppId,
      balance: 0,
    );
  }

  UserRequestBalance? _findRequestBalanceChargeTarget(
    List<UserRequestBalance> requestBalances, {
    required String appId,
  }) {
    final normalizedAppId = normalizeAppId(appId);
    for (final requestBalance in requestBalances) {
      if (requestBalance.scope == subscriptionScopeApp &&
          requestBalance.appId == normalizedAppId &&
          requestBalance.balance > 0) {
        return requestBalance;
      }
    }

    for (final requestBalance in requestBalances) {
      if (requestBalance.scope == subscriptionScopeGlobal &&
          requestBalance.balance > 0) {
        return requestBalance;
      }
    }

    return null;
  }

  /// Функция _findUser: выполняет шаг _findUser в этой части программы. Возвращает результат позже, когда закончится асинхронная работа.
  /// Возвращает результат позже, когда закончится асинхронная работа.
  Future<User> _findUser(ObjectId userId) async {
    // Общий helper, чтобы не повторять одну и ту же логику поиска пользователя
    // в каждом методе биллинга.
    final rawUser = await _usersCollection.findOne(where.eq('_id', userId));

    if (rawUser == null) {
      throw const BillingServiceException('User not found', statusCode: 404);
    }

    return User.fromJson(rawUser);
  }

  Future<Map<String, dynamic>?> _findRequestPackageDuplicateTransaction({
    required String paymentSource,
    required String? externalPaymentId,
    required String? externalOrderId,
  }) async {
    // Для покупок картой проверяем дубль банковского платежа.
    // Это защищает от повторного начисления одного и того же пакета.
    if (paymentSource != 'card') {
      return null;
    }
    if ((externalPaymentId == null || externalPaymentId.isEmpty) &&
        (externalOrderId == null || externalOrderId.isEmpty)) {
      return null;
    }

    final rawTransactions = await _transactionsCollection
        .find(
          where
              .eq('type', TransactionType.payment.name)
              .eq('description', requestPackagePurchaseDescription),
        )
        .toList();
    for (final rawTransaction in rawTransactions) {
      final transaction = Map<String, dynamic>.from(rawTransaction);
      final metadata = transaction['metadata'] is Map
          ? Map<String, dynamic>.from(transaction['metadata'] as Map)
          : const <String, dynamic>{};
      final samePayment =
          externalPaymentId != null &&
          externalPaymentId.isNotEmpty &&
          metadata['paymentId']?.toString() == externalPaymentId;
      final sameOrder =
          externalOrderId != null &&
          externalOrderId.isNotEmpty &&
          metadata['orderId']?.toString() == externalOrderId;
      if (samePayment || sameOrder) {
        return transaction;
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _findSubscriptionDuplicateTransaction({
    required String? paymentId,
    required String? orderId,
  }) async {
    // Проверяем банковский платёж, чтобы один и тот же платёж не продлил подписку дважды.
    if ((paymentId == null || paymentId.isEmpty) &&
        (orderId == null || orderId.isEmpty)) {
      return null;
    }

    final rawTransactions = await _transactionsCollection
        .find(
          where
              .eq('type', TransactionType.payment.name)
              .eq('description', subscriptionPurchaseDescription),
        )
        .toList();
    for (final rawTransaction in rawTransactions) {
      final transaction = Map<String, dynamic>.from(rawTransaction);
      final metadata = transaction['metadata'] is Map
          ? Map<String, dynamic>.from(transaction['metadata'] as Map)
          : const <String, dynamic>{};
      final samePayment =
          paymentId != null &&
          paymentId.isNotEmpty &&
          metadata['paymentId']?.toString() == paymentId;
      final sameOrder =
          orderId != null &&
          orderId.isNotEmpty &&
          metadata['orderId']?.toString() == orderId;
      if (samePayment || sameOrder) {
        return transaction;
      }
    }

    return null;
  }

  int _normalizeRequestCount(int requestCount) {
    // Минимальный товар - 10 запросов, чтобы не плодить микропакеты.
    if (requestCount < 10) {
      throw const BillingServiceException(
        'Request package must contain at least 10 requests',
      );
    }
    return requestCount;
  }

  double _normalizePackagePrice(double price) {
    if (price <= 0) {
      throw const BillingServiceException('Request package price is invalid');
    }
    return _normalizeMoneyAmount(price);
  }

  String _normalizeSubscriptionName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 40) {
      throw const BillingServiceException('Subscription name is invalid');
    }

    return normalized;
  }

  static String normalizeAppId(String? appId) {
    final normalized = (appId ?? AppConfig.appId).trim().toLowerCase();
    if (normalized.isEmpty) {
      return User.defaultAppId;
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$').hasMatch(normalized)) {
      throw const BillingServiceException('App ID is invalid');
    }
    return normalized;
  }

  static String normalizeSubscriptionScope(String? scope) {
    final normalized = scope?.trim().toLowerCase();
    return normalized == subscriptionScopeGlobal
        ? subscriptionScopeGlobal
        : subscriptionScopeApp;
  }

  static List<String> _normalizeRequestPackageAppIds(
    List<String>? appIds,
    String? fallbackAppId,
  ) {
    final normalizedValues = <String>{};
    for (final appId in appIds ?? const <String>[]) {
      normalizedValues.add(normalizeAppId(appId));
    }
    if (normalizedValues.isEmpty) {
      normalizedValues.add(normalizeAppId(fallbackAppId));
    }
    return normalizedValues.toList();
  }

  static void _assertRequestPackageAvailableForApp(
    RequestPackage package,
    String appId,
  ) {
    if (package.scope == subscriptionScopeGlobal) {
      return;
    }
    final normalizedAppId = normalizeAppId(appId);
    if (package.appIds.contains(normalizedAppId)) {
      return;
    }
    throw const BillingServiceException(
      'Request package is not available for this app',
      statusCode: 409,
    );
  }

  static String _subscriptionSettingsKeyFor({
    required String appId,
    required String scope,
  }) {
    final normalizedScope = normalizeSubscriptionScope(scope);
    if (normalizedScope == subscriptionScopeGlobal) {
      return 'monthly_subscription:global';
    }
    return 'monthly_subscription:app:${normalizeAppId(appId)}';
  }

  /// Функция _normalizeMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает число с копейками или дробной частью.
  double _normalizeMoneyAmount(double amount) {
    // Денежные значения округляем до копеек.
    return double.parse(amount.toStringAsFixed(2));
  }

  /// Функция priceForSessionRequestIndex: выполняет шаг priceForSessionRequestIndex в этой части программы. Возвращает число с копейками или дробной частью.
  /// Возвращает число с копейками или дробной частью.
  static double priceForSessionRequestIndex(int requestIndex) {
    // Простое правило 4-часовой сессии:
    // 1-й ответ стоит 299 ₽, 2-й стоит 149 ₽,
    // 3-й и все следующие стоят 99 ₽.
    if (requestIndex <= 1) {
      return firstAiRequestPrice;
    }
    if (requestIndex == 2) {
      return secondAiRequestPrice;
    }
    return nextAiRequestPrice;
  }

  /// Функция creditedTopUpAmount: выполняет шаг creditedTopUpAmount в этой части программы. Возвращает число с копейками или дробной частью.
  /// Возвращает число с копейками или дробной частью.
  static double creditedTopUpAmount(double paidAmount) {
    // За любое пополнение начисляем приятный бонус сверху:
    // человек платит 100 ₽, на баланс падает 110 ₽.
    return _normalizeStaticMoneyAmount(
      paidAmount + topUpBonusAmount(paidAmount),
    );
  }

  /// Функция topUpBonusAmount: выполняет шаг topUpBonusAmount в этой части программы. Возвращает число с копейками или дробной частью.
  /// Возвращает число с копейками или дробной частью.
  static double topUpBonusAmount(double paidAmount) {
    /// Функция _normalizeStaticMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return _normalizeStaticMoneyAmount(paidAmount * topUpBonusPercent);
  }

  /// Функция _resolveAiSessionState: выполняет шаг _resolveAiSessionState в этой части программы. Возвращает целое число.
  /// Возвращает целое число.
  Future<({DateTime startedAt, int requestIndex})> _resolveAiSessionState(
    ObjectId userId,
  ) async {
    final now = DateTime.now().toUtc();
    final rawTransactions = await _transactionsCollection
        .find(
          where
              .eq('userId', userId)
              .eq('type', TransactionType.payment.name)
              .eq('description', aiRequestChargeDescription),
        )
        .toList();

    final transactions =
        rawTransactions.map((item) => Map<String, dynamic>.from(item)).toList()
          ..sort(
            (left, right) => _parseDateTime(
              right['createdAt'],
            ).compareTo(_parseDateTime(left['createdAt'])),
          );

    if (transactions.isEmpty) {
      return (startedAt: now, requestIndex: 1);
    }

    final latestTransaction = transactions.first;
    final latestCreatedAt = _parseDateTime(latestTransaction['createdAt']);
    final latestMetadata = latestTransaction['metadata'] is Map
        ? Map<String, dynamic>.from(latestTransaction['metadata'] as Map)
        : const <String, dynamic>{};
    final savedSessionStart = _parseNullableDateTime(
      latestMetadata['sessionStartedAt'],
    );
    final sessionStart = savedSessionStart ?? latestCreatedAt;
    final sessionEnd = sessionStart.add(
      const Duration(hours: aiSessionDurationHours),
    );

    if (!now.isBefore(sessionEnd)) {
      return (startedAt: now, requestIndex: 1);
    }

    final activeSessionCount = transactions.where((transaction) {
      final createdAt = _parseDateTime(transaction['createdAt']);
      return !createdAt.isBefore(sessionStart) &&
          createdAt.isBefore(sessionEnd);
    }).length;

    return (startedAt: sessionStart, requestIndex: activeSessionCount + 1);
  }

  /// Функция _buildInsufficientBalanceDetails: собирает и возвращает видимый кусок экрана, который пользователь видит в приложении.
  /// Возвращает текст.
  Map<String, dynamic> _buildInsufficientBalanceDetails({
    required double currentBalance,
    required double requiredAmount,
  }) {
    // Это структурированные детали ошибки, которые потом удобно показать клиенту:
    // - сколько денег сейчас
    // - сколько нужно
    // - сколько не хватает
    final normalizedCurrentBalance = _normalizeMoneyAmount(currentBalance);
    final normalizedRequiredAmount = _normalizeMoneyAmount(requiredAmount);
    final shortfall = _normalizeMoneyAmount(
      normalizedRequiredAmount - normalizedCurrentBalance,
    );

    return {
      'currentBalance': normalizedCurrentBalance,
      'requiredAmount': normalizedRequiredAmount,
      'shortfall': shortfall < 0 ? 0.0 : shortfall,
    };
  }

  /// Функция _parseDateTime: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа DateTime; это готовый результат для следующего шага программы.
  DateTime _parseDateTime(dynamic value) {
    // Защита от кривых старых данных в истории.
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Функция _parseNullableDateTime: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа DateTime?; это готовый результат для следующего шага программы.
  DateTime? _parseNullableDateTime(dynamic value) {
    if (value is DateTime) {
      return value.toUtc();
    }

    final rawValue = value?.toString();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawValue)?.toUtc();
  }

  /// Функция _normalizeStaticMoneyAmount: приводит значение к единому виду и возвращает очищенный результат.
  /// Возвращает число с копейками или дробной частью.
  static double _normalizeStaticMoneyAmount(double amount) {
    return double.parse(amount.toStringAsFixed(2));
  }
}
