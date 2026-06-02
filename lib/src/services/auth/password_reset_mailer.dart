import 'package:main_api/src/services/app_config.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class PasswordResetMailer {
  PasswordResetMailer._();

  static final instance = PasswordResetMailer._();

  Future<void> sendResetCode({
    required String email,
    required String code,
    required String appId,
  }) async {
    final host = AppConfig.smtpHost;
    final username = AppConfig.smtpUsername;
    final password = AppConfig.smtpPassword;
    if (host == null ||
        host.isEmpty ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      throw StateError('SMTP is not configured');
    }

    final appName = _appName(appId);
    final ttlMinutes = AppConfig.passwordResetCodeTtlMinutes;
    final message = Message()
      ..from = Address(AppConfig.smtpFromEmail, AppConfig.smtpFromName)
      ..recipients.add(email)
      ..subject = 'Код восстановления пароля $appName'
      ..text = _plainBody(appName: appName, code: code, ttlMinutes: ttlMinutes)
      ..html = _htmlBody(appName: appName, code: code, ttlMinutes: ttlMinutes);

    final server = SmtpServer(
      host,
      port: AppConfig.smtpPort,
      username: username,
      password: password,
      ssl: AppConfig.smtpSsl,
      allowInsecure: AppConfig.smtpAllowInsecure,
    );

    await send(message, server);
  }

  String _appName(String appId) {
    return switch (appId.trim().toLowerCase()) {
      'med_app' => 'Niami Med',
      'callories' => 'Callories',
      _ => 'NIAMI',
    };
  }

  String _plainBody({
    required String appName,
    required String code,
    required int ttlMinutes,
  }) {
    return '''
Ваш код для восстановления пароля в $appName: $code

Код действует $ttlMinutes минут. Если вы не запрашивали восстановление пароля, просто проигнорируйте это письмо.
''';
  }

  String _htmlBody({
    required String appName,
    required String code,
    required int ttlMinutes,
  }) {
    return '''
<div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.5;color:#111827">
  <p>Ваш код для восстановления пароля в <b>$appName</b>:</p>
  <p style="font-size:28px;font-weight:700;letter-spacing:4px;margin:18px 0">$code</p>
  <p>Код действует $ttlMinutes минут.</p>
  <p style="color:#6b7280">Если вы не запрашивали восстановление пароля, просто проигнорируйте это письмо.</p>
</div>
''';
  }
}
