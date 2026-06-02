// Этот файл: lib/src/router/admin_router.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:main_api/src/controller/admin/admin_auth_controller.dart';
import 'package:main_api/src/controller/admin/app_registry_admin_controller.dart';
import 'package:main_api/src/controller/admin/billing_admin_controller.dart';
import 'package:main_api/src/controller/admin/app_admin_controller.dart';
import 'package:main_api/src/controller/admin/promo_code_admin_controller.dart';
import 'package:main_api/src/controller/admin/user_admin_controller.dart';
import 'package:main_api/src/controller/admin/wish_admin_controller.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

// Роутер админки.
// Он обслуживает HTML-страницы админки и API, которыми эти страницы пользуются.
Handler createAdminRouter({String basePath = '/admin'}) {
  final router = Router();

  // Визуальная авторизация админки: вход, выход и переход на рабочую страницу.
  router.get('/', (Request request) => Response.found('$basePath/apps'));
  router.get('/login', AdminAuthController.loginPage);
  router.post('/login', AdminAuthController.login);
  router.get('/logout', AdminAuthController.logout);

  // Настройки приложения.
  router.get('/api/apps', AppRegistryAdminController.listApps);
  router.post('/api/apps', AppRegistryAdminController.createApp);
  router.get('/api/apps/<appId>', AppRegistryAdminController.getApp);
  router.put('/api/apps/<appId>', AppRegistryAdminController.updateApp);
  router.get('/api/app/version', AppAdminController.getVersionSettings);
  router.put('/api/app/version', AppAdminController.updateVersionSettings);

  // Настройки стоимости AI-запроса и реферального бонуса.
  router.get(
    '/api/billing/settings',
    BillingAdminController.getAiRequestSettings,
  );
  router.put(
    '/api/billing/settings',
    BillingAdminController.updateAiRequestSettings,
  );

  // История списаний за AI-запросы для админки.
  router.get(
    '/api/billing/charges',
    BillingAdminController.listAiRequestCharges,
  );
  router.get(
    '/api/billing/request-packages',
    BillingAdminController.listRequestPackages,
  );
  router.post(
    '/api/billing/request-packages',
    BillingAdminController.createRequestPackage,
  );
  router.put(
    '/api/billing/request-packages/<id>',
    BillingAdminController.updateRequestPackage,
  );
  router.delete(
    '/api/billing/request-packages/<id>',
    BillingAdminController.deleteRequestPackage,
  );
  router.get(
    '/api/subscriptions',
    BillingAdminController.listSubscriptionPlans,
  );
  router.post(
    '/api/subscriptions',
    BillingAdminController.createSubscriptionPlan,
  );
  router.put(
    '/api/subscriptions/<id>',
    BillingAdminController.updateSubscriptionPlan,
  );
  router.delete(
    '/api/subscriptions/<id>',
    BillingAdminController.deleteSubscriptionPlan,
  );

  // Пользователи и ручное изменение баланса через админку.
  router.get('/api/users', UserAdminController.listUsers);
  router.get('/api/users/<id>', UserAdminController.getUserProfile);
  router.put('/api/users/<id>', UserAdminController.updateUser);
  router.delete('/api/users/<id>', UserAdminController.deleteUser);
  router.put('/api/users/<id>/balance', UserAdminController.updateUserBalance);
  router.put(
    '/api/users/<id>/subscription',
    UserAdminController.updateUserSubscription,
  );
  router.delete(
    '/api/users/<id>/subscription',
    UserAdminController.clearUserSubscription,
  );

  // Промокоды: список, создание, обновление, удаление.
  router.get('/api/promo-codes', PromoCodeAdminController.listPromoCodes);
  router.post('/api/promo-codes', PromoCodeAdminController.createPromoCode);
  router.put('/api/promo-codes/<id>', PromoCodeAdminController.updatePromoCode);
  router.delete(
    '/api/promo-codes/<id>',
    PromoCodeAdminController.deletePromoCode,
  );

  // Заявки на желания и сами желания.
  router.get('/api/wish-requests', WishAdminController.listWishRequests);
  router.delete('/api/wish-requests', WishAdminController.clearWishRequests);
  router.delete(
    '/api/wish-requests/<id>',
    WishAdminController.deleteWishRequest,
  );
  router.get('/api/wishes', WishAdminController.listWishes);
  router.post('/api/wishes', WishAdminController.createWish);
  router.put('/api/wishes/<id>', WishAdminController.updateWish);
  router.delete('/api/wishes/<id>', WishAdminController.deleteWish);

  // Возвращаем готовый набор маршрутов серверу вместе с защитой доступа.
  return Pipeline()
      .addMiddleware(AdminAuthController.middleware(basePath: basePath))
      .addHandler(router.call);
}
