// Этот файл: lib/src/router/client_router.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/controller/app/app_controller.dart';
import 'package:main_api/src/controller/wish/wish_controller.dart';
import 'package:main_api/src/controller/wish/wish_request_controller.dart';
import 'package:main_api/src/router/account_billing_router.dart';
import 'package:main_api/src/services/account_billing/account_billing_proxy.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:shelf_router/shelf_router.dart';

/// Роутер пользовательского API.
/// Здесь описано: какой URL вызывает какой controller.
Router createClientRouter() {
  // Создаём пустой роутер и ниже добавляем в него маршруты.
  final router = Router();

  // Публичные настройки приложения.
  router.get('/app/version', AppController.getVersionSettings);

  // Auth/billing вынесены в отдельный сервис. Без внешнего URL оставляем
  // локальные маршруты, чтобы старый dev-режим и тесты не ломались.
  if (AppConfig.accountBillingServiceUrl == null) {
    addAccountBillingRoutes(router);
  } else {
    router.all('/auth/<path|.*>', AccountBillingProxy.instance.forward);
    router.all('/billing/<path|.*>', AccountBillingProxy.instance.forward);
  }

  // Желания/заявки на желания.
  router.post('/wishes/requests', WishRequestController.createWishRequest);
  router.get('/wishes', WishController.listWishes);
  router.post('/wishes/<id>/reaction', WishController.reactToWish);

  // Возвращаем готовый роутер серверу.
  return router;
}
