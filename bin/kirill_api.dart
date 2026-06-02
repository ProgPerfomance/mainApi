// Этот файл: bin/kirill_api.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:main_api/src/router/admin_router.dart';
import 'package:main_api/src/router/client_router.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/billing/recurring_subscription_service.dart';
import 'package:main_api/src/services/database/mongo_service.dart';

// Backend стартует отсюда.
// Это отдельное серверное приложение, которое принимает HTTP-запросы от Flutter.
void main(List<String> arguments) async {
  // Загружаем переменные окружения из .env:
  // адрес MongoDB, порт сервера, ключи внешних сервисов и т.д.
  AppConfig.loadEnv();

  // Берём строку подключения к MongoDB из конфига.
  final mongoUri = AppConfig.mongoUri;

  try {
    // Подключаемся к базе до запуска сервера.
    // Если база недоступна, нет смысла принимать запросы.
    await MongoService.instance.connect(mongoUri);
    print('MongoDB connected successfully');
  } catch (e) {
    print('Failed to connect to MongoDB: $e');
    exit(1);
  }
  if (AppConfig.accountBillingServiceUrl == null) {
    RecurringSubscriptionService.instance.start();
  }

  // Router - это таблица URL-адресов backend.
  // Он решает, какой controller должен обработать конкретный запрос.
  final app = Router();

  // Все пользовательские API начинаются с /api/v1/.
  // Например /api/v1/billing/deposit.
  app.mount('/api/v1/', createClientRouter().call);

  // Админка для продакшена доступна как /psychology.
  // Старый /admin оставлен для совместимости со старыми закладками.
  app.get('/admin', (Request request) {
    return Response.found('/admin/apps');
  });
  app.mount('/admin/', createAdminRouter().call);

  // Простой health check.
  // По нему можно проверить, что сервер жив и отвечает.
  app.get('/health', (Request request) {
    return Response.ok('OK');
  });

  // Pipeline добавляет обработку вокруг всех обычных HTTP-запросов:
  // - logRequests печатает запросы в консоль
  // - _corsHeaders разрешает фронту обращаться к backend
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsHeaders())
      .addHandler(app.call);

  // Запускаем HTTP-сервер на всех сетевых интерфейсах.
  // Порт берём из AppConfig.
  final server = await HttpServer.bind("0.0.0.0", AppConfig.port);
  server.listen((request) async {
    // Все остальные HTTP-запросы отдаём shelf.
    await io.handleRequest(request, handler);
  });

  print('Server running on http://${server.address.host}:${server.port}');
}

/// Middleware для CORS.
/// Простыми словами: разрешает приложению/браузеру отправлять запросы на backend.
Middleware _corsHeaders() {
  return (Handler handler) {
    return (Request request) async {
      // OPTIONS - это предварительный запрос браузера:
      // "можно ли мне потом отправить настоящий POST/GET?"
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

      // Выполняем настоящий handler и добавляем CORS-заголовки к его ответу.
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
