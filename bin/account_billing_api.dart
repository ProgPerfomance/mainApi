// Этот файл: bin/account_billing_api.dart.
// Отдельный backend общей учётной записи, баланса, подписок и оплат.

import 'dart:io';

import 'package:main_api/src/router/account_billing_router.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/billing/recurring_subscription_service.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

void main(List<String> arguments) async {
  AppConfig.loadEnv();

  try {
    await MongoService.instance.connect(AppConfig.mongoUri);
    print('MongoDB connected successfully');
  } catch (error) {
    print('Failed to connect to MongoDB: $error');
    exit(1);
  }

  RecurringSubscriptionService.instance.start();

  final app = Router();
  app.mount('/api/v1/', createAccountBillingRouter().call);
  app.get('/health', (Request request) => Response.ok('OK'));

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsHeaders())
      .addHandler(app.call);

  final server = await HttpServer.bind('0.0.0.0', AppConfig.accountBillingPort);
  server.listen((request) async {
    await io.handleRequest(request, handler);
  });

  print(
    'Account billing server running on '
    'http://${server.address.host}:${server.port}',
  );
}

Middleware _corsHeaders() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(
          '',
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers':
                'Origin, Content-Type, Accept, Authorization, X-App-Id, X-Subscription-Scope',
          },
        );
      }

      final response = await handler(request);
      return response.change(
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers':
              'Origin, Content-Type, Accept, Authorization, X-App-Id, X-Subscription-Scope',
        },
      );
    };
  };
}
