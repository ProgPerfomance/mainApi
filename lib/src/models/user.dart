// Этот файл: lib/src/models/user.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';

class UserSubscription {
  UserSubscription({
    required String scope,
    required String appId,
    required this.expiresAt,
    this.autoRenewEnabled = false,
    this.nextChargeAt,
    this.rebillId,
    this.recurringPaymentId,
    this.recurringOrderId,
    this.updatedAt,
  }) : scope = _normalizeScope(scope),
       appId = _normalizeAppId(appId);

  final String scope;
  final String appId;
  final DateTime? expiresAt;
  final bool autoRenewEnabled;
  final DateTime? nextChargeAt;
  final String? rebillId;
  final String? recurringPaymentId;
  final String? recurringOrderId;
  final DateTime? updatedAt;

  bool get isGlobal => scope == User.subscriptionScopeGlobal;

  bool get isActive {
    final expires = expiresAt;
    return expires != null && expires.toUtc().isAfter(DateTime.now().toUtc());
  }

  bool isActiveForApp(String appId) {
    if (!isActive) {
      return false;
    }
    if (isGlobal) {
      return true;
    }
    return this.appId == _normalizeAppId(appId);
  }

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      scope: json['scope']?.toString() ?? User.subscriptionScopeApp,
      appId:
          json['appId']?.toString() ??
          json['app_id']?.toString() ??
          User.defaultAppId,
      expiresAt: User._parseDateTime(json['expiresAt'] ?? json['expires_at']),
      autoRenewEnabled:
          json['autoRenewEnabled'] == true ||
          json['subscriptionAutoRenewEnabled'] == true,
      nextChargeAt: User._parseDateTime(
        json['nextChargeAt'] ?? json['next_charge_at'],
      ),
      rebillId: User._stringOrNull(json['rebillId'] ?? json['rebill_id']),
      recurringPaymentId: User._stringOrNull(
        json['recurringPaymentId'] ?? json['recurring_payment_id'],
      ),
      recurringOrderId: User._stringOrNull(
        json['recurringOrderId'] ?? json['recurring_order_id'],
      ),
      updatedAt: User._parseDateTime(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scope': scope,
      'appId': appId,
      'app_id': appId,
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      'autoRenewEnabled': autoRenewEnabled,
      if (nextChargeAt != null) 'nextChargeAt': nextChargeAt!.toIso8601String(),
      if (rebillId != null) 'rebillId': rebillId,
      if (recurringPaymentId != null) 'recurringPaymentId': recurringPaymentId,
      if (recurringOrderId != null) 'recurringOrderId': recurringOrderId,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> toPublicJson() {
    return {
      'scope': scope,
      'appId': appId,
      'app_id': appId,
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      'hasActiveSubscription': isActive,
      'autoRenewEnabled': autoRenewEnabled,
      if (nextChargeAt != null) 'nextChargeAt': nextChargeAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  UserSubscription copyWith({
    String? scope,
    String? appId,
    DateTime? expiresAt,
    bool? autoRenewEnabled,
    DateTime? nextChargeAt,
    String? rebillId,
    String? recurringPaymentId,
    String? recurringOrderId,
    DateTime? updatedAt,
  }) {
    return UserSubscription(
      scope: scope ?? this.scope,
      appId: appId ?? this.appId,
      expiresAt: expiresAt ?? this.expiresAt,
      autoRenewEnabled: autoRenewEnabled ?? this.autoRenewEnabled,
      nextChargeAt: nextChargeAt ?? this.nextChargeAt,
      rebillId: rebillId ?? this.rebillId,
      recurringPaymentId: recurringPaymentId ?? this.recurringPaymentId,
      recurringOrderId: recurringOrderId ?? this.recurringOrderId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _normalizeScope(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == User.subscriptionScopeGlobal
        ? User.subscriptionScopeGlobal
        : User.subscriptionScopeApp;
  }

  static String _normalizeAppId(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return User.defaultAppId;
    }
    return normalized;
  }
}

class UserRequestBalance {
  UserRequestBalance({
    required String scope,
    required String appId,
    required this.balance,
    this.updatedAt,
  }) : scope = UserSubscription._normalizeScope(scope),
       appId = UserSubscription._normalizeAppId(appId);

  final String scope;
  final String appId;
  final int balance;
  final DateTime? updatedAt;

  bool get isGlobal => scope == User.subscriptionScopeGlobal;

  factory UserRequestBalance.fromJson(Map<String, dynamic> json) {
    return UserRequestBalance(
      scope: json['scope']?.toString() ?? User.subscriptionScopeApp,
      appId:
          json['appId']?.toString() ??
          json['app_id']?.toString() ??
          User.defaultAppId,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      updatedAt: User._parseDateTime(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scope': scope,
      'appId': appId,
      'app_id': appId,
      'balance': balance,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> toPublicJson() => toJson();

  UserRequestBalance copyWith({
    String? scope,
    String? appId,
    int? balance,
    DateTime? updatedAt,
  }) {
    return UserRequestBalance(
      scope: scope ?? this.scope,
      appId: appId ?? this.appId,
      balance: balance ?? this.balance,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// User model
class User {
  static const String defaultAppId = 'psychology';
  static const String globalAppId = 'global';
  static const String subscriptionScopeApp = 'app';
  static const String subscriptionScopeGlobal = 'global';

  final ObjectId? id;
  final String name;
  final String email;
  final String passwordHash;
  final String? phoneNumber;
  final String? referralCode;
  final String? appliedReferralCode;
  final ObjectId? referredByUserId;
  final DateTime? referralAppliedAt;
  final String? avatarUrl;
  final double balance;
  final int requestBalance;
  final List<UserRequestBalance> requestBalances;
  final DateTime? subscriptionExpiresAt;
  final bool subscriptionAutoRenewEnabled;
  final DateTime? subscriptionNextChargeAt;
  final List<UserSubscription> subscriptions;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Конструктор User: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  User({
    this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    this.phoneNumber,
    this.referralCode,
    this.appliedReferralCode,
    this.referredByUserId,
    this.referralAppliedAt,
    this.avatarUrl,
    this.balance = 0.0,
    this.requestBalance = 0,
    this.requestBalances = const [],
    this.subscriptionExpiresAt,
    this.subscriptionAutoRenewEnabled = false,
    this.subscriptionNextChargeAt,
    this.subscriptions = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// From JSON
  factory User.fromJson(Map<String, dynamic> json) {
    final subscriptions = _parseSubscriptions(json);
    final requestBalances = _parseRequestBalances(json);
    final legacySubscriptionExpiresAt = _parseDateTime(
      json['subscriptionExpiresAt'],
    );
    final legacyRequestBalance = (json['requestBalance'] as num?)?.toInt();

    return User(
      id: _parseObjectId(json['_id']),
      name: _stringOrNull(json['name']) ?? '',
      email: _stringOrNull(json['email']) ?? '',
      passwordHash: _stringOrNull(json['passwordHash']) ?? '',
      phoneNumber: _stringOrNull(json['phoneNumber']),
      referralCode: _stringOrNull(json['referralCode']),
      appliedReferralCode: _stringOrNull(json['appliedReferralCode']),
      referredByUserId: _parseObjectId(json['referredByUserId']),
      referralAppliedAt: _parseDateTime(json['referralAppliedAt']),
      avatarUrl: _stringOrNull(json['avatarUrl']),
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      requestBalance:
          legacyRequestBalance ??
          effectiveRequestBalanceForAppFrom(requestBalances, defaultAppId),
      requestBalances: requestBalances,
      subscriptionExpiresAt:
          legacySubscriptionExpiresAt ??
          effectiveSubscriptionForAppFrom(
            subscriptions,
            defaultAppId,
          )?.expiresAt,
      subscriptionAutoRenewEnabled:
          json['subscriptionAutoRenewEnabled'] == true ||
          (effectiveSubscriptionForAppFrom(
                subscriptions,
                defaultAppId,
              )?.autoRenewEnabled ??
              false),
      subscriptionNextChargeAt:
          _parseDateTime(json['subscriptionNextChargeAt']) ??
          effectiveSubscriptionForAppFrom(
            subscriptions,
            defaultAppId,
          )?.nextChargeAt,
      subscriptions: subscriptions,
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now().toUtc(),
    );
  }

  /// To JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'name': name,
      'email': email,
      'passwordHash': passwordHash,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (referralCode != null) 'referralCode': referralCode,
      if (appliedReferralCode != null)
        'appliedReferralCode': appliedReferralCode,
      if (referredByUserId != null) 'referredByUserId': referredByUserId,
      if (referralAppliedAt != null)
        'referralAppliedAt': referralAppliedAt!.toIso8601String(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'balance': balance,
      'requestBalance': requestBalance,
      'requestBalances': requestBalances.map((item) => item.toJson()).toList(),
      if (subscriptionExpiresAt != null)
        'subscriptionExpiresAt': subscriptionExpiresAt!.toIso8601String(),
      'subscriptionAutoRenewEnabled': subscriptionAutoRenewEnabled,
      if (subscriptionNextChargeAt != null)
        'subscriptionNextChargeAt': subscriptionNextChargeAt!.toIso8601String(),
      'subscriptions': subscriptions.map((item) => item.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  bool get hasActiveSubscription => hasActiveSubscriptionForApp(defaultAppId);

  bool hasActiveSubscriptionForApp(String appId) {
    return effectiveSubscriptionForApp(appId)?.isActive ?? false;
  }

  UserSubscription? subscriptionFor({
    required String scope,
    required String appId,
  }) {
    final normalizedScope = UserSubscription._normalizeScope(scope);
    final normalizedAppId = UserSubscription._normalizeAppId(appId);
    for (final subscription in subscriptions) {
      if (subscription.scope == normalizedScope &&
          subscription.appId == normalizedAppId) {
        return subscription;
      }
    }
    return null;
  }

  UserSubscription? effectiveSubscriptionForApp(String appId) {
    return effectiveSubscriptionForAppFrom(subscriptions, appId);
  }

  int effectiveRequestBalanceForApp(String appId) {
    return effectiveRequestBalanceForAppFrom(requestBalances, appId);
  }

  /// To public JSON (without sensitive data)
  Map<String, dynamic> toPublicJson({String appId = defaultAppId}) {
    final normalizedAppId = UserSubscription._normalizeAppId(appId);
    final effectiveSubscription = effectiveSubscriptionForApp(normalizedAppId);
    final effectiveRequestBalance = effectiveRequestBalanceForApp(
      normalizedAppId,
    );

    return {
      '_id': id?.oid,
      'name': name,
      'email': email,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (referralCode != null) 'referralCode': referralCode,
      if (appliedReferralCode != null)
        'appliedReferralCode': appliedReferralCode,
      if (referredByUserId != null) 'referredByUserId': referredByUserId!.oid,
      if (referralAppliedAt != null)
        'referralAppliedAt': referralAppliedAt!.toIso8601String(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'balance': balance,
      'appId': normalizedAppId,
      'app_id': normalizedAppId,
      'requestBalance': effectiveRequestBalance,
      'requestBalances': requestBalances
          .map((item) => item.toPublicJson())
          .toList(),
      if (effectiveSubscription?.expiresAt != null)
        'subscriptionExpiresAt': effectiveSubscription!.expiresAt!
            .toIso8601String(),
      'hasActiveSubscription': effectiveSubscription?.isActive ?? false,
      'subscriptionAutoRenewEnabled':
          effectiveSubscription?.autoRenewEnabled ?? false,
      if (effectiveSubscription?.nextChargeAt != null)
        'subscriptionNextChargeAt': effectiveSubscription!.nextChargeAt!
            .toIso8601String(),
      'subscriptions': subscriptions
          .map((item) => item.toPublicJson())
          .toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Copy with
  User copyWith({
    ObjectId? id,
    String? name,
    String? email,
    String? passwordHash,
    String? phoneNumber,
    String? referralCode,
    String? appliedReferralCode,
    ObjectId? referredByUserId,
    DateTime? referralAppliedAt,
    String? avatarUrl,
    double? balance,
    int? requestBalance,
    List<UserRequestBalance>? requestBalances,
    DateTime? subscriptionExpiresAt,
    bool? subscriptionAutoRenewEnabled,
    DateTime? subscriptionNextChargeAt,
    List<UserSubscription>? subscriptions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      referralCode: referralCode ?? this.referralCode,
      appliedReferralCode: appliedReferralCode ?? this.appliedReferralCode,
      referredByUserId: referredByUserId ?? this.referredByUserId,
      referralAppliedAt: referralAppliedAt ?? this.referralAppliedAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      balance: balance ?? this.balance,
      requestBalance: requestBalance ?? this.requestBalance,
      requestBalances: requestBalances ?? this.requestBalances,
      subscriptionExpiresAt:
          subscriptionExpiresAt ?? this.subscriptionExpiresAt,
      subscriptionAutoRenewEnabled:
          subscriptionAutoRenewEnabled ?? this.subscriptionAutoRenewEnabled,
      subscriptionNextChargeAt:
          subscriptionNextChargeAt ?? this.subscriptionNextChargeAt,
      subscriptions: subscriptions ?? this.subscriptions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<UserSubscription> upsertSubscription(
    List<UserSubscription> subscriptions,
    UserSubscription next,
  ) {
    final result = <UserSubscription>[];
    var updated = false;
    for (final subscription in subscriptions) {
      if (subscription.scope == next.scope &&
          subscription.appId == next.appId) {
        result.add(next);
        updated = true;
      } else {
        result.add(subscription);
      }
    }
    if (!updated) {
      result.add(next);
    }
    return result;
  }

  static List<UserSubscription> removeSubscription(
    List<UserSubscription> subscriptions, {
    required String scope,
    required String appId,
  }) {
    final normalizedScope = UserSubscription._normalizeScope(scope);
    final normalizedAppId = UserSubscription._normalizeAppId(appId);
    return subscriptions
        .where(
          (item) =>
              item.scope != normalizedScope || item.appId != normalizedAppId,
        )
        .toList();
  }

  static UserSubscription? effectiveSubscriptionForAppFrom(
    List<UserSubscription> subscriptions,
    String appId,
  ) {
    final normalizedAppId = UserSubscription._normalizeAppId(appId);
    final activeSubscriptions = subscriptions
        .where((subscription) => subscription.isActiveForApp(normalizedAppId))
        .toList();
    if (activeSubscriptions.isEmpty) {
      return null;
    }

    activeSubscriptions.sort((left, right) {
      final leftPriority = left.isGlobal ? 1 : 0;
      final rightPriority = right.isGlobal ? 1 : 0;
      if (leftPriority != rightPriority) {
        return leftPriority.compareTo(rightPriority);
      }
      final leftExpiresAt =
          left.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightExpiresAt =
          right.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightExpiresAt.compareTo(leftExpiresAt);
    });
    return activeSubscriptions.first;
  }

  static int effectiveRequestBalanceForAppFrom(
    List<UserRequestBalance> requestBalances,
    String appId,
  ) {
    final normalizedAppId = UserSubscription._normalizeAppId(appId);
    var total = 0;
    for (final item in requestBalances) {
      if (item.balance <= 0) {
        continue;
      }
      if (item.isGlobal || item.appId == normalizedAppId) {
        total += item.balance;
      }
    }
    return total;
  }

  static List<UserRequestBalance> upsertRequestBalance(
    List<UserRequestBalance> requestBalances,
    UserRequestBalance next,
  ) {
    final result = <UserRequestBalance>[];
    var updated = false;
    for (final requestBalance in requestBalances) {
      if (requestBalance.scope == next.scope &&
          requestBalance.appId == next.appId) {
        if (next.balance > 0) {
          result.add(next);
        }
        updated = true;
      } else {
        result.add(requestBalance);
      }
    }
    if (!updated && next.balance > 0) {
      result.add(next);
    }
    return result;
  }

  static List<UserSubscription> _parseSubscriptions(Map<String, dynamic> json) {
    final rawSubscriptions = json['subscriptions'];
    if (rawSubscriptions is Iterable) {
      final parsed = rawSubscriptions
          .whereType<Map>()
          .map(
            (item) =>
                UserSubscription.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    final legacyExpiresAt = _parseDateTime(json['subscriptionExpiresAt']);
    if (legacyExpiresAt == null) {
      return const [];
    }

    return [
      UserSubscription(
        scope: subscriptionScopeApp,
        appId: defaultAppId,
        expiresAt: legacyExpiresAt,
        autoRenewEnabled: json['subscriptionAutoRenewEnabled'] == true,
        nextChargeAt: _parseDateTime(json['subscriptionNextChargeAt']),
        rebillId: _stringOrNull(json['subscriptionRebillId']),
        recurringPaymentId: _stringOrNull(
          json['subscriptionRecurringPaymentId'],
        ),
        recurringOrderId: _stringOrNull(json['subscriptionRecurringOrderId']),
        updatedAt: _parseDateTime(json['updatedAt']),
      ),
    ];
  }

  static List<UserRequestBalance> _parseRequestBalances(
    Map<String, dynamic> json,
  ) {
    final rawRequestBalances = json['requestBalances'];
    if (rawRequestBalances is Iterable) {
      final parsed = rawRequestBalances
          .whereType<Map>()
          .map(
            (item) =>
                UserRequestBalance.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    final legacyRequestBalance = (json['requestBalance'] as num?)?.toInt() ?? 0;
    if (legacyRequestBalance <= 0) {
      return const [];
    }

    return [
      UserRequestBalance(
        scope: subscriptionScopeApp,
        appId: defaultAppId,
        balance: legacyRequestBalance,
        updatedAt: _parseDateTime(json['updatedAt']),
      ),
    ];
  }

  /// Функция _parseObjectId: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа ObjectId?; это готовый результат для следующего шага программы.
  static ObjectId? _parseObjectId(dynamic value) {
    if (value is ObjectId) {
      return value;
    }

    final rawValue = value?.toString();
    if (rawValue == null || !ObjectId.isValidHexId(rawValue)) {
      return null;
    }

    return ObjectId.fromHexString(rawValue);
  }

  /// Функция _parseDateTime: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает значение типа DateTime?; это готовый результат для следующего шага программы.
  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value.toUtc();
    }

    final rawValue = value?.toString();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawValue)?.toUtc();
  }

  static DateTime? parseDateTimePublic(dynamic value) => _parseDateTime(value);

  static String? _stringOrNull(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}
