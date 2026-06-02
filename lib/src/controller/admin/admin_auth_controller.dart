// Этот файл: lib/src/controller/admin/admin_auth_controller.dart.
// Простыми словами: это вход в админку для менеджеров и владельцев проекта.
// Комментарии описывают бизнес-смысл: кто может открыть админку и что видит пользователь.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:shelf/shelf.dart';

/// Класс AdminAuthController: показывает визуальный вход в админку и проверяет доступ.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт ответы backend.
class AdminAuthController {
  static const String _cookieName = 'niami_admin_session';
  static const Duration _sessionDuration = Duration(hours: 8);

  /// Функция middleware: закрывает админку от гостей.
  /// Возвращает проверку, которая запускается перед страницами и admin API.
  static Middleware middleware({String basePath = '/admin'}) {
    return (Handler handler) {
      return (Request request) async {
        final path = _normalizedMountedPath(request);
        final adminBasePath = _adminBasePath(request, fallback: basePath);

        // Страница входа и отправка формы должны быть доступны без сессии.
        if (request.method == 'OPTIONS' ||
            path == '/login' ||
            path == '/logout') {
          return handler(request);
        }

        // Если cookie валидна, менеджер может работать с админкой.
        if (_hasValidSession(request)) {
          return handler(request);
        }

        // Next.js admin uses server-side proxy calls and authenticates them
        // with a shared admin API token instead of browser cookies.
        if (path.startsWith('/api/') && _hasValidAdminApiToken(request)) {
          return handler(request);
        }

        // API получает понятную ошибку, а не HTML-страницу входа.
        if (path.startsWith('/api/')) {
          return ResponseHelper.error(
            errorMessage: 'Admin authorization required',
            statusCode: 401,
          );
        }

        // HTML-страницы отправляем на красивый экран входа.
        final next = Uri.encodeQueryComponent(
          '$adminBasePath${path == '/' ? '/characters' : path}',
        );
        return Response.found('$adminBasePath/login?next=$next');
      };
    };
  }

