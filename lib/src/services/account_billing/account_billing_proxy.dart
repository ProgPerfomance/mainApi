// Этот файл: lib/src/services/account_billing/account_billing_proxy.dart.
// Он проксирует старые /api/v1/auth и /api/v1/billing маршруты в отдельный сервис.

import 'dart:io';

import 'package:main_api/src/services/app_config.dart';
import 'package:shelf/shelf.dart';

class AccountBillingProxy {
  AccountBillingProxy._();

  static final AccountBillingProxy instance = AccountBillingProxy._();

  final HttpClient _client = HttpClient();

  Future<Response> forward(Request request) async {
    final serviceUrl = AppConfig.accountBillingServiceUrl;
    if (serviceUrl == null) {
      return Response.internalServerError(
        body: 'ACCOUNT_BILLING_SERVICE_URL is not configured',
      );
    }

    final targetUri = _targetUri(serviceUrl, request);
    final proxyRequest = await _client.openUrl(request.method, targetUri);
    request.headers.forEach((name, value) {
      final lowerName = name.toLowerCase();
      if (lowerName == 'host' || lowerName == 'content-length') {
        return;
      }
      proxyRequest.headers.set(name, value);
    });

    final body = await request.read().expand((chunk) => chunk).toList();
    if (body.isNotEmpty) {
      proxyRequest.add(body);
    }

    final proxyResponse = await proxyRequest.close();
    final headers = <String, String>{};
    proxyResponse.headers.forEach((name, values) {
      final lowerName = name.toLowerCase();
      if (lowerName == 'transfer-encoding' || lowerName == 'content-length') {
        return;
      }
      headers[name] = values.join(',');
    });

    return Response(
      proxyResponse.statusCode,
      body: proxyResponse,
      headers: headers,
    );
  }

  Uri _targetUri(String serviceUrl, Request request) {
    final base = Uri.parse(serviceUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final requestPath = request.url.path.startsWith('/')
        ? request.url.path.substring(1)
        : request.url.path;
    return base.replace(
      path: '$basePath/api/v1/$requestPath',
      query: request.url.query,
    );
  }
}
