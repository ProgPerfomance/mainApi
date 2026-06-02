// Этот файл: test/kirill_api_test.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'dart:io';

import 'package:main_api/src/controller/admin/admin_auth_controller.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/character.dart';
import 'package:main_api/src/models/chat_message.dart';
import 'package:main_api/src/models/promo_code.dart';
import 'package:main_api/src/models/request_package.dart';
import 'package:main_api/src/models/transaction.dart';
import 'package:main_api/src/models/user.dart';
import 'package:main_api/src/models/wish.dart';
import 'package:main_api/src/models/wish_request.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/deepseek/rules.dart';
import 'package:main_api/src/services/tbank/tbank_payment_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Функция main: запускает приложение или сервер. Ничего не возвращает.
/// Ничего не возвращает, только выполняет действие.
void main() {
  setUpAll(() {
    final envFile = File('.test.env');
    envFile.writeAsStringSync(
      [
        'ADMIN_USERNAME=admin',
        'ADMIN_PASSWORD=test-admin-password',
        'JWT_SECRET=test-jwt-secret-that-is-long-enough-123',
      ].join('\n'),
    );
    AppConfig.loadEnv(['.test.env']);
    envFile.deleteSync();
  });

  test('response helper respects status code', () async {
    final response = ResponseHelper.success(
      statusCode: 201,
      data: {'ok': true},
    );

    expect(response.statusCode, 201);
    expect(jsonDecode(await response.readAsString()), {
      'status': 'success',
      'data': {'ok': true},
    });
  });

  test(
    'response helper includes structured error fields when provided',
    () async {
      final response = ResponseHelper.error(
        errorMessage: 'Insufficient balance for AI request',
        statusCode: 402,
        errorCode: 'INSUFFICIENT_BALANCE',
        details: {
          'currentBalance': 10.0,
          'requiredAmount': 49.0,
          'shortfall': 39.0,
        },
      );

      expect(response.statusCode, 402);
      expect(jsonDecode(await response.readAsString()), {
        'status': 'error',
        'errorMessage': 'Insufficient balance for AI request',
        'errorCode': 'INSUFFICIENT_BALANCE',
        'details': {
          'currentBalance': 10.0,
          'requiredAmount': 49.0,
          'shortfall': 39.0,
        },
      });
    },
  );

  test(
    'admin login invalid credentials render form without browser auth',
    () async {
      final response = await AdminAuthController.login(
        Request(
          'POST',
          Uri.parse('http://localhost/admin/login'),
          body: 'username=${AppConfig.adminUsername}&password=wrong-password',
        ),
      );

      expect(response.statusCode, 200);
      expect(response.headers, isNot(contains('www-authenticate')));
      expect(
        await response.readAsString(),
        contains('Неверный логин или пароль'),
      );
    },
  );

  test('chat message converts to deepseek payload', () {
    final message = ChatMessage(role: ChatMessageRole.user, content: 'Hello');

    expect(message.toDeepSeekMessage(), {'role': 'user', 'content': 'Hello'});
  });

  test('client chat message is serialized without server ids', () {
    final message = ChatMessage.fromClientJson({
      'role': 'assistant',
      'content': 'Hi there',
      'createdAt': '2026-04-17T10:20:30.000Z',
    });

    expect(message.toPublicJson(), {
      'role': 'assistant',
      'content': 'Hi there',
      'createdAt': '2026-04-17T10:20:30.000Z',
    });
  });

  test('user public json includes phone number when present', () {
    final user = User(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439011'),
      name: 'Ivan',
      email: 'ivan@example.com',
      passwordHash: 'hash',
      phoneNumber: '+79991234567',
    );

    expect(user.toPublicJson(), containsPair('phoneNumber', '+79991234567'));
  });

  test('user entitlements resolve app and global subscription scopes', () {
    final now = DateTime.now().toUtc();
    final user = User(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439012'),
      name: 'Ivan',
      email: 'ivan@example.com',
      passwordHash: 'hash',
      subscriptions: [
        UserSubscription(
          scope: User.subscriptionScopeGlobal,
          appId: User.globalAppId,
          expiresAt: now.add(const Duration(days: 30)),
        ),
        UserSubscription(
          scope: User.subscriptionScopeApp,
          appId: 'psychology',
          expiresAt: now.add(const Duration(days: 10)),
        ),
      ],
      requestBalances: [
        UserRequestBalance(
          scope: User.subscriptionScopeApp,
          appId: 'psychology',
          balance: 3,
        ),
        UserRequestBalance(
          scope: User.subscriptionScopeGlobal,
          appId: User.globalAppId,
          balance: 5,
        ),
        UserRequestBalance(
          scope: User.subscriptionScopeApp,
          appId: 'fitness',
          balance: 7,
        ),
      ],
    );

    final psychologyJson = user.toPublicJson(appId: 'psychology');
    final fitnessJson = user.toPublicJson(appId: 'fitness');

    expect(psychologyJson['hasActiveSubscription'], isTrue);
    expect(psychologyJson['requestBalance'], 8);
    expect(fitnessJson['hasActiveSubscription'], isTrue);
    expect(fitnessJson['requestBalance'], 12);
    expect(psychologyJson['subscriptions'], hasLength(2));
    expect(psychologyJson['requestBalances'], hasLength(3));
  });

  test('request package public json exposes app id and scope', () {
    final package = RequestPackage(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439013'),
      requestCount: 100,
      price: 799,
      appId: 'psychology',
      scope: 'app',
    );

    expect(package.toPublicJson(), containsPair('appId', 'psychology'));
    expect(package.toPublicJson(), containsPair('app_id', 'psychology'));
    expect(package.toPublicJson(), containsPair('scope', 'app'));
  });

  test('promo code parses Mongo DateTime fields', () {
    final createdAt = DateTime.utc(2026, 5, 11, 10, 0);
    final updatedAt = DateTime.utc(2026, 5, 11, 10, 5);
    final redeemedAt = DateTime.utc(2026, 5, 11, 10, 10);

    final promoCode = PromoCode.fromJson({
      '_id': ObjectId.fromHexString('507f1f77bcf86cd799439014'),
      'code': 'TEST100',
      'amount': 100,
      'isActive': true,
      'redemptions': [
        {
          'userId': ObjectId.fromHexString('507f1f77bcf86cd799439015'),
          'redeemedAt': redeemedAt,
        },
      ],
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    });

    expect(promoCode.createdAt, createdAt);
    expect(promoCode.updatedAt, updatedAt);
    expect(promoCode.redemptions.single.redeemedAt, redeemedAt);
  });

  test('promo code parses string user id in redemptions', () {
    final promoCode = PromoCode.fromJson({
      '_id': ObjectId.fromHexString('507f1f77bcf86cd799439014'),
      'code': 'TEST100',
      'amount': 100,
      'redemptions': [
        {
          'userId': '507f1f77bcf86cd799439015',
          'redeemedAt': DateTime.utc(2026, 5, 11, 10, 10),
        },
      ],
      'createdAt': DateTime.utc(2026, 5, 11, 10, 0),
      'updatedAt': DateTime.utc(2026, 5, 11, 10, 5),
    });

    expect(promoCode.redemptions.single.userId.oid, '507f1f77bcf86cd799439015');
  });

  test('character public json exposes configured fields', () {
    final character = Character(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439021'),
      name: 'Mentor',
      avatarUrl: 'https://example.com/avatar.png',
      systemPrompt: 'You are calm and clear.',
      shortDescription: 'Short hello.',
      longDescription: 'Long hello.',
    );

    expect(character.toPublicJson(), {
      '_id': '507f1f77bcf86cd799439021',
      'name': 'Mentor',
      'avatarUrl': 'https://example.com/avatar.png',
      'systemPrompt': 'You are calm and clear.',
      'shortDescription': 'Short hello.',
      'longDescription': 'Long hello.',
      'createdAt': character.createdAt.toIso8601String(),
      'updatedAt': character.updatedAt.toIso8601String(),
    });
  });

  test('character public json localizes name and descriptions', () {
    final character = Character(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439022'),
      name: 'Психолог',
      avatarUrl: 'https://example.com/avatar.png',
      systemPrompt: 'You are calm and clear.',
      shortDescription: 'Коротко.',
      longDescription: 'Подробно.',
      localizedNames: const {'en': 'Psychologist', 'be': 'Псіхолаг'},
      localizedShortDescriptions: const {'en': 'Short.', 'be': 'Каротка.'},
      localizedLongDescriptions: const {'en': 'Long.', 'be': 'Падрабязна.'},
    );

    final englishJson = character.toPublicJson(languageCode: 'en');
    expect(englishJson['name'], 'Psychologist');
    expect(englishJson['shortDescription'], 'Short.');
    expect(englishJson['longDescription'], 'Long.');
  });

  test('transaction public json exposes optional user name', () {
    final transaction = Transaction(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439031'),
      userId: ObjectId.fromHexString('507f1f77bcf86cd799439011'),
      userName: 'Ivan',
      amount: 49.9,
      type: TransactionType.payment,
      description: 'AI request charge',
    );

    expect(transaction.toPublicJson(), containsPair('userName', 'Ivan'));
    expect(transaction.toPublicJson(), containsPair('amount', 49.9));
    expect(transaction.toPublicJson(), containsPair('type', 'payment'));
  });

  test('billing session prices follow product ladder', () {
    expect(BillingService.priceForSessionRequestIndex(1), 299);
    expect(BillingService.priceForSessionRequestIndex(2), 149);
    expect(BillingService.priceForSessionRequestIndex(3), 99);
    expect(BillingService.priceForSessionRequestIndex(10), 99);
  });

  test('top-up bonus adds ten percent to credited amount', () {
    expect(BillingService.topUpBonusAmount(299), 29.9);
    expect(BillingService.creditedTopUpAmount(299), 328.9);
  });

  test('wish request public json exposes author and text', () {
    final wishRequest = WishRequest(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439041'),
      userId: ObjectId.fromHexString('507f1f77bcf86cd799439011'),
      appId: 'psychology',
      text: 'Добавьте подборки по темам',
    );

    expect(wishRequest.toPublicJson(), {
      '_id': '507f1f77bcf86cd799439041',
      'userId': '507f1f77bcf86cd799439011',
      'appId': 'psychology',
      'app_id': 'psychology',
      'text': 'Добавьте подборки по темам',
      'createdAt': wishRequest.createdAt.toIso8601String(),
      'updatedAt': wishRequest.updatedAt.toIso8601String(),
    });
  });

  test('wish public json exposes counters and source request', () {
    final wish = Wish(
      id: ObjectId.fromHexString('507f1f77bcf86cd799439051'),
      requestId: ObjectId.fromHexString('507f1f77bcf86cd799439041'),
      appId: 'psychology',
      text: 'Сделать напоминания о практике',
      likeCount: 12,
      dislikeCount: 3,
    );

    expect(wish.toPublicJson(), {
      '_id': '507f1f77bcf86cd799439051',
      'requestId': '507f1f77bcf86cd799439041',
      'appId': 'psychology',
      'app_id': 'psychology',
      'text': 'Сделать напоминания о практике',
      'likeCount': 12,
      'dislikeCount': 3,
      'createdAt': wish.createdAt.toIso8601String(),
      'updatedAt': wish.updatedAt.toIso8601String(),
    });
  });

  test('wishes parse string ids from old database rows', () {
    final wishRequest = WishRequest.fromJson({
      '_id': ObjectId.fromHexString('507f1f77bcf86cd799439041'),
      'userId': '507f1f77bcf86cd799439011',
      'appId': 'callories',
      'text': 'Добавьте отчёты за неделю',
    });
    final wish = Wish.fromJson({
      '_id': ObjectId.fromHexString('507f1f77bcf86cd799439051'),
      'requestId': '507f1f77bcf86cd799439041',
      'appId': 'callories',
      'text': 'Сделать экспорт анализа',
    });

    expect(wishRequest.userId?.oid, '507f1f77bcf86cd799439011');
    expect(wish.requestId?.oid, '507f1f77bcf86cd799439041');
  });

  test('wish reaction parser supports like and dislike only', () {
    expect(WishReaction.parse('like'), WishReaction.like);
    expect(WishReaction.parse('dislike'), WishReaction.dislike);
    expect(WishReaction.parseNullable(null), isNull);
    expect(() => WishReaction.parse('heart'), throwsA(isA<FormatException>()));
  });

  test('wish reaction switching recalculates counters safely', () {
    final wish = Wish(
      appId: 'psychology',
      likeCount: 10,
      dislikeCount: 4,
      text: 'Добавить медитации',
    );

    final switchedWish = wish.applyReaction(
      reaction: WishReaction.dislike,
      previousReaction: WishReaction.like,
      reactedAt: DateTime.utc(2026, 4, 22, 10, 0),
    );

    expect(switchedWish.likeCount, 9);
    expect(switchedWish.dislikeCount, 5);
    expect(switchedWish.updatedAt, DateTime.utc(2026, 4, 22, 10, 0));
  });

  test('deepseek language instruction supports app locales only', () {
    expect(
      deepSeekLanguageInstructionForCode('ru'),
      contains('Reply in Russian'),
    );
    expect(
      deepSeekLanguageInstructionForCode('en'),
      contains('Reply in English'),
    );
    expect(
      deepSeekLanguageInstructionForCode('be'),
      contains('Reply in Belarusian'),
    );
    expect(deepSeekLanguageInstructionForCode('de'), isNull);
  });

  test('tbank token uses only root request fields', () {
    final token = TBankPaymentService.makeToken({
      'TerminalKey': 'MerchantTerminalKey',
      'Amount': 19200,
      'OrderId': '00000',
      'Description': 'Подарочная карта на 1000 рублей',
      'DATA': {'Phone': '+71234567890'},
      'Receipt': {
        'Items': [
          {'Name': 'Товар', 'Amount': 19200},
        ],
      },
    }, '11111111111111');

    expect(
      token,
      '72dd466f8ace0a37a1f740ce5fb78101712bc0665d91a8108c7c8a0ccd426db2',
    );
  });
}