  /// Функция loginPage: показывает визуальный экран входа в админку.
  /// Возвращает HTML-страницу с формой логина и пароля.
  static Future<Response> loginPage(Request request) async {
    final basePath = _adminBasePath(request);
    final next = _safeNextPath(
      request.requestedUri.queryParameters['next'],
      basePath: basePath,
    );
    final error = request.requestedUri.queryParameters['error'];
    return Response.ok(
      _loginHtml(basePath: basePath, next: next, error: error),
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// Функция login: проверяет логин и пароль менеджера.
  /// Возвращает переход в админку или снова показывает форму с ошибкой.
  static Future<Response> login(Request request) async {
    final basePath = _adminBasePath(request);
    final body = await request.readAsString();
    final form = Uri.splitQueryString(body);
    final username = form['username']?.trim() ?? '';
    final password = form['password'] ?? '';
    final next = _safeNextPath(form['next'], basePath: basePath);

    final configuredPassword = AppConfig.adminPassword;
    if (configuredPassword == null) {
      return Response(
        500,
        body: _loginHtml(
          basePath: basePath,
          next: next,
          error: 'ADMIN_PASSWORD не настроен на сервере',
        ),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    final isValid =
        username == AppConfig.adminUsername && password == configuredPassword;
    if (!isValid) {
      return Response.ok(
        _loginHtml(
          basePath: basePath,
          next: next,
          error: 'Неверный логин или пароль',
        ),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    return Response.found(
      next,
      headers: {
        'Set-Cookie': _buildSessionCookie(username, basePath: basePath),
      },
    );
  }

  /// Функция logout: завершает работу менеджера в админке.
  /// Возвращает на экран входа и удаляет cookie.
  static Future<Response> logout(Request request) async {
    final basePath = _adminBasePath(request);
    return Response.found(
      '$basePath/login',
      headers: {'Set-Cookie': _expiredSessionCookie(basePath: basePath)},
    );
  }

  /// Функция _hasValidSession: проверяет, что менеджер уже вошёл.
  /// Возвращает да/нет для доступа к админке.
  static bool _hasValidSession(Request request) {
    final cookie = _readCookie(request, _cookieName);
    if (cookie == null || cookie.isEmpty || !cookie.contains('.')) {
      return false;
    }

    final parts = cookie.split('.');
    if (parts.length != 2) {
      return false;
    }

    final payloadPart = parts[0];
    final signaturePart = parts[1];
    final expectedSignature = _sign(payloadPart);
    if (signaturePart != expectedSignature) {
      return false;
    }

    try {
      final payload = jsonDecode(
        utf8.decode(_decodeBase64UrlNoPadding(payloadPart)),
      );
      if (payload is! Map<String, dynamic>) {
        return false;
      }
      final username = payload['username']?.toString();
      final expiresAt = DateTime.tryParse(
        payload['expiresAt']?.toString() ?? '',
      );
      if (username != AppConfig.adminUsername || expiresAt == null) {
        return false;
      }
      return DateTime.now().toUtc().isBefore(expiresAt);
    } catch (_) {
      return false;
    }
  }

  static bool _hasValidAdminApiToken(Request request) {
    final configuredToken = AppConfig.adminApiToken;
    if (configuredToken == null) {
      return false;
    }
    final requestToken = request.headers['x-admin-token']?.trim();
    return requestToken == configuredToken;
  }

  /// Функция _buildSessionCookie: создаёт подтверждение входа для браузера.
  /// Возвращает Set-Cookie, который браузер будет отправлять в админку.
  static String _buildSessionCookie(
    String username, {
    required String basePath,
  }) {
    final expiresAt = DateTime.now().toUtc().add(_sessionDuration);
    final payload = _encodeBase64UrlNoPadding(
      utf8.encode(
        jsonEncode({
          'username': username,
          'expiresAt': expiresAt.toIso8601String(),
        }),
      ),
    );
    final secure = AppConfig.adminCookieSecure ? '; Secure' : '';
    return '$_cookieName=$payload.${_sign(payload)}; Path=$basePath; Max-Age=${_sessionDuration.inSeconds}; HttpOnly; SameSite=Lax$secure';
  }

  /// Функция _expiredSessionCookie: удаляет подтверждение входа из браузера.
  /// Возвращает Set-Cookie с истёкшим сроком.
  static String _expiredSessionCookie({required String basePath}) {
    final secure = AppConfig.adminCookieSecure ? '; Secure' : '';
    return '$_cookieName=; Path=$basePath; Max-Age=0; HttpOnly; SameSite=Lax$secure';
  }

  /// Функция _sign: подписывает cookie админки.
  /// Возвращает подпись, по которой backend понимает, что cookie не подделали.
  static String _sign(String value) {
    final hmac = Hmac(sha256, utf8.encode(AppConfig.adminSessionSecret));
    return _encodeBase64UrlNoPadding(hmac.convert(utf8.encode(value)).bytes);
  }

  /// Функция _readCookie: находит нужное значение cookie в запросе.
  /// Возвращает текст cookie или пустое значение, если её нет.
  static String? _readCookie(Request request, String name) {
    final header = request.headers['cookie'];
    if (header == null || header.isEmpty) {
      return null;
    }

    for (final part in header.split(';')) {
      final trimmed = part.trim();
      final separator = trimmed.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator);
      if (key == name) {
        return trimmed.substring(separator + 1);
      }
    }
    return null;
  }

  /// Функция _safeNextPath: защищает переход после входа.
  /// Возвращает только внутренний адрес админки.
  static String _safeNextPath(String? rawNext, {required String basePath}) {
    final fallback = '$basePath/characters';
    if (rawNext == null || rawNext.isEmpty) {
      return fallback;
    }
    final parsed = Uri.tryParse(rawNext);
    if (parsed == null || parsed.hasScheme || parsed.hasAuthority) {
      return fallback;
    }
    if (!rawNext.startsWith('$basePath/') ||
        rawNext.startsWith('$basePath/login')) {
      return fallback;
    }
    return rawNext;
  }

  static String _adminBasePath(Request request, {String fallback = '/admin'}) {
    final path = request.requestedUri.path;
    if (path == '/psychology' || path.startsWith('/psychology/')) {
      return '/psychology';
    }
    if (path == '/admin' || path.startsWith('/admin/')) {
      return '/admin';
    }
    return fallback;
  }

  /// Функция _normalizedMountedPath: приводит путь внутри /admin к единому виду.
  /// Возвращает путь, по которому middleware решает, пускать ли запрос.
  static String _normalizedMountedPath(Request request) {
    final path = request.url.path;
    if (path.isEmpty) {
      return '/';
    }
    return path.startsWith('/') ? path : '/$path';
  }

  /// Функция _encodeBase64UrlNoPadding: готовит короткий текст для cookie.
  /// Возвращает безопасную строку без лишних символов.
  static String _encodeBase64UrlNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Функция _decodeBase64UrlNoPadding: читает короткий текст из cookie.
  /// Возвращает исходные байты для проверки сессии.
  static List<int> _decodeBase64UrlNoPadding(String value) {
    final paddingLength = (4 - value.length % 4) % 4;
    return base64Url.decode(value + ('=' * paddingLength));
  }

  /// Функция _escapeHtml: безопасно показывает текст ошибки на странице.
  /// Возвращает текст без риска сломать HTML.
  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Функция _loginHtml: собирает визуальный экран авторизации.
  /// Возвращает HTML, который видит менеджер перед входом в админку.
  static String _loginHtml({
    required String basePath,
    required String next,
    String? error,
  }) {
    final escapedNext = _escapeHtml(next);
    final escapedLoginAction = _escapeHtml('$basePath/login');
    final errorHtml = error == null || error.isEmpty
        ? ''
        : '<div class="alert">${_escapeHtml(error)}</div>';

    return '''
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Вход в админку Niami</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      font-family: "Helvetica Neue", Arial, sans-serif;
      color: #111111;
      background: #f5f5f5;
    }
    .shell {
      width: min(100%, 980px);
      display: grid;
      grid-template-columns: minmax(0, 1fr) 420px;
      min-height: 560px;
      border: 1px solid #d9d9d9;
      border-radius: 28px;
      overflow: hidden;
      background: #ffffff;
    }
    .hero {
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      padding: 34px;
      background: #111111;
      color: #ffffff;
    }
    .brand {
      margin: 0;
      font-size: 14px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
    }
    .hero h1 {
      max-width: 420px;
      margin: 0;
      font-size: 42px;
      line-height: 1;
      letter-spacing: 0;
    }
    .hero p {
      max-width: 420px;
      margin: 14px 0 0;
      color: #d9d9d9;
      line-height: 1.5;
      font-size: 15px;
    }
    .badge-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 22px;
    }
    .badge {
      border: 1px solid rgba(255, 255, 255, 0.24);
      border-radius: 999px;
      padding: 8px 10px;
      color: #ffffff;
      font-size: 12px;
      font-weight: 700;
    }
    .form-side {
      display: grid;
      align-content: center;
      padding: 34px;
      background: #ffffff;
    }
    h2 {
      margin: 0 0 8px;
      font-size: 24px;
      line-height: 1.1;
    }
    .subtitle {
      margin: 0 0 22px;
      color: #6b6b6b;
      font-size: 14px;
      line-height: 1.45;
    }
    form {
      display: grid;
      gap: 14px;
    }
    label {
      display: grid;
      gap: 7px;
      color: #6b6b6b;
      font-size: 13px;
      font-weight: 700;
    }
    input {
      width: 100%;
      border: 1px solid #d9d9d9;
      border-radius: 16px;
      padding: 13px 14px;
      background: #fafafa;
      color: #111111;
      font: inherit;
      outline: none;
    }
    input:focus {
      border-color: #111111;
      background: #ffffff;
    }
    button {
      width: 100%;
      border: 1px solid #111111;
      border-radius: 999px;
      padding: 13px 16px;
      background: #111111;
      color: #ffffff;
      font: inherit;
      font-weight: 800;
      cursor: pointer;
    }
    .alert {
      margin-bottom: 14px;
      border: 1px solid #f2c7c7;
      border-radius: 16px;
      padding: 12px;
      color: #7a1f1f;
      background: #fff4f4;
      font-size: 13px;
      line-height: 1.35;
    }
    .note {
      margin: 16px 0 0;
      color: #8a8a8a;
      font-size: 12px;
      line-height: 1.4;
    }
    @media (max-width: 820px) {
      body { padding: 14px; }
      .shell {
        grid-template-columns: 1fr;
        min-height: auto;
      }
      .hero {
        gap: 40px;
        padding: 26px;
      }
      .hero h1 { font-size: 34px; }
      .form-side { padding: 26px; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <p class="brand">Niami Admin</p>
      <div>
        <h1>Управление приложением</h1>
        <p>Вход нужен для доступа к психологам, пользователям, платежам, промокодам и настройкам приложения.</p>
        <div class="badge-row">
          <span class="badge">Пользователи</span>
          <span class="badge">Биллинг</span>
          <span class="badge">Контент</span>
        </div>
      </div>
      <p class="subtitle">Сессия действует 8 часов. После выхода доступ к админке закрывается на этом устройстве.</p>
    </section>
    <section class="form-side">
      <h2>Вход</h2>
      <p class="subtitle">Введите логин и пароль менеджера.</p>
      $errorHtml
      <form method="post" action="$escapedLoginAction">
        <input type="hidden" name="next" value="$escapedNext" />
        <label>
          Логин
          <input name="username" autocomplete="username" required autofocus />
        </label>
        <label>
          Пароль
          <input name="password" type="password" autocomplete="current-password" required />
        </label>
        <button type="submit">Войти в админку</button>
      </form>
      <p class="note">Доступ выдаётся через переменные ADMIN_USERNAME и ADMIN_PASSWORD на сервере.</p>
    </section>
  </main>
</body>
</html>
''';
  }
}
