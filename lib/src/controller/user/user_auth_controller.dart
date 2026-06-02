// Этот файл: lib/src/controller/user/user_auth_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/auth/jwt_service.dart';
import 'package:main_api/src/services/auth/password_reset_mailer.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/referral/referral_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

// UserAuthController принимает HTTP-запросы по аккаунту пользователя:
// регистрация, логин, профиль и применение реферального кода.
class UserAuthController {
  /// Создать новый аккаунт.
  static Future<Response> createAccount(Request request) async {
    try {
      // Все auth-эндпоинты читают JSON-тело через общий helper,
      // чтобы валидация и ошибки парсинга были единообразными.
      Map<String, dynamic> data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(data);

      // Здесь базовая валидация обязательных полей.
      //
      // Это именно "ранняя" проверка на уровне контроллера:
      // если нет имени / email / пароля, нет смысла идти в базу.
      if (data['name'] == null || data['name'].toString().isEmpty) {
        return ResponseHelper.error(errorMessage: 'Name is required');
      }
      final email = data['email']?.toString().trim().toLowerCase() ?? '';
      if (email.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Email is required');
      }
      if (!_isValidEmail(email)) {
        return ResponseHelper.error(errorMessage: 'Invalid email format');
      }
      if (data['password'] == null || data['password'].toString().isEmpty) {
        return ResponseHelper.error(errorMessage: 'Password is required');
      }

      final db = MongoService.instance.db;
      final usersCollection = db.collection(Collections.users);

      // Email нормализуем в lowercase и при записи, и при поиске.
      // Это исключает дубли аккаунтов с разным регистром символов.
      final existingUser = await usersCollection.findOne(
        where.eq('email', email),
      );

      if (existingUser != null) {
        return ResponseHelper.error(
          errorMessage: 'User with this email already exists',
          statusCode: 409,
        );
      }

      // Сам пароль в базе никогда не хранится "как есть".
      //
      // Вместо этого:
      // 1. Берём строку пароля
      // 2. Прогоняем через хеш-функцию
      // 3. Сохраняем только хеш
      //
      // Зачем:
      // если база когда-нибудь утечёт, raw-паролей там не будет.
      final passwordHash = _hashPassword(data['password'].toString());
      final appliedReferralCode =
          data['appliedReferralCode']?.toString() ??
          data['referralCode']?.toString();

      // В ответ клиенту вернётся public-представление пользователя без passwordHash.
      final user = User(
        name: data['name'].toString(),
        email: email,
        passwordHash: passwordHash,
        phoneNumber: data['phoneNumber']?.toString(),
        referralCode: await ReferralService.instance
            .generateUniqueReferralCode(),
        avatarUrl: data['avatarUrl']?.toString(),
        // Новому пользователю сразу даём 300 ₽.
        // Этого хватает на первый AI-запрос за 299 ₽, чтобы человек
        // мог попробовать сервис без обязательной оплаты.
        balance: BillingService.startingBalanceAmount,
      );

      // После insert перечитываем документ из базы.
      //
      // Это чуть длиннее, чем просто вернуть локальный объект user, зато:
      // - в ответе гарантированно будет настоящий _id от MongoDB
      // - клиент увидит документ ровно в том виде, как он лежит в базе
      final result = await usersCollection.insertOne(user.toJson());

      if (result.isSuccess) {
        final insertedUser = await usersCollection.findOne(
          where.eq('_id', result.id),
        );

        if (insertedUser != null) {
          var userModel = User.fromJson(insertedUser);
          try {
            /// Функция _saveStartingBalanceTransaction: сохраняет данные. Обычно возвращает подтверждение или просто завершает работу.
            /// Возвращает значение типа await; это готовый результат для следующего шага программы.
            await _saveStartingBalanceTransaction(userModel);
            userModel = await BillingService.instance
                .ensureStartingAppRequestBalance(
                  userId: userModel.id!,
                  appId: appId,
                );
          } catch (_) {
            await _rollbackCreatedAccount(db, userModel);
            rethrow;
          }

          if ((appliedReferralCode ?? '').trim().isNotEmpty &&
              userModel.id != null) {
            try {
              userModel = await ReferralService.instance.applyReferralCode(
                userId: userModel.id!,
                rawReferralCode: appliedReferralCode!,
              );
            } on ReferralServiceException {
              await _rollbackCreatedAccount(db, userModel);
              rethrow;
            }
          }
          return ResponseHelper.success(
            data: {
              ...userModel.toPublicJson(appId: appId),
              'token': JwtService.instance.issueToken(userId: userModel.id!),
            },
          );
        }
      }

      return ResponseHelper.error(
        errorMessage: 'Failed to create account',
        statusCode: 500,
      );
    } on ReferralServiceException catch (e) {
      return ResponseHelper.error(
        errorMessage: e.message,
        statusCode: e.statusCode,
        errorCode: e.errorCode,
      );
    } catch (e) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Войти в аккаунт.
  /// Сейчас login возвращает userId и JWT-токен для защищённых запросов.
  static Future<Response> login(Request request) async {
    try {
      Map<String, dynamic> data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(data);

      // Для логина обязательны только email и пароль.
      final email = data['email']?.toString().trim().toLowerCase() ?? '';
      if (email.isEmpty) {
        _logLoginFailure(email: email, appId: appId, reason: 'missing_email');
        return ResponseHelper.error(errorMessage: 'Email is required');
      }
      if (!_isValidEmail(email)) {
        _logLoginFailure(email: email, appId: appId, reason: 'invalid_email');
        return ResponseHelper.error(errorMessage: 'Invalid email format');
      }
      if (data['password'] == null || data['password'].toString().isEmpty) {
        _logLoginFailure(
          email: email,
          appId: appId,
          reason: 'missing_password',
        );
        return ResponseHelper.error(errorMessage: 'Password is required');
      }

      final db = MongoService.instance.db;
      final usersCollection = db.collection(Collections.users);

      // Здесь работает схема авторизации с JWT:
      // - клиент присылает email и пароль
      // - сервер проверяет их
      // - в ответ возвращаются userId и токен сессии
      //
      // Почему именно так:
      // мобильный клиент хранит userId для удобства профиля,
      // а JWT отправляет в Authorization для защищённых действий.
      final userData = await usersCollection.findOne(where.eq('email', email));

      if (userData == null) {
        _logLoginFailure(
          email: email,
          appId: appId,
          reason: 'user_not_found',
          statusCode: 401,
        );
        return ResponseHelper.error(
          errorMessage: 'Invalid email or password',
          statusCode: 401,
        );
      }

      var user = User.fromJson(userData);
      if (user.passwordHash.isEmpty) {
        _logLoginFailure(
          email: email,
          appId: appId,
          reason: 'missing_password_hash',
          statusCode: 401,
        );
        return ResponseHelper.error(
          errorMessage: 'Invalid email or password',
          statusCode: 401,
        );
      }

      // При логине пароль тоже не сравнивается "в лоб".
      //
      // Мы:
      // 1. Берём пароль из запроса
      // 2. Считаем для него хеш тем же алгоритмом
      // 3. Сравниваем уже два хеша
      final passwordHash = _hashPassword(data['password'].toString());
      if (passwordHash != user.passwordHash) {
        _logLoginFailure(
          email: email,
          appId: appId,
          reason: 'wrong_password',
          statusCode: 401,
        );
        return ResponseHelper.error(
          errorMessage: 'Invalid email or password',
          statusCode: 401,
        );
      }

      user = await BillingService.instance.ensureStartingAppRequestBalance(
        userId: user.id!,
        appId: appId,
      );

      // Возвращаем идентификатор и JWT:
      // - _id нужен приложению для текущего профиля
      // - token подтверждает вход при следующих запросах
      return ResponseHelper.success(
        data: {
          '_id': user.id?.oid,
          'token': JwtService.instance.issueToken(userId: user.id!),
          'requestBalance': user.effectiveRequestBalanceForApp(appId),
        },
      );
    } catch (e) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  static void _logLoginFailure({
    required String email,
    required String appId,
    required String reason,
    int statusCode = 400,
  }) {
    print(
      'AUTH_LOGIN_FAILED ${jsonEncode({'email': email, 'appId': appId, 'reason': reason, 'statusCode': statusCode, 'createdAt': DateTime.now().toUtc().toIso8601String()})}',
    );
  }

  static Future<Response> requestPasswordReset(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(data);
      final email = data['email']?.toString().trim().toLowerCase() ?? '';
      if (email.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Email is required');
      }
      if (!_isValidEmail(email)) {
        return ResponseHelper.error(errorMessage: 'Invalid email format');
      }

      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(where.eq('email', email));

      // Не раскрываем, существует ли email в базе.
      if (userData == null) {
        return ResponseHelper.success(data: {'sent': true});
      }

      final lastRequestedAt = User.parseDateTimePublic(
        userData['passwordResetRequestedAt'],
      );
      final now = DateTime.now().toUtc();
      final minInterval = Duration(
        seconds: AppConfig.passwordResetMinIntervalSeconds,
      );
      if (lastRequestedAt != null &&
          now.difference(lastRequestedAt) < minInterval) {
        return ResponseHelper.success(data: {'sent': true});
      }

      final code = _generateResetCode();
      final expiresAt = now.add(
        Duration(minutes: AppConfig.passwordResetCodeTtlMinutes),
      );
      await usersCollection.updateOne(
        where.eq('_id', userData['_id']),
        modify
            .set('passwordResetCodeHash', _hashPasswordResetCode(email, code))
            .set('passwordResetExpiresAt', expiresAt.toIso8601String())
            .set('passwordResetRequestedAt', now.toIso8601String())
            .set('updatedAt', now.toIso8601String()),
      );

      await PasswordResetMailer.instance.sendResetCode(
        email: email,
        code: code,
        appId: appId,
      );

      return ResponseHelper.success(data: {'sent': true});
    } catch (e) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> resetPassword(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final email = data['email']?.toString().trim().toLowerCase() ?? '';
      final code = data['code']?.toString().trim() ?? '';
      final password = data['password']?.toString() ?? '';

      if (email.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Email is required');
      }
      if (!_isValidEmail(email)) {
        return ResponseHelper.error(errorMessage: 'Invalid email format');
      }
      if (!_isValidResetCode(code)) {
        return ResponseHelper.error(errorMessage: 'Invalid reset code');
      }
      if (password.length < 6) {
        return ResponseHelper.error(
          errorMessage: 'Password must contain at least 6 characters',
        );
      }

      final usersCollection = MongoService.instance.db.collection(
        Collections.users,
      );
      final userData = await usersCollection.findOne(where.eq('email', email));
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'Invalid reset code',
          statusCode: 400,
        );
      }

      final expiresAt = User.parseDateTimePublic(
        userData['passwordResetExpiresAt'],
      );
      final expectedHash = userData['passwordResetCodeHash']?.toString();
      final actualHash = _hashPasswordResetCode(email, code);
      if (expiresAt == null ||
          expiresAt.isBefore(DateTime.now().toUtc()) ||
          expectedHash == null ||
          expectedHash != actualHash) {
        return ResponseHelper.error(
          errorMessage: 'Invalid reset code',
          statusCode: 400,
        );
      }

      final now = DateTime.now().toUtc();
      await usersCollection.updateOne(
        where.eq('_id', userData['_id']),
        modify
            .set('passwordHash', _hashPassword(password))
            .set('passwordResetCodeHash', null)
            .set('passwordResetExpiresAt', null)
            .set('passwordResetRequestedAt', null)
            .set('updatedAt', now.toIso8601String()),
      );

      return ResponseHelper.success(data: {'reset': true});
    } catch (e) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Получить профиль пользователя.
  static Future<Response> getProfile(Request request) async {
    try {
      Map<String, dynamic> data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(data);

      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );

      final db = MongoService.instance.db;
      final usersCollection = db.collection(Collections.users);

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
      var ensuredUser = await ReferralService.instance.ensureUserReferralCode(
        user,
      );
      ensuredUser = await BillingService.instance
          .ensureStartingAppRequestBalance(
            userId: ensuredUser.id!,
            appId: appId,
          );
      return ResponseHelper.success(
        data: ensuredUser.toPublicJson(appId: appId),
      );
    } on ReferralServiceException catch (e) {
      return ResponseHelper.error(
        errorMessage: e.message,
        statusCode: e.statusCode,
        errorCode: e.errorCode,
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

  /// Применить реферальный код один раз для существующего пользователя.
  static Future<Response> applyReferralCode(Request request) async {
    try {
      // Читаем JSON из запроса.
      final data = await parseRequestDataHelper(request);
      final appId = _resolveAppId(data);

      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );

      // Клиент может прислать код под старым или новым именем поля.
      // Поддерживаем оба варианта ради совместимости.
      final referralCode =
          data['appliedReferralCode']?.toString() ??
          data['referralCode']?.toString();
      if (referralCode == null || referralCode.trim().isEmpty) {
        return ResponseHelper.error(errorMessage: 'Referral code is required');
      }

      // Сервис сам проверит код, запретит самоприглашение
      // и начислит бонус пригласившему пользователю.
      final user = await ReferralService.instance.applyReferralCode(
        userId: userObjectId,
        rawReferralCode: referralCode,
      );

      // Возвращаем обновлённый публичный профиль пользователя.
      return ResponseHelper.success(data: user.toPublicJson(appId: appId));
    } on ReferralServiceException catch (e) {
      // Ожидаемые ошибки рефералок возвращаем как обычный API-ответ.
      return ResponseHelper.error(
        errorMessage: e.message,
        statusCode: e.statusCode,
        errorCode: e.errorCode,
      );
    } on JwtAuthException catch (e) {
      return ResponseHelper.error(
        errorMessage: e.message,
        statusCode: e.statusCode,
      );
    } catch (e) {
      // Неожиданная ошибка сервера.
      return ResponseHelper.error(
        errorMessage: 'Internal server error: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  static Future<Response> deleteAccount(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final userObjectId = JwtService.instance.resolveUserId(
        request,
        data['userId']?.toString(),
      );

      final db = MongoService.instance.db;
      final usersCollection = db.collection(Collections.users);
      final userData = await usersCollection.findOne(
        where.eq('_id', userObjectId),
      );
      if (userData == null) {
        return ResponseHelper.error(
          errorMessage: 'User not found',
          statusCode: 404,
        );
      }

      final deleteResult = await usersCollection.deleteOne(
        where.eq('_id', userObjectId),
      );
      if (!deleteResult.isSuccess || deleteResult.nRemoved == 0) {
        return ResponseHelper.error(
          errorMessage: 'Failed to delete account',
          statusCode: 500,
        );
      }

      await db
          .collection(Collections.transactions)
          .deleteMany(where.eq('userId', userObjectId));
      await db
          .collection(Collections.tbankPayments)
          .deleteMany(where.eq('userId', userObjectId));
      await db
          .collection(Collections.wishRequests)
          .deleteMany(where.eq('userId', userObjectId));
      await usersCollection.updateMany(
        where.eq('referredByUserId', userObjectId),
        modify
            .set('referredByUserId', null)
            .set('appliedReferralCode', null)
            .set('referralAppliedAt', null)
            .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
      );

      return ResponseHelper.success(data: {'deleted': true});
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

  /// Хеширование пароля через SHA-256.
  static const String _startingBalanceDescription = 'Starting balance bonus';

  static bool _isValidEmail(String email) {
    if (email.length > 254 || RegExp(r'\s').hasMatch(email)) {
      return false;
    }

    final parts = email.split('@');
    if (parts.length != 2) {
      return false;
    }

    final localPart = parts[0];
    final domain = parts[1];
    if (localPart.isEmpty ||
        localPart.length > 64 ||
        domain.isEmpty ||
        domain.length > 253 ||
        domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.contains('..')) {
      return false;
    }

    final labels = domain.split('.');
    if (labels.length < 2 || labels.last.length < 2) {
      return false;
    }

    final localPattern = RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+$");
    final domainLabelPattern = RegExp(
      r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
    );
    return localPattern.hasMatch(localPart) &&
        labels.every(domainLabelPattern.hasMatch);
  }

  /// Функция _saveStartingBalanceTransaction: сохраняет данные. Обычно возвращает подтверждение или просто завершает работу.
  /// Возвращает ожидание завершения работы, но не возвращает отдельное значение.
  static Future<void> _saveStartingBalanceTransaction(User user) async {
    if (user.id == null || BillingService.startingBalanceAmount <= 0) {
      return;
    }

    final transaction = Transaction(
      userId: user.id!,
      userName: user.name,
      amount: BillingService.startingBalanceAmount,
      type: TransactionType.deposit,
      description: _startingBalanceDescription,
      metadata: {'provider': 'starting_balance', 'reason': 'new_user_trial'},
      createdAt: DateTime.now().toUtc(),
    );

    final result = await MongoService.instance.db
        .collection(Collections.transactions)
        .insertOne(transaction.toJson());

    if (!result.isSuccess) {
      /// Функция StateError: выполняет шаг StateError в этой части программы. Возвращает значение типа throw; это готовый результат для следующего шага программы.
      /// Возвращает значение типа throw; это готовый результат для следующего шага программы.
      throw StateError('Failed to save starting balance transaction');
    }
  }

  static Future<void> _rollbackCreatedAccount(Db db, User user) async {
    final userId = user.id;
    if (userId == null) {
      return;
    }
    await db
        .collection(Collections.transactions)
        .deleteMany(where.eq('userId', userId));
    await db.collection(Collections.users).deleteOne(where.eq('_id', userId));
  }

  /// Хеширование пароля через SHA-256.
  static String _hashPassword(String password) {
    // Хеширование вынесено в одно место, чтобы регистрация и логин
    // использовали идентичный алгоритм без расхождения по реализации.
    //
    // Алгоритм простой:
    // - password string -> utf8 bytes
    // - bytes -> sha256 hash
    // - hash -> hex string
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  static String _generateResetCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  static bool _isValidResetCode(String code) {
    return RegExp(r'^\d{6}$').hasMatch(code);
  }

  static String _hashPasswordResetCode(String email, String code) {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedCode = code.trim();
    final bytes = utf8.encode(
      '$normalizedEmail:$normalizedCode:${AppConfig.passwordResetSecret}',
    );
    return sha256.convert(bytes).toString();
  }

  static String _resolveAppId(Map<String, dynamic> data) {
    return BillingService.normalizeAppId(
      data['appId']?.toString() ?? data['app_id']?.toString(),
    );
  }
}
