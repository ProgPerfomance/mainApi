// Этот файл: lib/src/router/account_billing_router.dart.
// Здесь собраны только маршруты общей учётной записи и биллинга.

import 'package:main_api/src/controller/user/user_auth_controller.dart';
import 'package:main_api/src/controller/user/user_billing_controller.dart';
import 'package:shelf_router/shelf_router.dart';

Router createAccountBillingRouter() {
  final router = Router();
  addAccountBillingRoutes(router);
  return router;
}

void addAccountBillingRoutes(Router router) {
  // Авторизация и профиль.
  router.post('/auth/register', UserAuthController.createAccount);
  router.post('/auth/login', UserAuthController.login);
  router.post(
    '/auth/password-reset/request',
    UserAuthController.requestPasswordReset,
  );
  router.post('/auth/password-reset/confirm', UserAuthController.resetPassword);
  router.post('/auth/profile', UserAuthController.getProfile);
  router.post('/auth/referral/apply', UserAuthController.applyReferralCode);
  router.post('/auth/referrals', UserAuthController.listReferrals);
  router.post('/auth/delete', UserAuthController.deleteAccount);

  // Деньги пользователя.
  router.post('/billing/deposit', UserBillingController.depositBalance);
  router.post('/billing/ai/prepare', UserBillingController.prepareAiRequest);
  router.post('/billing/ai/charge', UserBillingController.chargeAiRequest);
  router.get(
    '/billing/subscription',
    UserBillingController.getSubscriptionSettings,
  );
  router.post(
    '/billing/subscription/tbank/init',
    UserBillingController.initTBankSubscription,
  );
  router.post(
    '/billing/subscription/tbank/confirm',
    UserBillingController.confirmTBankSubscription,
  );
  router.post(
    '/billing/subscription/buy-balance',
    UserBillingController.buySubscriptionWithBalance,
  );
  router.post(
    '/billing/subscription/auto-renew/cancel',
    UserBillingController.cancelSubscriptionAutoRenew,
  );
  router.post(
    '/billing/tbank/notification',
    UserBillingController.handleTBankNotification,
  );
  router.get(
    '/billing/request-packages',
    UserBillingController.listRequestPackages,
  );
  router.post(
    '/billing/request-packages/buy-balance',
    UserBillingController.buyRequestPackageWithBalance,
  );
  router.post(
    '/billing/request-packages/tbank/init',
    UserBillingController.initTBankRequestPackage,
  );
  router.post(
    '/billing/request-packages/tbank/confirm',
    UserBillingController.confirmTBankRequestPackage,
  );
  router.post('/billing/tbank/init', UserBillingController.initTBankTopUp);
  router.post(
    '/billing/tbank/confirm',
    UserBillingController.confirmTBankTopUp,
  );
  router.post('/billing/history', UserBillingController.listTransactions);
  router.post('/billing/promo/apply', UserBillingController.applyPromoCode);
}
