// Этот файл: lib/src/controller/admin/character_admin_controller.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:main_api/src/helper/parse_request_data_helper.dart';
import 'package:main_api/src/helper/response_helper.dart';
import 'package:main_api/src/models/character.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:main_api/src/services/deepseek/deepseek_chat_service.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';

/// Класс CharacterAdminController: описывает отдельную часть программы простыми блоками.
/// Сам по себе комментарий ничего не возвращает; код внутри класса создаёт объекты, экраны или сервисы.
class CharacterAdminController {
  static const Set<String> _allowedImageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
  };

  /// Функция adminPage: выполняет шаг adminPage в этой части программы. Возвращает HTTP-ответ, который backend отправит клиенту.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> adminPage(Request request) async {
    return Response.ok(
      _pageHtml,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// Функция listCharacters: получает список данных и возвращает его вызывающему коду.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> listCharacters(Request request) async {
    try {
      final charactersCollection = _charactersCollection;
      final rawCharacters = await charactersCollection.find().toList();
      final characters = rawCharacters.map(Character.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return ResponseHelper.success(
        data: characters
            .map(
              (item) => item.toPublicJson(includeLocalizedDescriptions: true),
            )
            .toList(),
      );
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция createCharacter: создаёт новую запись или объект и возвращает созданный результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> createCharacter(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final character = _characterFromRequest(data);

      final result = await _charactersCollection.insertOne(character.toJson());
      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to create character',
          statusCode: 500,
        );
      }

      final rawCharacter = await _charactersCollection.findOne(
        where.eq('_id', result.id),
      );

      if (rawCharacter == null) {
        return ResponseHelper.error(
          errorMessage: 'Failed to load created character',
          statusCode: 500,
        );
      }

      return ResponseHelper.success(
        statusCode: 201,
        data: Character.fromJson(
          rawCharacter,
        ).toPublicJson(includeLocalizedDescriptions: true),
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция updateCharacter: обновляет существующие данные и возвращает обновлённый результат.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> updateCharacter(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(
          errorMessage: 'Invalid psychologist ID format',
        );
      }

      final data = await parseRequestDataHelper(request);
      final characterId = ObjectId.fromHexString(id);
      final existingCharacter = await _charactersCollection.findOne(
        where.eq('_id', characterId),
      );

      if (existingCharacter == null) {
        return ResponseHelper.error(
          errorMessage: 'Psychologist not found',
          statusCode: 404,
        );
      }

      final character = _characterFromRequest(
        data,
        existing: Character.fromJson(
          existingCharacter,
        ).copyWith(id: characterId),
      );

      final result = await _charactersCollection.updateOne(
        where.eq('_id', characterId),
        modify
            .set('name', character.name)
            .set('avatarUrl', character.avatarUrl)
            .set('systemPrompt', character.systemPrompt)
            .set('shortDescription', character.shortDescription)
            .set('longDescription', character.longDescription)
            .set('localizedNames', character.localizedNames)
            .set(
              'localizedShortDescriptions',
              character.localizedShortDescriptions,
            )
            .set(
              'localizedLongDescriptions',
              character.localizedLongDescriptions,
            )
            .set('updatedAt', character.updatedAt.toIso8601String()),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to update character',
          statusCode: 500,
        );
      }

      final rawCharacter = await _charactersCollection.findOne(
        where.eq('_id', characterId),
      );

      if (rawCharacter == null) {
        return ResponseHelper.error(
          errorMessage: 'Failed to load updated character',
          statusCode: 500,
        );
      }

      return ResponseHelper.success(
        data: Character.fromJson(
          rawCharacter,
        ).toPublicJson(includeLocalizedDescriptions: true),
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> translateCharacter(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(
          errorMessage: 'Invalid psychologist ID format',
        );
      }

      final characterId = ObjectId.fromHexString(id);
      final rawCharacter = await _charactersCollection.findOne(
        where.eq('_id', characterId),
      );

      if (rawCharacter == null) {
        return ResponseHelper.error(
          errorMessage: 'Psychologist not found',
          statusCode: 404,
        );
      }

      final character = Character.fromJson(
        rawCharacter,
      ).copyWith(id: characterId);
      final data = await parseRequestDataHelper(request);
      final targetField = data['field']?.toString().trim() ?? '';
      final targetLanguage = data['language']?.toString().trim() ?? '';
      if (targetField.isNotEmpty || targetLanguage.isNotEmpty) {
        return _translateCharacterField(
          characterId: characterId,
          character: character,
          field: targetField,
          languageCode: targetLanguage,
        );
      }

      final translations = await _translateDescriptions(character);
      final now = DateTime.now().toUtc();
      final localizedNames = {
        ...character.localizedNames,
        ...translations.localizedNames,
      };
      final localizedShortDescriptions = {
        ...character.localizedShortDescriptions,
        ...translations.localizedShortDescriptions,
      };
      final localizedLongDescriptions = {
        ...character.localizedLongDescriptions,
        ...translations.localizedLongDescriptions,
      };

      final result = await _charactersCollection.updateOne(
        where.eq('_id', characterId),
        modify
            .set('localizedNames', localizedNames)
            .set('localizedShortDescriptions', localizedShortDescriptions)
            .set('localizedLongDescriptions', localizedLongDescriptions)
            .set('updatedAt', now.toIso8601String()),
      );

      if (!result.isSuccess || result.nMatched == 0) {
        return ResponseHelper.error(
          errorMessage: 'Failed to save translations',
          statusCode: 500,
        );
      }

      final updatedRawCharacter = await _charactersCollection.findOne(
        where.eq('_id', characterId),
      );

      return ResponseHelper.success(
        data: Character.fromJson(updatedRawCharacter ?? rawCharacter)
            .copyWith(id: characterId)
            .toPublicJson(includeLocalizedDescriptions: true),
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  static Future<Response> _translateCharacterField({
    required ObjectId characterId,
    required Character character,
    required String field,
    required String languageCode,
  }) async {
    if (languageCode != 'en' && languageCode != 'be') {
      return ResponseHelper.error(errorMessage: 'Unsupported language');
    }

    if (field != 'name' &&
        field != 'shortDescription' &&
        field != 'longDescription') {
      return ResponseHelper.error(errorMessage: 'Unsupported field');
    }

    final sourceText = switch (field) {
      'name' => character.name,
      'shortDescription' => character.shortDescription,
      'longDescription' => character.longDescription,
      _ => '',
    };
    if (sourceText.trim().isEmpty) {
      return ResponseHelper.error(errorMessage: 'Source text is empty');
    }

    final translatedText = await _translateTextField(
      sourceText: sourceText,
      field: field,
      languageCode: languageCode,
    );
    final now = DateTime.now().toUtc();
    final localizedNames = {...character.localizedNames};
    final localizedShortDescriptions = {
      ...character.localizedShortDescriptions,
    };
    final localizedLongDescriptions = {...character.localizedLongDescriptions};

    switch (field) {
      case 'name':
        localizedNames[languageCode] = translatedText;
      case 'shortDescription':
        localizedShortDescriptions[languageCode] = translatedText;
      case 'longDescription':
        localizedLongDescriptions[languageCode] = translatedText;
    }

    final result = await _charactersCollection.updateOne(
      where.eq('_id', characterId),
      modify
          .set('localizedNames', localizedNames)
          .set('localizedShortDescriptions', localizedShortDescriptions)
          .set('localizedLongDescriptions', localizedLongDescriptions)
          .set('updatedAt', now.toIso8601String()),
    );

    if (!result.isSuccess || result.nMatched == 0) {
      return ResponseHelper.error(
        errorMessage: 'Failed to save translation',
        statusCode: 500,
      );
    }

    final updatedRawCharacter = await _charactersCollection.findOne(
      where.eq('_id', characterId),
    );

    return ResponseHelper.success(
      data: Character.fromJson(updatedRawCharacter ?? character.toJson())
          .copyWith(id: characterId)
          .toPublicJson(includeLocalizedDescriptions: true),
    );
  }

  /// Функция deleteCharacter: удаляет данные. Возвращает результат удаления или HTTP-ответ.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> deleteCharacter(Request request, String id) async {
    try {
      if (!ObjectId.isValidHexId(id)) {
        return ResponseHelper.error(
          errorMessage: 'Invalid psychologist ID format',
        );
      }

      final result = await _charactersCollection.deleteOne(
        where.eq('_id', ObjectId.fromHexString(id)),
      );

      if (!result.isSuccess) {
        return ResponseHelper.error(
          errorMessage: 'Failed to delete character',
          statusCode: 500,
        );
      }

      if (result.nRemoved == 0) {
        return ResponseHelper.error(
          errorMessage: 'Psychologist not found',
          statusCode: 404,
        );
      }

      return ResponseHelper.success(data: {'deleted': true, '_id': id});
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция uploadCharacterAvatar: выполняет шаг uploadCharacterAvatar в этой части программы. Возвращает HTTP-ответ, который backend отправит клиенту.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> uploadCharacterAvatar(Request request) async {
    try {
      final data = await parseRequestDataHelper(request);
      final rawFileName = data['fileName']?.toString().trim() ?? '';
      final dataUrl = data['dataUrl']?.toString().trim() ?? '';

      if (rawFileName.isEmpty || dataUrl.isEmpty) {
        return ResponseHelper.error(errorMessage: 'Image file is required');
      }

      final parsedImage = _parseImageDataUrl(dataUrl);
      final sanitizedName = _sanitizeFileName(rawFileName);
      final extension = _resolveImageExtension(
        sanitizedName: sanitizedName,
        mimeType: parsedImage.mimeType,
      );
      final uniqueName =
          'character_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32).toRadixString(16)}.$extension';

      final uploadsDirectory = Directory(
        path.join(AppConfig.uploadsDir, 'characters'),
      );
      await uploadsDirectory.create(recursive: true);

      final file = File(path.join(uploadsDirectory.path, uniqueName));
      await file.writeAsBytes(parsedImage.bytes, flush: true);

      final publicUrl = _publicUploadUrl(
        request,
        '/uploads/characters/$uniqueName',
      );

      return ResponseHelper.success(
        statusCode: 201,
        data: {'url': publicUrl.toString()},
      );
    } on FormatException catch (error) {
      return ResponseHelper.error(errorMessage: error.message);
    } catch (error) {
      return ResponseHelper.error(
        errorMessage: 'Internal server error: $error',
        statusCode: 500,
      );
    }
  }

  /// Функция serveUploadedFile: выполняет шаг serveUploadedFile в этой части программы. Возвращает HTTP-ответ, который backend отправит клиенту.
  /// Возвращает HTTP-ответ, который backend отправит клиенту.
  static Future<Response> serveUploadedFile(
    Request request,
    String filePath,
  ) async {
    try {
      final normalizedPath = path.normalize(filePath).replaceAll('\\', '/');
      if (normalizedPath.startsWith('..') || path.isAbsolute(normalizedPath)) {
        return Response.notFound('Not found');
      }

      final file = File(path.join(AppConfig.uploadsDir, normalizedPath));
      if (!await file.exists()) {
        return Response.notFound('Not found');
      }

      final extension = path
          .extension(file.path)
          .replaceFirst('.', '')
          .toLowerCase();
      final bytes = await file.readAsBytes();

      return Response.ok(
        bytes,
        headers: {
          'Content-Type': _contentTypeForExtension(extension),
          'Cache-Control': 'public, max-age=31536000',
        },
      );
    } catch (_) {
      return Response.notFound('Not found');
    }
  }

  /// Геттер _charactersCollection: читает значение _charactersCollection и возвращает его без отдельного изменения данных.
  /// Возвращает значение типа DbCollection; это готовый результат для следующего шага программы.
  static DbCollection get _charactersCollection =>
      MongoService.instance.db.collection(Collections.characters);

  static Uri _publicUploadUrl(Request request, String uploadPath) {
    final forwardedHost =
        _firstForwardedHeader(request, 'x-forwarded-host') ??
        _firstForwardedHeader(request, 'host');
    if (forwardedHost == null || forwardedHost.isEmpty) {
      return request.requestedUri.resolve(uploadPath);
    }

    final forwardedProto =
        _firstForwardedHeader(request, 'x-forwarded-proto') ??
        request.requestedUri.scheme;
    final scheme = forwardedProto == 'http' || forwardedProto == 'https'
        ? forwardedProto
        : 'https';
    return Uri.parse('$scheme://$forwardedHost').resolve(uploadPath);
  }

  static String? _firstForwardedHeader(Request request, String name) {
    final value = request.headers[name]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value.split(',').first.trim();
  }

  /// Функция _characterFromRequest: выполняет шаг _characterFromRequest в этой части программы. Возвращает значение типа Character; это готовый результат для следующего шага программы.
  /// Возвращает значение типа Character; это готовый результат для следующего шага программы.
  static Character _characterFromRequest(
    Map<String, dynamic> data, {
    Character? existing,
  }) {
    final name = data['name']?.toString().trim() ?? '';
    final rawAvatarUrl = data['avatarUrl']?.toString().trim() ?? '';
    final avatarUrl = rawAvatarUrl.isEmpty
        ? existing?.avatarUrl ?? ''
        : rawAvatarUrl;
    final systemPrompt = data['systemPrompt']?.toString().trim() ?? '';
    final shortDescription = data['shortDescription']?.toString().trim() ?? '';
    final longDescription = data['longDescription']?.toString().trim() ?? '';
    final localizedNames = _localizedTextMapFromRequest(data['localizedNames']);
    final localizedShortDescriptions = _localizedTextMapFromRequest(
      data['localizedShortDescriptions'],
    );
    final localizedLongDescriptions = _localizedTextMapFromRequest(
      data['localizedLongDescriptions'],
    );

    if (name.isEmpty) {
      throw const FormatException('Name is required');
    }

    if (avatarUrl.isEmpty) {
      throw const FormatException('Avatar URL is required');
    }

    if (systemPrompt.isEmpty) {
      throw const FormatException('System prompt is required');
    }

    if (shortDescription.isEmpty) {
      throw const FormatException('Short description is required');
    }

    if (longDescription.isEmpty) {
      throw const FormatException('Long description is required');
    }

    final now = DateTime.now().toUtc();

    /// Функция Character: выполняет шаг Character в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Character(
      id: existing?.id,
      name: name,
      avatarUrl: avatarUrl,
      systemPrompt: systemPrompt,
      shortDescription: shortDescription,
      longDescription: longDescription,
      localizedNames: localizedNames.isEmpty
          ? existing?.localizedNames
          : localizedNames,
      localizedShortDescriptions: localizedShortDescriptions.isEmpty
          ? existing?.localizedShortDescriptions
          : localizedShortDescriptions,
      localizedLongDescriptions: localizedLongDescriptions.isEmpty
          ? existing?.localizedLongDescriptions
          : localizedLongDescriptions,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  static Map<String, String> _localizedTextMapFromRequest(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final normalized = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      final text = entry.value?.toString().trim() ?? '';
      if ((key == 'en' || key == 'be') && text.isNotEmpty) {
        normalized[key] = text;
      }
    }

    return normalized;
  }

  static Future<
    ({
      Map<String, String> localizedNames,
      Map<String, String> localizedShortDescriptions,
      Map<String, String> localizedLongDescriptions,
    })
  >
  _translateDescriptions(Character character) async {
    final result = await DeepSeekChatService.instance.generateReply(
      messages: [
        {
          'role': 'system',
          'content':
              'You are a professional translator for a psychology app. '
              'Translate only the provided psychologist name and descriptions. '
              'Return strict JSON with keys "en" and "be"; each contains '
              '"name", "shortDescription" and "longDescription". Do not add markdown.',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'sourceLanguage': 'ru',
            'targets': ['en', 'be'],
            'name': character.name,
            'shortDescription': character.shortDescription,
            'longDescription': character.longDescription,
          }),
        },
      ],
    );

    final data = _decodeDeepSeekJsonObject(result.content);
    final localizedNames = <String, String>{};
    final localizedShortDescriptions = <String, String>{};
    final localizedLongDescriptions = <String, String>{};

    for (final languageCode in const ['en', 'be']) {
      final languageData = data[languageCode];
      if (languageData is! Map) {
        throw FormatException('DeepSeek did not return $languageCode');
      }

      final name = languageData['name']?.toString().trim();
      final shortDescription = languageData['shortDescription']
          ?.toString()
          .trim();
      final longDescription = languageData['longDescription']
          ?.toString()
          .trim();
      if (name == null ||
          name.isEmpty ||
          shortDescription == null ||
          shortDescription.isEmpty ||
          longDescription == null ||
          longDescription.isEmpty) {
        throw FormatException('DeepSeek returned empty $languageCode text');
      }

      localizedNames[languageCode] = name;
      localizedShortDescriptions[languageCode] = shortDescription;
      localizedLongDescriptions[languageCode] = longDescription;
    }

    return (
      localizedNames: localizedNames,
      localizedShortDescriptions: localizedShortDescriptions,
      localizedLongDescriptions: localizedLongDescriptions,
    );
  }

  static Future<String> _translateTextField({
    required String sourceText,
    required String field,
    required String languageCode,
  }) async {
    final targetLanguage = switch (languageCode) {
      'en' => 'English',
      'be' => 'Belarusian',
      _ => languageCode,
    };
    final fieldLabel = switch (field) {
      'name' => 'psychologist display name',
      'shortDescription' => 'short psychologist description',
      'longDescription' => 'long psychologist description',
      _ => 'text',
    };

    final result = await DeepSeekChatService.instance.generateReply(
      messages: [
        {
          'role': 'system',
          'content':
              'You are a professional translator for a psychology app. '
              'Translate only the provided $fieldLabel from Russian to $targetLanguage. '
              'Return strict JSON with one key "text". Do not add markdown. '
              'For display names, keep it short and natural.',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'sourceLanguage': 'ru',
            'targetLanguage': languageCode,
            'field': field,
            'text': sourceText,
          }),
        },
      ],
    );

    final data = _decodeDeepSeekJsonObject(result.content);
    final translatedText = data['text']?.toString().trim() ?? '';
    if (translatedText.isEmpty) {
      throw const FormatException('DeepSeek returned empty translation');
    }

    return translatedText;
  }

  static Map<String, dynamic> _decodeDeepSeekJsonObject(String content) {
    var normalized = content.trim();
    if (normalized.startsWith('```')) {
      normalized = normalized
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    final decoded = jsonDecode(normalized);
    if (decoded is! Map) {
      throw const FormatException('DeepSeek returned invalid JSON');
    }

    return Map<String, dynamic>.from(decoded);
  }

  /// Функция _parseImageDataUrl: разбирает входные данные и возвращает их в понятном для программы виде.
  /// Возвращает текст.
  static ({String mimeType, List<int> bytes}) _parseImageDataUrl(
    String dataUrl,
  ) {
    final match = RegExp(
      r'^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$',
      dotAll: true,
    ).firstMatch(dataUrl);

    if (match == null) {
      throw const FormatException('Invalid image payload');
    }

    final mimeType = match.group(1)?.toLowerCase() ?? '';
    final rawData = match.group(2) ?? '';
    final extension = _extensionFromMimeType(mimeType);
    if (extension == null) {
      throw const FormatException('Unsupported image format');
    }

    try {
      return (mimeType: mimeType, bytes: base64Decode(rawData));
    } on FormatException {
      throw const FormatException('Invalid image payload');
    }
  }

  /// Функция _sanitizeFileName: выполняет шаг _sanitizeFileName в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static String _sanitizeFileName(String fileName) {
    final baseName = path.basename(fileName).trim();
    return baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  /// Функция _resolveImageExtension: выполняет шаг _resolveImageExtension в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static String _resolveImageExtension({
    required String sanitizedName,
    required String mimeType,
  }) {
    final extension = path
        .extension(sanitizedName)
        .replaceFirst('.', '')
        .toLowerCase();
    if (_allowedImageExtensions.contains(extension)) {
      return extension == 'jpeg' ? 'jpg' : extension;
    }

    final extensionFromMime = _extensionFromMimeType(mimeType);
    if (extensionFromMime == null) {
      throw const FormatException('Unsupported image format');
    }

    return extensionFromMime;
  }

  /// Функция _extensionFromMimeType: выполняет шаг _extensionFromMimeType в этой части программы. Возвращает текст или пустое значение, если текста нет.
  /// Возвращает текст или пустое значение, если текста нет.
  static String? _extensionFromMimeType(String mimeType) {
    switch (mimeType) {
      case 'image/png':
        return 'png';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return null;
    }
  }

  /// Функция _contentTypeForExtension: выполняет шаг _contentTypeForExtension в этой части программы. Возвращает текст.
  /// Возвращает текст.
  static String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  static const String _pageHtml = r'''
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Психологи, биллинг и пожелания</title>
  <style>
    :root {
      --bg: #f5f5f5;
      --surface: #ffffff;
      --surface-soft: #fafafa;
      --line: #d9d9d9;
      --line-strong: #111111;
      --text: #111111;
      --muted: #6b6b6b;
      --accent: #111111;
      --danger: #111111;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      font-family: "Helvetica Neue", Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
    }

    .wrap {
      max-width: 1180px;
      margin: 0 auto;
      padding: 28px 20px 40px;
    }

    h1 {
      margin: 0;
      font-size: 22px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }

    .topbar {
      display: grid;
      gap: 18px;
      margin-bottom: 24px;
    }

    .topbar-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    .logout-link {
      display: inline-flex;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 8px 12px;
      background: #ffffff;
      color: var(--text);
      font-size: 13px;
      font-weight: 700;
      text-decoration: none;
    }

    .layout {
      display: grid;
      grid-template-columns: 360px 1fr;
      gap: 20px;
    }

    .tab-bar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    .panel {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 20px;
      padding: 18px;
      box-shadow: none;
    }

	    .panel h2 {
	      margin: 0 0 14px;
	      font-size: 15px;
	      font-weight: 700;
	      letter-spacing: 0.04em;
	      text-transform: uppercase;
	    }

	    .panel-heading {
	      display: flex;
	      align-items: center;
	      justify-content: space-between;
	      gap: 12px;
	      margin-bottom: 14px;
	    }

	    .panel-heading h2 {
	      margin: 0;
	    }

	    .compact-control {
	      display: inline-flex;
	      align-items: center;
	      gap: 8px;
	      color: var(--muted);
	      font-size: 12px;
	      font-weight: 700;
	    }

	    .compact-control select {
	      width: auto;
	      min-width: 190px;
	      padding: 8px 10px;
	      border-radius: 999px;
	      font-size: 12px;
	    }

    .status {
      min-height: 18px;
      margin-bottom: 10px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.02em;
    }

    .status.error { color: #111111; }
    .status.success { color: var(--muted); }

    .list {
      display: grid;
      gap: 12px;
    }

    .price-row {
      display: flex;
      gap: 10px;
      align-items: end;
      flex-wrap: wrap;
    }

    .price-row label {
      flex: 1 1 220px;
    }

    .summary-number {
      margin: 4px 0 0;
      font-size: 28px;
      font-weight: 700;
      color: var(--text);
    }

    .table-wrap {
      overflow-x: auto;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--surface-soft);
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 620px;
    }

    th, td {
      padding: 12px 14px;
      border-bottom: 1px solid var(--line);
      text-align: left;
      font-size: 14px;
    }

    th {
      color: var(--muted);
      font-weight: 600;
      background: #f3f3f3;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      font-size: 12px;
    }

    tr:last-child td {
      border-bottom: 0;
    }

    .amount-negative {
      color: var(--text);
      font-weight: 700;
      white-space: nowrap;
    }

    .mono {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      font-size: 13px;
    }

    .card {
      display: grid;
      grid-template-columns: 56px 1fr;
      gap: 12px;
      align-items: start;
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      background: var(--surface-soft);
    }

    .card img {
      width: 56px;
      height: 56px;
      border-radius: 14px;
      object-fit: cover;
      background: #efefef;
      border: 1px solid var(--line);
    }

    .card-title {
      margin: 0 0 6px;
      font-size: 16px;
    }

    .card-text {
      margin: 0 0 10px;
      color: var(--muted);
      font-size: 14px;
      line-height: 1.4;
      white-space: pre-wrap;
    }

    form {
      display: grid;
      gap: 12px;
    }

    label {
      display: grid;
      gap: 6px;
      font-size: 14px;
      color: var(--muted);
    }

    .field-title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
    }

    .field-translate-button {
      padding: 6px 10px;
      font-size: 12px;
      background: white;
      color: var(--text);
    }

    input, textarea, select {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 10px 12px;
      background: #fff;
      color: var(--text);
      font: inherit;
    }

    textarea {
      min-height: 120px;
      resize: vertical;
    }

    .actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    button {
      border: 1px solid var(--line-strong);
      border-radius: 999px;
      padding: 10px 14px;
      background: var(--accent);
      color: white;
      font: inherit;
      cursor: pointer;
      transition: background 0.15s ease, color 0.15s ease;
    }

    button.secondary {
      background: white;
      color: var(--text);
    }

    button.danger {
      background: white;
      color: var(--text);
    }

    .card-meta {
      margin: 0 0 10px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.5;
    }

    .tag {
      display: inline-flex;
      align-items: center;
      padding: 4px 8px;
      border-radius: 999px;
      border: 1px solid var(--line);
      background: white;
      color: var(--text);
      font-size: 12px;
      font-weight: 600;
    }

    .tag.success {
      background: #111111;
      color: #ffffff;
    }

    .section-stack {
      display: grid;
      gap: 20px;
      margin-top: 20px;
    }

    .package-hero {
      display: grid;
      gap: 14px;
      padding: 18px;
      border: 1px solid var(--line-strong);
      border-radius: 20px;
      background: #111111;
      color: #ffffff;
      margin-bottom: 16px;
    }

    .package-hero h2 {
      margin: 0 0 8px;
      color: #ffffff;
    }

    .package-hero p {
      margin: 0;
      color: #d9d9d9;
      line-height: 1.45;
      font-size: 14px;
    }

    .package-hero-badge {
      display: inline-flex;
      width: fit-content;
      padding: 6px 10px;
      border-radius: 999px;
      background: #fff2c2;
      color: #6b4d00;
      font-size: 12px;
      font-weight: 700;
    }

    .package-form-card {
      padding: 14px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--surface-soft);
    }

    .package-card {
      display: grid;
      grid-template-columns: minmax(96px, 132px) 1fr;
      gap: 14px;
      align-items: stretch;
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      background: #ffffff;
    }

    .package-card.is-muted {
      opacity: 0.68;
    }

    .package-count {
      display: grid;
      place-items: center;
      text-align: center;
      border-radius: 16px;
      background: #111111;
      color: #ffffff;
      min-height: 96px;
      padding: 12px;
    }

    .package-count strong {
      display: block;
      font-size: 30px;
      line-height: 1;
    }

    .package-count span {
      display: block;
      margin-top: 6px;
      font-size: 12px;
      color: #d9d9d9;
    }

    .package-info {
      min-width: 0;
    }

    .package-title-row {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: flex-start;
      margin-bottom: 10px;
    }

    .package-metrics {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 12px;
    }

    .package-metric {
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--surface-soft);
      padding: 10px;
    }

    .package-metric span {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 4px;
    }

    .package-metric strong {
      font-size: 16px;
    }

    .package-empty {
      border: 1px dashed var(--line);
      border-radius: 18px;
      padding: 18px;
      color: var(--muted);
      background: var(--surface-soft);
    }

    .tab-button {
      background: white;
      color: var(--text);
    }

    .tab-button.is-active {
      background: #111111;
      color: #ffffff;
    }

    .tab-panel {
      display: none;
    }

    .tab-panel.is-active {
      display: block;
    }

	    @media (max-width: 820px) {
	      .layout {
	        grid-template-columns: 1fr;
	      }

	      .panel-heading {
	        align-items: flex-start;
	        flex-direction: column;
	      }

	      .compact-control {
	        width: 100%;
	      }

	      .compact-control select {
	        width: 100%;
	      }

	      .package-card {
	        grid-template-columns: 1fr;
	      }
	    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="topbar">
      <div class="topbar-head">
        <h1>Admin</h1>
        <a class="logout-link" href="./logout">Выйти</a>
      </div>
      <div class="tab-bar">
        <button type="button" class="tab-button is-active" data-tab="characters">Психологи</button>
        <button type="button" class="tab-button" data-tab="app">О приложении</button>
        <button type="button" class="tab-button" data-tab="billing">Биллинг</button>
        <button type="button" class="tab-button" data-tab="request-packages">Пакеты запросов</button>
        <button type="button" class="tab-button" data-tab="users">Пользователи</button>
        <button type="button" class="tab-button" data-tab="promo-codes">Промокоды</button>
        <button type="button" class="tab-button" data-tab="wishes">Пожелания</button>
      </div>
    </div>

    <section class="tab-panel is-active" data-tab-panel="characters">
      <div class="layout">
        <section class="panel">
          <h2 id="form-title">Психолог</h2>
          <div id="status" class="status"></div>
          <form id="character-form">
            <label>
              Имя
              <input id="name" name="name" required />
            </label>
            <label>
              <span class="field-title">
                <span>Имя EN</span>
                <button type="button" class="field-translate-button" data-translate-field data-field="name" data-language="en" data-target="nameEn">Перевести</button>
              </span>
              <input id="nameEn" name="nameEn" />
            </label>
            <label>
              <span class="field-title">
                <span>Имя BE</span>
                <button type="button" class="field-translate-button" data-translate-field data-field="name" data-language="be" data-target="nameBe">Перевести</button>
              </span>
              <input id="nameBe" name="nameBe" />
            </label>
            <label>
              Фото
              <input id="avatarFile" name="avatarFile" type="file" accept="image/png,image/jpeg,image/webp,image/gif" />
            </label>
            <input id="avatarUrl" name="avatarUrl" type="hidden" />
            <div id="avatar-upload-status" class="status"></div>
            <div class="card">
              <img id="avatar-preview" alt="Предпросмотр" />
              <div>
                <p class="card-text" id="avatar-preview-text">Файл не выбран</p>
              </div>
            </div>
            <label>
              Системный промпт
              <textarea id="systemPrompt" name="systemPrompt" required></textarea>
            </label>
            <label>
              Короткое описание
              <textarea id="shortDescription" name="shortDescription" required></textarea>
            </label>
            <label>
              Длинное описание
              <textarea id="longDescription" name="longDescription" required></textarea>
            </label>
            <label>
              <span class="field-title">
                <span>Короткое описание EN</span>
                <button type="button" class="field-translate-button" data-translate-field data-field="shortDescription" data-language="en" data-target="shortDescriptionEn">Перевести</button>
              </span>
              <textarea id="shortDescriptionEn" name="shortDescriptionEn"></textarea>
            </label>
            <label>
              <span class="field-title">
                <span>Длинное описание EN</span>
                <button type="button" class="field-translate-button" data-translate-field data-field="longDescription" data-language="en" data-target="longDescriptionEn">Перевести</button>
              </span>
              <textarea id="longDescriptionEn" name="longDescriptionEn"></textarea>
            </label>
            <label>
              <span class="field-title">
                <span>Короткое описание BE</span>
                <button type="button" class="field-translate-button" data-translate-field data-field="shortDescription" data-language="be" data-target="shortDescriptionBe">Перевести</button>
              </span>
              <textarea id="shortDescriptionBe" name="shortDescriptionBe"></textarea>
            </label>
            <label>
              <span class="field-title">
                <span>Длинное описание BE</span>
                <button type="button" class="field-translate-button" data-translate-field data-field="longDescription" data-language="be" data-target="longDescriptionBe">Перевести</button>
              </span>
              <textarea id="longDescriptionBe" name="longDescriptionBe"></textarea>
            </label>
            <div class="actions">
              <button type="submit" id="submit-btn">Сохранить</button>
              <button type="button" class="secondary" id="translate-btn">Перевести EN/BE</button>
              <button type="button" class="secondary" id="reset-btn">Сбросить</button>
            </div>
          </form>
        </section>
        <section class="panel">
          <h2>Список</h2>
          <div id="character-list" class="list"></div>
        </section>
      </div>
    </section>

    <section class="tab-panel" data-tab-panel="app">
      <div class="layout">
        <section class="panel">
          <h2>О приложении</h2>
          <div id="app-status" class="status"></div>
          <form id="app-form">
            <label>
              Актуальная версия приложения
              <input id="requiredAppVersion" name="requiredAppVersion" placeholder="v1.0.1+2" required />
            </label>
            <div class="actions">
              <button type="submit" id="app-submit-btn">Сохранить</button>
            </div>
          </form>
        </section>
        <section class="panel">
          <h2>Текущая настройка</h2>
          <div class="section-stack" style="margin-top:0;">
            <div>
              <div class="card-text">Разрешённая версия</div>
              <p class="summary-number" id="current-app-version">—</p>
            </div>
            <div>
              <div class="card-text">Обновлено</div>
              <p class="card-meta" id="current-app-version-updated">—</p>
            </div>
          </div>
        </section>
      </div>
    </section>

    <section class="tab-panel" data-tab-panel="billing">
      <div class="layout">
        <section class="panel">
          <h2>Настройки</h2>
          <div id="billing-status" class="status"></div>
          <form id="billing-form">
            <div class="price-row">
              <label>
                Цена первого AI-запроса, ₽
                <input id="requestPrice" name="requestPrice" type="number" min="0" step="0.01" required />
              </label>
            </div>
            <div class="price-row">
              <label>
                Бонус за реферала, ₽
                <input id="referralBonusAmount" name="referralBonusAmount" type="number" min="0" step="0.01" required />
              </label>
            </div>
            <div class="price-row">
              <label>
                Название подписки
                <input id="subscriptionName" name="subscriptionName" maxlength="40" placeholder="Плюс" required />
              </label>
              <label>
                Цена подписки за месяц, ₽
                <input id="subscriptionPrice" name="subscriptionPrice" type="number" min="0.01" step="0.01" required />
              </label>
            </div>
            <div class="actions">
              <button type="submit" id="billing-submit-btn">Сохранить</button>
            </div>
          </form>
          <div class="section-stack">
            <div>
              <div class="card-text">Текущие условия сессии</div>
              <p class="summary-number" id="current-price">0.00 ₽</p>
            </div>
            <div>
              <div class="card-text">Текущий бонус за реферала</div>
              <p class="summary-number" id="current-referral-bonus">0.00 ₽</p>
            </div>
            <div>
              <div class="card-text">Текущая подписка</div>
              <p class="summary-number" id="current-subscription">Плюс · 0.00 ₽</p>
            </div>
          </div>
        </section>
        <section class="panel">
          <h2>Списания</h2>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Пользователь</th>
                  <th>ID</th>
                  <th>Сумма</th>
                  <th>Дата</th>
                </tr>
              </thead>
              <tbody id="charges-list">
                <tr><td colspan="4">Загрузка...</td></tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </section>

    <!-- Отдельная вкладка пакетов: менеджер управляет товаром, который продаётся в мобильном приложении. -->
    <section class="tab-panel" data-tab-panel="request-packages">
      <div class="layout">
        <section class="panel">
          <div class="package-hero">
            <div>
              <h2>Пакеты запросов</h2>
              <p>Управление товаром для мобильного приложения: пользователь покупает запросы заранее, а консультации становятся выгоднее.</p>
            </div>
            <span class="package-hero-badge">Минимум 10 запросов</span>
          </div>
          <div id="request-packages-status" class="status"></div>
          <div class="package-form-card">
            <form id="request-package-form">
              <div class="price-row">
                <label>
                  Запросов в пакете
                  <input id="requestPackageCount" type="number" min="10" step="1" required />
                </label>
                <label>
                  Цена пакета, ₽
                  <input id="requestPackagePrice" type="number" min="0.01" step="0.01" required />
                </label>
              </div>
              <div class="price-row">
                <label>
                  Статус
                  <select id="requestPackageActive">
                    <option value="true">Активен</option>
                    <option value="false">Скрыт</option>
                  </select>
                </label>
              </div>
              <div class="actions">
                <button type="submit" id="request-package-submit-btn">Сохранить пакет</button>
                <button type="button" class="secondary" id="request-package-reset-btn">Сбросить</button>
              </div>
            </form>
          </div>
        </section>
        <section class="panel">
          <h2>Список пакетов</h2>
          <div id="request-packages-list" class="list"></div>
        </section>
      </div>
    </section>

    <section class="tab-panel" data-tab-panel="users">
      <div class="section-stack">
        <section class="panel">
          <h2>Пользователи</h2>
          <div id="users-status" class="status"></div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Имя</th>
                  <th>Email</th>
                  <th>Баланс</th>
                  <th>Подписка</th>
                  <th>Реферальный код</th>
                  <th>Рефералы</th>
                  <th>Действия</th>
                </tr>
              </thead>
              <tbody id="users-list">
                <tr><td colspan="7">Загрузка...</td></tr>
              </tbody>
            </table>
          </div>
        </section>
        <section class="panel">
          <h2>Профиль пользователя</h2>
          <div id="user-profile-status" class="status"></div>
          <div id="user-profile-empty" class="card">
            <div></div>
            <div><p class="card-text">Выберите пользователя из списка, чтобы открыть профиль и историю транзакций.</p></div>
          </div>
          <div id="user-profile-content" style="display:none;">
            <div class="section-stack" style="margin-top:0;">
              <div class="card">
                <div></div>
                <div>
                  <h3 class="card-title" id="user-profile-name">—</h3>
                  <p class="card-meta" id="user-profile-email">—</p>
                  <p class="card-meta">ID: <span id="user-profile-id" class="mono">—</span></p>
                  <p class="card-meta">Реферальный код: <span id="user-profile-referral-code" class="mono">—</span></p>
                  <p class="card-meta">Применённый код: <span id="user-profile-applied-referral-code" class="mono">—</span></p>
                  <p class="card-meta">Подписка: <span id="user-profile-subscription">—</span></p>
                  <p class="summary-number" id="user-profile-balance">0.00 ₽</p>
                </div>
              </div>
              <form id="user-balance-form">
                <label>
                  Кто меняет баланс
                  <input id="balanceAdminName" name="balanceAdminName" placeholder="Например, kirill" required />
                </label>
                <label>
                  Новый баланс, ₽
                  <input id="userTargetBalance" name="userTargetBalance" type="number" min="0" step="0.01" required />
                </label>
                <label>
                  Комментарий
                  <input id="userBalanceReason" name="userBalanceReason" placeholder="Необязательно" />
                </label>
                <div class="actions">
                  <button type="submit" id="user-balance-submit-btn">Сохранить баланс</button>
                </div>
              </form>
              <form id="user-subscription-form">
                <label>
                  Кто выдаёт подписку
                  <input id="subscriptionAdminName" name="subscriptionAdminName" placeholder="Например, kirill" required />
                </label>
                <label>
                  Дней подписки
                  <input id="userSubscriptionDays" name="userSubscriptionDays" type="number" min="1" step="1" value="30" required />
                </label>
                <label>
                  Комментарий
                  <input id="userSubscriptionReason" name="userSubscriptionReason" placeholder="Например, тестовый доступ" />
                </label>
                <div class="actions">
                  <button type="submit" id="user-subscription-submit-btn">Выдать подписку</button>
                  <button type="button" id="user-subscription-clear-btn" class="danger">Удалить подписку</button>
                </div>
              </form>
              <div>
                <h3 class="card-title">Рефералы</h3>
                <div id="user-profile-referrals" class="list"></div>
              </div>
              <div>
                <h3 class="card-title">Транзакции</h3>
                <div class="price-row" style="margin-bottom:12px;">
                  <label>
                    Фильтр
                    <select id="userTransactionFilter">
                      <option value="all">Все</option>
                      <option value="deposit">Пополнения</option>
                      <option value="withdrawal">Списания</option>
                      <option value="payment">Оплаты</option>
                    </select>
                  </label>
                </div>
                <div class="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Тип</th>
                        <th>Сумма</th>
                        <th>Описание</th>
                        <th>Кто изменил</th>
                        <th>Дата</th>
                      </tr>
                    </thead>
                    <tbody id="user-transactions-list">
                      <tr><td colspan="5">Транзакций пока нет.</td></tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </section>

    <section class="tab-panel" data-tab-panel="promo-codes">
      <div class="layout">
        <section class="panel">
          <h2 id="promo-form-title">Промокод</h2>
          <div id="promo-status" class="status"></div>
          <form id="promo-form">
            <label>
              Код
              <input id="promoCodeValue" name="promoCodeValue" maxlength="24" required />
            </label>
            <label>
              Рекламная кампания
              <input id="promoCodeCampaign" name="promoCodeCampaign" placeholder="Например, telegram_may" />
            </label>
            <label>
              Сумма начисления, ₽
              <input id="promoCodeAmount" name="promoCodeAmount" type="number" min="0.01" step="0.01" required />
            </label>
            <label>
              Лимит активаций
              <input id="promoCodeMaxRedemptions" name="promoCodeMaxRedemptions" type="number" min="1" step="1" placeholder="Пусто = без лимита" />
            </label>
            <label>
              Статус
              <select id="promoCodeActive" name="promoCodeActive">
                <option value="true">Активен</option>
                <option value="false">Отключён</option>
              </select>
            </label>
            <div class="actions">
              <button type="submit" id="promo-submit-btn">Сохранить</button>
              <button type="button" class="secondary" id="promo-reset-btn">Сбросить</button>
            </div>
          </form>
        </section>
        <section class="panel">
          <h2>Список промокодов</h2>
          <div id="promo-list" class="list"></div>
        </section>
      </div>
    </section>

    <section class="tab-panel" data-tab-panel="wishes">
      <div class="layout">
        <section class="panel">
          <h2 id="wish-form-title">Пожелание</h2>
          <div id="wish-status" class="status"></div>
          <form id="wish-form">
            <label>
              Текст
              <textarea id="wishText" name="wishText" required></textarea>
            </label>
            <label>
              Запрос
              <select id="wishRequestId" name="wishRequestId">
                <option value="">Без привязки</option>
              </select>
            </label>
            <div class="actions">
              <button type="submit" id="wish-submit-btn">Сохранить</button>
              <button type="button" class="secondary" id="wish-reset-btn">Сбросить</button>
            </div>
          </form>
	        </section>
	        <section class="panel">
	          <div class="panel-heading">
	            <h2>Опубликовано</h2>
	            <label class="compact-control">
	              Сортировка
	              <select id="wishSort">
	                <option value="score_desc">Выше рейтинг</option>
	                <option value="score_asc">Ниже рейтинг</option>
	                <option value="date_desc">Сначала новые</option>
	                <option value="date_asc">Сначала старые</option>
	                <option value="likes_desc">Больше лайков</option>
	                <option value="likes_asc">Меньше лайков</option>
	                <option value="dislikes_desc">Больше дизлайков</option>
	                <option value="dislikes_asc">Меньше дизлайков</option>
	              </select>
	            </label>
	          </div>
	          <div id="wish-list" class="list"></div>
	        </section>
      </div>

      <div class="section-stack">
        <section class="panel">
          <div class="panel-heading">
            <h2>Запросы</h2>
            <button type="button" class="danger" id="wish-requests-clear-btn">Очистить запросы</button>
          </div>
          <div id="wish-requests-list" class="list"></div>
        </section>
      </div>
    </section>
  </div>

  <script>
    const adminBasePath = window.location.pathname.startsWith('/psychology') ? '/psychology' : '/admin';
    const characterApiBase = `${adminBasePath}/api/characters`;
    const appVersionApiBase = `${adminBasePath}/api/app/version`;
    const billingSettingsApiBase = `${adminBasePath}/api/billing/settings`;
    const billingChargesApiBase = `${adminBasePath}/api/billing/charges`;
    const requestPackagesApiBase = `${adminBasePath}/api/billing/request-packages`;
    const usersApiBase = `${adminBasePath}/api/users`;
    const promoCodesApiBase = `${adminBasePath}/api/promo-codes`;
    const wishesApiBase = `${adminBasePath}/api/wishes`;
    const wishRequestsApiBase = `${adminBasePath}/api/wish-requests`;
    const form = document.getElementById('character-form');
    const statusEl = document.getElementById('status');
    const formTitle = document.getElementById('form-title');
    const submitBtn = document.getElementById('submit-btn');
    const translateBtn = document.getElementById('translate-btn');
    const fieldTranslateButtons = Array.from(document.querySelectorAll('[data-translate-field]'));
    const listEl = document.getElementById('character-list');
    const resetBtn = document.getElementById('reset-btn');
    const avatarFileInput = document.getElementById('avatarFile');
    const avatarUrlInput = document.getElementById('avatarUrl');
    const avatarUploadStatusEl = document.getElementById('avatar-upload-status');
    const avatarPreviewEl = document.getElementById('avatar-preview');
    const avatarPreviewTextEl = document.getElementById('avatar-preview-text');
    const appForm = document.getElementById('app-form');
    const appStatusEl = document.getElementById('app-status');
    const requiredAppVersionInput = document.getElementById('requiredAppVersion');
    const currentAppVersionEl = document.getElementById('current-app-version');
    const currentAppVersionUpdatedEl = document.getElementById('current-app-version-updated');
    const billingForm = document.getElementById('billing-form');
    const billingStatusEl = document.getElementById('billing-status');
    const requestPriceInput = document.getElementById('requestPrice');
    const referralBonusAmountInput = document.getElementById('referralBonusAmount');
    const subscriptionNameInput = document.getElementById('subscriptionName');
    const subscriptionPriceInput = document.getElementById('subscriptionPrice');
    const currentPriceEl = document.getElementById('current-price');
    const currentReferralBonusEl = document.getElementById('current-referral-bonus');
    const currentSubscriptionEl = document.getElementById('current-subscription');
    const chargesListEl = document.getElementById('charges-list');
    const requestPackageForm = document.getElementById('request-package-form');
    const requestPackagesStatusEl = document.getElementById('request-packages-status');
    const requestPackageCountInput = document.getElementById('requestPackageCount');
    const requestPackagePriceInput = document.getElementById('requestPackagePrice');
    const requestPackageActiveInput = document.getElementById('requestPackageActive');
    const requestPackageSubmitBtn = document.getElementById('request-package-submit-btn');
    const requestPackageResetBtn = document.getElementById('request-package-reset-btn');
    const requestPackagesListEl = document.getElementById('request-packages-list');
    const usersStatusEl = document.getElementById('users-status');
    const usersListEl = document.getElementById('users-list');
    const userProfileStatusEl = document.getElementById('user-profile-status');
    const userProfileEmptyEl = document.getElementById('user-profile-empty');
    const userProfileContentEl = document.getElementById('user-profile-content');
    const userProfileNameEl = document.getElementById('user-profile-name');
    const userProfileEmailEl = document.getElementById('user-profile-email');
    const userProfileIdEl = document.getElementById('user-profile-id');
    const userProfileReferralCodeEl = document.getElementById('user-profile-referral-code');
    const userProfileAppliedReferralCodeEl = document.getElementById('user-profile-applied-referral-code');
    const userProfileSubscriptionEl = document.getElementById('user-profile-subscription');
    const userProfileBalanceEl = document.getElementById('user-profile-balance');
    const userProfileReferralsEl = document.getElementById('user-profile-referrals');
    const userTransactionsListEl = document.getElementById('user-transactions-list');
    const userTransactionFilterInput = document.getElementById('userTransactionFilter');
    const userBalanceForm = document.getElementById('user-balance-form');
    const balanceAdminNameInput = document.getElementById('balanceAdminName');
    const userTargetBalanceInput = document.getElementById('userTargetBalance');
    const userBalanceReasonInput = document.getElementById('userBalanceReason');
    const userSubscriptionForm = document.getElementById('user-subscription-form');
    const subscriptionAdminNameInput = document.getElementById('subscriptionAdminName');
    const userSubscriptionDaysInput = document.getElementById('userSubscriptionDays');
    const userSubscriptionReasonInput = document.getElementById('userSubscriptionReason');
    const userSubscriptionClearBtn = document.getElementById('user-subscription-clear-btn');
    const promoForm = document.getElementById('promo-form');
    const promoStatusEl = document.getElementById('promo-status');
    const promoFormTitle = document.getElementById('promo-form-title');
    const promoCodeValueInput = document.getElementById('promoCodeValue');
    const promoCodeCampaignInput = document.getElementById('promoCodeCampaign');
    const promoCodeAmountInput = document.getElementById('promoCodeAmount');
    const promoCodeMaxRedemptionsInput = document.getElementById('promoCodeMaxRedemptions');
    const promoCodeActiveInput = document.getElementById('promoCodeActive');
    const promoSubmitBtn = document.getElementById('promo-submit-btn');
    const promoResetBtn = document.getElementById('promo-reset-btn');
    const promoListEl = document.getElementById('promo-list');
    const wishForm = document.getElementById('wish-form');
    const wishStatusEl = document.getElementById('wish-status');
    const wishFormTitle = document.getElementById('wish-form-title');
    const wishSubmitBtn = document.getElementById('wish-submit-btn');
    const wishTextInput = document.getElementById('wishText');
	    const wishRequestIdSelect = document.getElementById('wishRequestId');
    const wishSortInput = document.getElementById('wishSort');
    const wishListEl = document.getElementById('wish-list');
    const wishRequestsListEl = document.getElementById('wish-requests-list');
    const wishRequestsClearBtn = document.getElementById('wish-requests-clear-btn');
    const wishResetBtn = document.getElementById('wish-reset-btn');
    const tabButtons = Array.from(document.querySelectorAll('[data-tab]'));
    const tabPanels = Array.from(document.querySelectorAll('[data-tab-panel]'));

    let editingId = null;
    let editingWishId = null;
    let characters = [];
    let charges = [];
    let requestPackages = [];
    let editingRequestPackageId = null;
    let users = [];
    let selectedUserProfile = null;
    let promoCodes = [];
    let editingPromoCodeId = null;
    let wishes = [];
    let wishRequests = [];

    function setStatus(message, type = '') {
      statusEl.textContent = message || '';
      statusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setBillingStatus(message, type = '') {
      billingStatusEl.textContent = message || '';
      billingStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    // Статус вкладки пакетов показывает менеджеру результат создания, изменения или удаления товара.
    function setRequestPackagesStatus(message, type = '') {
      requestPackagesStatusEl.textContent = message || '';
      requestPackagesStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setWishStatus(message, type = '') {
      wishStatusEl.textContent = message || '';
      wishStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setUsersStatus(message, type = '') {
      usersStatusEl.textContent = message || '';
      usersStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setUserProfileStatus(message, type = '') {
      userProfileStatusEl.textContent = message || '';
      userProfileStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setPromoStatus(message, type = '') {
      promoStatusEl.textContent = message || '';
      promoStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setAvatarUploadStatus(message, type = '') {
      avatarUploadStatusEl.textContent = message || '';
      avatarUploadStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function setAppStatus(message, type = '') {
      appStatusEl.textContent = message || '';
      appStatusEl.className = 'status' + (type ? ' ' + type : '');
    }

    function formPayload() {
      return {
        name: document.getElementById('name').value.trim(),
        avatarUrl: avatarUrlInput.value.trim(),
        systemPrompt: document.getElementById('systemPrompt').value.trim(),
        shortDescription: document.getElementById('shortDescription').value.trim(),
        longDescription: document.getElementById('longDescription').value.trim(),
        localizedNames: {
          en: document.getElementById('nameEn').value.trim(),
          be: document.getElementById('nameBe').value.trim()
        },
        localizedShortDescriptions: {
          en: document.getElementById('shortDescriptionEn').value.trim(),
          be: document.getElementById('shortDescriptionBe').value.trim()
        },
        localizedLongDescriptions: {
          en: document.getElementById('longDescriptionEn').value.trim(),
          be: document.getElementById('longDescriptionBe').value.trim()
        }
      };
    }

    function updateAvatarPreview(url, label = '') {
      const normalizedUrl = String(url || '').trim();
      avatarUrlInput.value = normalizedUrl;
      avatarPreviewEl.src = normalizedUrl;
      avatarPreviewEl.style.visibility = normalizedUrl ? 'visible' : 'hidden';
      avatarPreviewTextEl.textContent = label || (normalizedUrl ? 'Загружено' : 'Файл не выбран');
    }

    function resetForm() {
      editingId = null;
      form.reset();
      formTitle.textContent = 'Психолог';
      submitBtn.textContent = 'Сохранить';
      translateBtn.disabled = true;
      fieldTranslateButtons.forEach((button) => { button.disabled = true; });
      avatarFileInput.value = '';
      updateAvatarPreview('');
      setAvatarUploadStatus('');
      setStatus('');
    }

    function wishFormPayload() {
      const requestId = wishRequestIdSelect.value.trim();
      return {
        text: wishTextInput.value.trim(),
        requestId
      };
    }

    function resetWishForm() {
      editingWishId = null;
      wishForm.reset();
      wishRequestIdSelect.value = '';
      wishFormTitle.textContent = 'Новое пожелание';
      wishSubmitBtn.textContent = 'Сохранить';
      setWishStatus('');
      renderWishRequestOptions();
    }

    function escapeHtml(value) {
      return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    function renderList() {
      if (!characters.length) {
        listEl.innerHTML = '<div class="card"><div></div><div><p class="card-text">Психологов пока нет.</p></div></div>';
        return;
      }

      listEl.innerHTML = characters.map((character) => `
        <article class="card">
          <img src="${escapeHtml(character.avatarUrl)}" alt="${escapeHtml(character.name)}" onerror="this.style.visibility='hidden'" />
          <div>
            <h3 class="card-title">${escapeHtml(character.name)}</h3>
            <p class="card-text">${escapeHtml(character.shortDescription || '')}</p>
            <p class="card-meta">
              ${character.localizedNames?.en && character.localizedShortDescriptions?.en ? '<span class="tag success">EN</span>' : '<span class="tag">EN нет</span>'}
              ${character.localizedNames?.be && character.localizedShortDescriptions?.be ? '<span class="tag success">BE</span>' : '<span class="tag">BE нет</span>'}
            </p>
            <div class="actions">
              <button type="button" data-action="edit" data-id="${character._id}">Редактировать</button>
              <button type="button" data-action="delete" data-id="${character._id}" class="danger">Удалить</button>
            </div>
          </div>
        </article>
      `).join('');
    }

    function formatMoney(value) {
      return new Intl.NumberFormat('ru-RU', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }).format(Number(value || 0));
    }

    function formatDate(value) {
      if (!value) return '—';
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) {
        return '—';
      }

      return new Intl.DateTimeFormat('ru-RU', {
        dateStyle: 'short',
        timeStyle: 'short'
      }).format(date);
    }

    function formatSubscriptionStatus(user) {
      const expiresAt = user?.subscriptionExpiresAt;
      if (!expiresAt) {
        return 'Нет активной подписки';
      }

      const date = new Date(expiresAt);
      if (Number.isNaN(date.getTime())) {
        return 'Нет активной подписки';
      }

      const active = date.getTime() > Date.now();
      return `${active ? 'Активна' : 'Истекла'} до ${formatDate(expiresAt)}`;
    }

    function renderCharges() {
      if (!charges.length) {
        chargesListEl.innerHTML = '<tr><td colspan="4">Списаний пока нет.</td></tr>';
        return;
      }

      chargesListEl.innerHTML = charges.map((charge) => `
        <tr>
          <td>${escapeHtml(charge.userName || 'Неизвестный пользователь')}</td>
          <td class="mono">${escapeHtml(charge.userId || '—')}</td>
          <td class="amount-negative">-${formatMoney(charge.amount)} ₽</td>
          <td>${escapeHtml(formatDate(charge.createdAt))}</td>
        </tr>
      `).join('');
    }

    function resetRequestPackageForm() {
      // Сброс возвращает форму в режим создания нового пакета.
      editingRequestPackageId = null;
      requestPackageForm.reset();
      requestPackageActiveInput.value = 'true';
      requestPackageSubmitBtn.textContent = 'Сохранить пакет';
      setRequestPackagesStatus('');
    }

    function renderRequestPackages() {
      // Список показывает менеджеру все товары: активные видны пользователям,
      // скрытые остаются в админке для дальнейшей настройки.
      if (!requestPackages.length) {
        requestPackagesListEl.innerHTML = '<div class="package-empty">Пакетов пока нет. Создайте первый пакет, чтобы он появился в мобильном приложении.</div>';
        return;
      }

      const basePackage = requestPackages.reduce((left, right) => (
        Number(left.requestCount || 0) < Number(right.requestCount || 0) ? left : right
      ));
      const basePricePerRequest = Number(basePackage.price || 0) / Number(basePackage.requestCount || 1);
      requestPackagesListEl.innerHTML = requestPackages.map((item) => `
        <article class="package-card ${item.isActive ? '' : 'is-muted'}">
          <div class="package-count">
            <div>
              <strong>${escapeHtml(item.requestCount)}</strong>
              <span>запросов</span>
            </div>
          </div>
          <div class="package-info">
            <div class="package-title-row">
              <h3 class="card-title">${escapeHtml(item.requestCount)} запросов</h3>
              <div class="tag ${item.isActive ? 'success' : ''}">${item.isActive ? 'Активен' : 'Скрыт'}</div>
            </div>
            <div class="package-metrics">
              <div class="package-metric">
                <span>Цена пакета</span>
                <strong>${formatMoney(item.price)} ₽</strong>
              </div>
              <div class="package-metric">
                <span>За запрос</span>
                <strong>${formatMoney(item.price / item.requestCount)} ₽</strong>
              </div>
            </div>
            <p class="card-meta">
              ${basePricePerRequest > 0 && item.requestCount !== basePackage.requestCount
                ? 'Скидка относительно минимального пакета: ' + Math.max(0, Math.round((1 - (item.price / item.requestCount) / basePricePerRequest) * 100)) + '%'
                : 'Базовый пакет для расчёта скидок'}
            </p>
            <div class="actions">
              <button type="button" data-package-action="edit" data-id="${item._id}">Редактировать</button>
              <button type="button" data-package-action="delete" data-id="${item._id}" class="danger">Удалить</button>
            </div>
          </div>
        </article>
      `).join('');
    }

    function renderUsers() {
      if (!users.length) {
        usersListEl.innerHTML = '<tr><td colspan="7">Пользователей пока нет.</td></tr>';
        return;
      }

      usersListEl.innerHTML = users.map((user) => {
        const referrals = Array.isArray(user.referrals) ? user.referrals : [];
        const referralsHtml = referrals.length
          ? `
              <details>
                <summary>${referrals.length} ${referrals.length === 1 ? 'реферал' : 'рефералов'}</summary>
                <div class="section-stack">
                  ${referrals.map((referral) => `
                    <div class="card">
                      <div>
                        <h3 class="card-title">${escapeHtml(referral.name || 'Без имени')}</h3>
                        <p class="card-meta">${escapeHtml(referral.email || '—')}</p>
                        <p class="card-meta">Баланс: ${formatMoney(referral.balance)} ₽</p>
                        <p class="card-meta">Применён: ${escapeHtml(formatDate(referral.referralAppliedAt || referral.createdAt))}</p>
                      </div>
                    </div>
                  `).join('')}
                </div>
              </details>
            `
          : 'Нет рефералов';

        return `
          <tr>
            <td>${escapeHtml(user.name || 'Без имени')}</td>
            <td>${escapeHtml(user.email || '—')}</td>
            <td>${formatMoney(user.balance)} ₽</td>
            <td>${escapeHtml(formatSubscriptionStatus(user))}</td>
            <td class="mono">${escapeHtml(user.referralCode || '—')}</td>
            <td>${referralsHtml}</td>
            <td>
              <button type="button" data-user-action="open" data-id="${user._id}">Открыть</button>
            </td>
          </tr>
        `;
      }).join('');
    }

    function formatTransactionType(type) {
      switch (type) {
        case 'deposit':
          return 'Пополнение';
        case 'withdrawal':
          return 'Списание';
        case 'payment':
          return 'Оплата';
        default:
          return type || '—';
      }
    }

    function transactionExtraMeta(transaction) {
      const metadata = transaction && transaction.metadata && typeof transaction.metadata === 'object'
        ? transaction.metadata
        : {};

      if (metadata.provider === 'admin_adjustment') {
        return {
          description: metadata.reason
            ? `${transaction.description || 'Корректировка'} · ${metadata.reason}`
            : (transaction.description || 'Корректировка'),
          adminName: metadata.adminName || '—'
        };
      }
      if (metadata.provider === 'admin_subscription_grant') {
        return {
          description: metadata.reason
            ? `${transaction.description || 'Выдача подписки'} · ${metadata.days || '—'} дн. · ${metadata.reason}`
            : `${transaction.description || 'Выдача подписки'} · ${metadata.days || '—'} дн.`,
          adminName: metadata.adminName || '—'
        };
      }
      if (metadata.provider === 'admin_subscription_clear') {
        return {
          description: metadata.reason
            ? `${transaction.description || 'Удаление подписки'} · ${metadata.reason}`
            : (transaction.description || 'Удаление подписки'),
          adminName: metadata.adminName || '—'
        };
      }

      if (metadata.provider === 'promo_code') {
        return {
          description: `${transaction.description || 'Промокод'} · ${metadata.promoCode || '—'}`,
          adminName: '—'
        };
      }

      if (metadata.provider === 'referral') {
        return {
          description: `${transaction.description || 'Реферал'} · ${metadata.appliedReferralCode || '—'}`,
          adminName: '—'
        };
      }

      return {
        description: transaction.description || '—',
        adminName: '—'
      };
    }

    function renderUserProfile() {
      if (!selectedUserProfile) {
        userProfileEmptyEl.style.display = '';
        userProfileContentEl.style.display = 'none';
        userProfileReferralsEl.innerHTML = '<div class="card"><div></div><div><p class="card-text">Нет данных.</p></div></div>';
        userTransactionsListEl.innerHTML = '<tr><td colspan="5">Транзакций пока нет.</td></tr>';
        return;
      }

      userProfileEmptyEl.style.display = 'none';
      userProfileContentEl.style.display = '';
      userProfileNameEl.textContent = selectedUserProfile.name || 'Без имени';
      userProfileEmailEl.textContent = selectedUserProfile.email || '—';
      userProfileIdEl.textContent = selectedUserProfile._id || '—';
      userProfileReferralCodeEl.textContent = selectedUserProfile.referralCode || '—';
      userProfileAppliedReferralCodeEl.textContent = selectedUserProfile.appliedReferralCode || '—';
      userProfileSubscriptionEl.textContent = formatSubscriptionStatus(selectedUserProfile);
      userProfileBalanceEl.textContent = `${formatMoney(selectedUserProfile.balance)} ₽`;
      userTargetBalanceInput.value = Number(selectedUserProfile.balance || 0).toFixed(2);

      const referrals = Array.isArray(selectedUserProfile.referrals)
        ? selectedUserProfile.referrals
        : [];

      if (!referrals.length) {
        userProfileReferralsEl.innerHTML = '<div class="card"><div></div><div><p class="card-text">Рефералов пока нет.</p></div></div>';
      } else {
        userProfileReferralsEl.innerHTML = referrals.map((referral) => `
          <div class="card">
            <div></div>
            <div>
              <h3 class="card-title">${escapeHtml(referral.name || 'Без имени')}</h3>
              <p class="card-meta">${escapeHtml(referral.email || '—')}</p>
              <p class="card-meta">Баланс: ${formatMoney(referral.balance)} ₽</p>
              <p class="card-meta">Дата: ${escapeHtml(formatDate(referral.referralAppliedAt || referral.createdAt))}</p>
            </div>
          </div>
        `).join('');
      }

      const transactions = Array.isArray(selectedUserProfile.transactions)
        ? selectedUserProfile.transactions
        : [];
      const transactionFilter = userTransactionFilterInput.value || 'all';
      const filteredTransactions = transactionFilter === 'all'
        ? transactions
        : transactions.filter((transaction) => transaction.type === transactionFilter);

      if (!filteredTransactions.length) {
        userTransactionsListEl.innerHTML = '<tr><td colspan="5">Транзакций пока нет.</td></tr>';
      } else {
        userTransactionsListEl.innerHTML = filteredTransactions.map((transaction) => {
          const meta = transactionExtraMeta(transaction);
          const sign = transaction.type === 'withdrawal' || transaction.type === 'payment' ? '-' : '+';
          return `
            <tr>
              <td>${escapeHtml(formatTransactionType(transaction.type))}</td>
              <td>${sign}${formatMoney(transaction.amount)} ₽</td>
              <td>${escapeHtml(meta.description)}</td>
              <td>${escapeHtml(meta.adminName)}</td>
              <td>${escapeHtml(formatDate(transaction.createdAt))}</td>
            </tr>
          `;
        }).join('');
      }
    }

    function resetPromoForm() {
      editingPromoCodeId = null;
      promoForm.reset();
      promoCodeActiveInput.value = 'true';
      promoCodeMaxRedemptionsInput.value = '';
      promoCodeCampaignInput.value = '';
      promoFormTitle.textContent = 'Промокод';
      promoSubmitBtn.textContent = 'Сохранить';
      setPromoStatus('');
    }

    function renderPromoCodes() {
      if (!promoCodes.length) {
        promoListEl.innerHTML = '<div class="card"><div></div><div><p class="card-text">Промокодов пока нет.</p></div></div>';
        return;
      }

      promoListEl.innerHTML = promoCodes.map((promoCode) => `
        <article class="card">
          <div class="tag ${promoCode.isActive ? 'success' : ''}">${promoCode.isActive ? 'Активен' : 'Отключён'}</div>
          <div>
            <h3 class="card-title mono">${escapeHtml(promoCode.code)}</h3>
            <p class="card-meta">Кампания: ${escapeHtml(promoCode.campaign || '—')}</p>
            <p class="card-meta">
              Сумма: ${formatMoney(promoCode.amount)} ₽ · Использований: ${escapeHtml(String(promoCode.redemptionsCount || 0))}${promoCode.maxRedemptions ? ` / ${escapeHtml(String(promoCode.maxRedemptions))}` : ''}
            </p>
            <p class="card-meta">Обновлён: ${escapeHtml(formatDate(promoCode.updatedAt))}</p>
            <div class="actions">
              <button type="button" data-promo-action="edit" data-id="${promoCode._id}">Редактировать</button>
              <button type="button" class="secondary" data-promo-action="toggle" data-id="${promoCode._id}">
                ${promoCode.isActive ? 'Отключить' : 'Включить'}
              </button>
              <button type="button" class="secondary" data-promo-action="redemptions" data-id="${promoCode._id}">
                Кто ввёл
              </button>
              <button type="button" class="danger" data-promo-action="delete" data-id="${promoCode._id}">
                Удалить
              </button>
            </div>
          </div>
        </article>
      `).join('');
    }

    function linkedWishForRequest(requestId) {
      return wishes.find((wish) => wish.requestId === requestId) || null;
    }

	    function renderWishRequestOptions() {
      const selectedValue = editingWishId
        ? (wishes.find((item) => item._id === editingWishId)?.requestId || '')
        : '';

      const options = ['<option value="">Без привязки</option>'];

      wishRequests.forEach((requestItem) => {
        const linkedWish = linkedWishForRequest(requestItem._id);
        const isCurrentSelection = selectedValue === requestItem._id;
        const isDisabled = linkedWish && !isCurrentSelection;
        const suffix = linkedWish && !isCurrentSelection
          ? ` (уже опубликовано: ${linkedWish.text.slice(0, 28)}${linkedWish.text.length > 28 ? '...' : ''})`
          : '';

        options.push(
          `<option value="${requestItem._id}" ${isCurrentSelection ? 'selected' : ''} ${isDisabled ? 'disabled' : ''}>${escapeHtml(requestItem.text)}${escapeHtml(suffix)}</option>`
        );
      });

	      wishRequestIdSelect.innerHTML = options.join('');
	    }

	    function sortedWishes() {
	      const sortMode = wishSortInput.value || 'score_desc';
	      const dateValue = (value) => {
	        const timestamp = Date.parse(value || '');
	        return Number.isNaN(timestamp) ? 0 : timestamp;
	      };
	      const scoreValue = (wish) => Number(wish.likeCount || 0) - Number(wish.dislikeCount || 0);
	      const tieBreakByDate = (left, right) => dateValue(right.updatedAt) - dateValue(left.updatedAt);

	      return [...wishes].sort((left, right) => {
	        if (sortMode === 'score_asc') {
	          return scoreValue(left) - scoreValue(right) || tieBreakByDate(left, right);
	        }
	        if (sortMode === 'score_desc') {
	          return scoreValue(right) - scoreValue(left) || tieBreakByDate(left, right);
	        }
	        if (sortMode === 'date_asc') {
	          return dateValue(left.updatedAt) - dateValue(right.updatedAt);
	        }
	        if (sortMode === 'likes_desc') {
	          return Number(right.likeCount || 0) - Number(left.likeCount || 0) || tieBreakByDate(left, right);
	        }
	        if (sortMode === 'likes_asc') {
	          return Number(left.likeCount || 0) - Number(right.likeCount || 0) || tieBreakByDate(left, right);
	        }
	        if (sortMode === 'dislikes_desc') {
	          return Number(right.dislikeCount || 0) - Number(left.dislikeCount || 0) || tieBreakByDate(left, right);
	        }
	        if (sortMode === 'dislikes_asc') {
	          return Number(left.dislikeCount || 0) - Number(right.dislikeCount || 0) || tieBreakByDate(left, right);
	        }
	        return tieBreakByDate(left, right);
	      });
	    }

	    function renderWishes() {
	      if (!wishes.length) {
        wishListEl.innerHTML = '<div class="card"><div></div><div><p class="card-text">Пожеланий пока нет.</p></div></div>';
        return;
      }

	      wishListEl.innerHTML = sortedWishes().map((wish) => {
        const sourceRequest = wish.requestId
          ? wishRequests.find((item) => item._id === wish.requestId)
          : null;
        const score = Number(wish.likeCount || 0) - Number(wish.dislikeCount || 0);

        return `
          <article class="card">
            <div class="tag">Рейтинг ${score} · ${wish.likeCount} 👍 / ${wish.dislikeCount} 👎</div>
            <div>
              <h3 class="card-title">${escapeHtml(wish.text)}</h3>
              <p class="card-meta">
                ${sourceRequest ? escapeHtml(sourceRequest.text) : 'Без привязки'} · ${escapeHtml(formatDate(wish.updatedAt))}
              </p>
              <div class="actions">
                <button type="button" data-wish-action="edit" data-id="${wish._id}">Редактировать</button>
                <button type="button" data-wish-action="delete" data-id="${wish._id}" class="danger">Удалить</button>
              </div>
            </div>
          </article>
        `;
      }).join('');
    }

    function renderWishRequests() {
      if (!wishRequests.length) {
        wishRequestsListEl.innerHTML = '<div class="card"><div></div><div><p class="card-text">Запросов пока нет.</p></div></div>';
        return;
      }

      wishRequestsListEl.innerHTML = wishRequests.map((requestItem) => {
        const linkedWish = linkedWishForRequest(requestItem._id);

        return `
          <article class="card">
            <div class="tag ${linkedWish ? 'success' : ''}">${linkedWish ? 'Опубликовано' : 'Новый запрос'}</div>
            <div>
              <h3 class="card-title">${escapeHtml(requestItem.text)}</h3>
              <p class="card-meta">
                <span class="mono">${escapeHtml(requestItem.userId || '—')}</span> · ${escapeHtml(formatDate(requestItem.createdAt))}
              </p>
              <div class="actions">
                <button type="button" data-request-action="${linkedWish ? 'edit-linked' : 'publish'}" data-id="${requestItem._id}">
                  ${linkedWish ? 'Открыть' : 'Создать'}
                </button>
                <button type="button" data-request-action="delete" data-id="${requestItem._id}" class="danger">
                  Удалить
                </button>
              </div>
            </div>
          </article>
        `;
      }).join('');
    }

    async function request(url, options = {}) {
      const response = await fetch(url, {
        headers: { 'Content-Type': 'application/json' },
        ...options
      });

      // Если сессия админки закончилась, возвращаем менеджера на экран входа.
      if (response.status === 401) {
        window.location.href = `${adminBasePath}/login?next=${encodeURIComponent(window.location.pathname)}`;
        throw new Error('Нужно войти в админку');
      }

      const data = await response.json();
      if (!response.ok || data.status !== 'success') {
        throw new Error(data.errorMessage || 'Request failed');
      }

      return data.data;
    }

    async function uploadAvatarFile(file) {
      if (!file) {
        return;
      }

      setAvatarUploadStatus('Загрузка...');

      const dataUrl = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(new Error('Не удалось прочитать файл'));
        reader.readAsDataURL(file);
      });

      try {
        const result = await request(`${adminBasePath}/api/characters/avatar-upload`, {
          method: 'POST',
          body: JSON.stringify({
            fileName: file.name,
            dataUrl
          })
        });

        updateAvatarPreview(result.url, file.name);
        setAvatarUploadStatus('Загружено', 'success');
      } catch (error) {
        updateAvatarPreview('');
        setAvatarUploadStatus(error.message, 'error');
      }
    }

    async function loadCharacters() {
      setStatus('');
      try {
        characters = await request(characterApiBase);
        renderList();
        setStatus('');
      } catch (error) {
        setStatus(error.message, 'error');
      }
    }

    async function submitForm(event) {
      event.preventDefault();
      const payload = formPayload();

      if (!payload.avatarUrl) {
        setStatus('Сначала загрузите фото', 'error');
        return;
      }

      try {
        setStatus(editingId ? 'Сохраняю изменения...' : 'Создаю психолога...');
        const url = editingId ? `${characterApiBase}/${editingId}` : characterApiBase;
        const method = editingId ? 'PUT' : 'POST';
        await request(url, { method, body: JSON.stringify(payload) });
        resetForm();
        await loadCharacters();
      } catch (error) {
        setStatus(error.message, 'error');
      }
    }

    function editCharacter(id) {
      const character = characters.find((item) => item._id === id);
      if (!character) return;

      editingId = id;
      formTitle.textContent = `Редактирование: ${character.name}`;
      submitBtn.textContent = 'Обновить';
      translateBtn.disabled = false;
      fieldTranslateButtons.forEach((button) => { button.disabled = false; });
      document.getElementById('name').value = character.name;
      avatarFileInput.value = '';
      updateAvatarPreview(character.avatarUrl, character.name);
      setAvatarUploadStatus('');
      document.getElementById('systemPrompt').value = character.systemPrompt;
      document.getElementById('shortDescription').value = character.shortDescription || '';
      document.getElementById('longDescription').value = character.longDescription || character.shortDescription || '';
      applyLocalizedFields(character);
      setStatus('');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    function applyLocalizedFields(character) {
      document.getElementById('nameEn').value = character.localizedNames?.en || '';
      document.getElementById('nameBe').value = character.localizedNames?.be || '';
      document.getElementById('shortDescriptionEn').value = character.localizedShortDescriptions?.en || '';
      document.getElementById('longDescriptionEn').value = character.localizedLongDescriptions?.en || '';
      document.getElementById('shortDescriptionBe').value = character.localizedShortDescriptions?.be || '';
      document.getElementById('longDescriptionBe').value = character.localizedLongDescriptions?.be || '';
    }

    async function translateCharacterField(button) {
      if (!editingId) {
        setStatus('Сначала сохраните психолога, затем запустите перевод', 'error');
        return;
      }

      const field = button.dataset.field;
      const language = button.dataset.language;
      const target = document.getElementById(button.dataset.target);
      const previousText = button.textContent;

      try {
        button.disabled = true;
        button.textContent = '...';
        setStatus('Перевожу поле через DeepSeek...');
        const character = await request(`${characterApiBase}/${editingId}/translate`, {
          method: 'POST',
          body: JSON.stringify({ field, language })
        });
        if (target) {
          target.value = character.localizedNames?.[language] && field === 'name'
            ? character.localizedNames[language]
            : field === 'shortDescription'
              ? character.localizedShortDescriptions?.[language] || ''
              : character.localizedLongDescriptions?.[language] || '';
        }
        await loadCharacters();
        setStatus('Перевод сохранён', 'success');
      } catch (error) {
        setStatus(error.message, 'error');
      } finally {
        button.disabled = false;
        button.textContent = previousText;
      }
    }

    async function translateCharacter() {
      if (!editingId) {
        setStatus('Сначала сохраните психолога, затем запустите перевод', 'error');
        return;
      }

      try {
        translateBtn.disabled = true;
        setStatus('Перевожу имя и описания через DeepSeek...');
        const character = await request(`${characterApiBase}/${editingId}/translate`, {
          method: 'POST',
          body: JSON.stringify({})
        });
        applyLocalizedFields(character);
        await loadCharacters();
        setStatus('Переводы сохранены', 'success');
      } catch (error) {
        setStatus(error.message, 'error');
      } finally {
        translateBtn.disabled = !editingId;
      }
    }

    async function deleteCharacter(id) {
      const character = characters.find((item) => item._id === id);
      if (!character) return;

      if (!window.confirm(`Удалить психолога "${character.name}"?`)) {
        return;
      }

      try {
        setStatus('Удаляю психолога...');
        await request(`${characterApiBase}/${id}`, { method: 'DELETE' });
        if (editingId === id) {
          resetForm();
        }
        await loadCharacters();
      } catch (error) {
        setStatus(error.message, 'error');
      }
    }

    async function loadBillingSettings() {
      setBillingStatus('');
      try {
        const settings = await request(billingSettingsApiBase);
        const requestPrice = Number(settings.requestPrice || 0);
        const referralBonusAmount = Number(settings.referralBonusAmount || 0);
        const subscription = settings.subscription || {};
        const subscriptionName = subscription.name || 'Плюс';
        const subscriptionPrice = Number(subscription.price || 0);
        requestPriceInput.value = requestPrice.toFixed(2);
        referralBonusAmountInput.value = referralBonusAmount.toFixed(2);
        subscriptionNameInput.value = subscriptionName;
        subscriptionPriceInput.value = subscriptionPrice.toFixed(2);
        currentPriceEl.textContent = `${formatMoney(requestPrice)} ₽ → 149 ₽ → 99 ₽`;
        currentReferralBonusEl.textContent = `${formatMoney(referralBonusAmount)} ₽`;
        currentSubscriptionEl.textContent = `${subscriptionName} · ${formatMoney(subscriptionPrice)} ₽ / месяц`;
        setBillingStatus('');
      } catch (error) {
        setBillingStatus(error.message, 'error');
      }
    }

    async function loadRequestPackages() {
      try {
        setRequestPackagesStatus('');
        requestPackages = await request(requestPackagesApiBase);
        renderRequestPackages();
      } catch (error) {
        setRequestPackagesStatus(error.message, 'error');
      }
    }

    async function loadAppVersionSettings() {
      setAppStatus('');
      try {
        const settings = await request(appVersionApiBase);
        requiredAppVersionInput.value = settings.requiredVersion || '';
        currentAppVersionEl.textContent = settings.requiredVersion || '—';
        currentAppVersionUpdatedEl.textContent = formatDate(settings.updatedAt);
      } catch (error) {
        setAppStatus(error.message, 'error');
      }
    }

    async function submitAppForm(event) {
      event.preventDefault();
      const requiredVersion = requiredAppVersionInput.value.trim();
      if (!requiredVersion) {
        setAppStatus('Введите версию приложения', 'error');
        return;
      }

      try {
        setAppStatus('Сохраняю версию...');
        const settings = await request(appVersionApiBase, {
          method: 'PUT',
          body: JSON.stringify({ requiredVersion })
        });
        requiredAppVersionInput.value = settings.requiredVersion || '';
        currentAppVersionEl.textContent = settings.requiredVersion || '—';
        currentAppVersionUpdatedEl.textContent = formatDate(settings.updatedAt);
        setAppStatus('Сохранено', 'success');
      } catch (error) {
        setAppStatus(error.message, 'error');
      }
    }

    async function loadCharges() {
      setBillingStatus('');
      try {
        charges = await request(`${billingChargesApiBase}?limit=100`);
        renderCharges();
        setBillingStatus('');
      } catch (error) {
        setBillingStatus(error.message, 'error');
      }
    }

    async function loadUsers() {
      setUsersStatus('');
      try {
        users = await request(usersApiBase);
        renderUsers();
        setUsersStatus('');
      } catch (error) {
        setUsersStatus(error.message, 'error');
      }
    }

    async function loadUserProfile(userId) {
      setUserProfileStatus('');
      try {
        selectedUserProfile = await request(`${usersApiBase}/${userId}`);
        renderUserProfile();
        setUserProfileStatus('');
        activateTab('users');
        userProfileContentEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
      } catch (error) {
        setUserProfileStatus(error.message, 'error');
      }
    }

    async function loadPromoCodes() {
      setPromoStatus('');
      try {
        promoCodes = await request(promoCodesApiBase);
        renderPromoCodes();
        setPromoStatus('');
      } catch (error) {
        setPromoStatus(error.message, 'error');
      }
    }

    async function loadWishes() {
      setWishStatus('');
      try {
        wishes = await request(wishesApiBase);
        renderWishRequestOptions();
        renderWishes();
        renderWishRequests();
        setWishStatus('');
      } catch (error) {
        setWishStatus(error.message, 'error');
      }
    }

    async function loadWishRequests() {
      setWishStatus('');
      try {
        wishRequests = await request(wishRequestsApiBase);
        renderWishRequestOptions();
        renderWishes();
        renderWishRequests();
        setWishStatus('');
      } catch (error) {
        setWishStatus(error.message, 'error');
      }
    }

    async function reloadWishData() {
      await loadWishRequests();
      await loadWishes();
    }

    async function submitBillingForm(event) {
      event.preventDefault();

      const requestPrice = Number(requestPriceInput.value);
      const referralBonusAmount = Number(referralBonusAmountInput.value);
      const subscriptionName = subscriptionNameInput.value.trim();
      const subscriptionPrice = Number(subscriptionPriceInput.value);
      if (Number.isNaN(requestPrice) || requestPrice < 0) {
        setBillingStatus('Введите корректную неотрицательную цену', 'error');
        return;
      }
      if (Number.isNaN(referralBonusAmount) || referralBonusAmount < 0) {
        setBillingStatus('Введите корректный неотрицательный бонус за реферала', 'error');
        return;
      }
      if (!subscriptionName) {
        setBillingStatus('Введите название подписки', 'error');
        return;
      }
      if (Number.isNaN(subscriptionPrice) || subscriptionPrice <= 0) {
        setBillingStatus('Введите корректную цену подписки', 'error');
        return;
      }

      try {
        setBillingStatus('Сохраняю настройки...');
        const settings = await request(billingSettingsApiBase, {
          method: 'PUT',
          body: JSON.stringify({
            requestPrice,
            referralBonusAmount,
            subscriptionName,
            subscriptionPrice
          })
        });

        const savedPrice = Number(settings.requestPrice || 0);
        const savedReferralBonusAmount = Number(settings.referralBonusAmount || 0);
        const savedSubscription = settings.subscription || {};
        const savedSubscriptionName = savedSubscription.name || subscriptionName;
        const savedSubscriptionPrice = Number(savedSubscription.price || subscriptionPrice);
        requestPriceInput.value = savedPrice.toFixed(2);
        referralBonusAmountInput.value = savedReferralBonusAmount.toFixed(2);
        subscriptionNameInput.value = savedSubscriptionName;
        subscriptionPriceInput.value = savedSubscriptionPrice.toFixed(2);
        currentPriceEl.textContent = `${formatMoney(savedPrice)} ₽ → 149 ₽ → 99 ₽`;
        currentReferralBonusEl.textContent = `${formatMoney(savedReferralBonusAmount)} ₽`;
        currentSubscriptionEl.textContent = `${savedSubscriptionName} · ${formatMoney(savedSubscriptionPrice)} ₽ / месяц`;
        setBillingStatus('Сохранено', 'success');
      } catch (error) {
        setBillingStatus(error.message, 'error');
      }
    }

    async function submitRequestPackageForm(event) {
      event.preventDefault();
      // Менеджер задаёт коммерческое предложение:
      // сколько консультационных запросов входит в пакет и сколько он стоит.
      const requestCount = Number(requestPackageCountInput.value);
      const price = Number(requestPackagePriceInput.value);
      const isActive = requestPackageActiveInput.value === 'true';

      if (!Number.isInteger(requestCount) || requestCount < 10) {
        setRequestPackagesStatus('В пакете должно быть минимум 10 запросов', 'error');
        return;
      }
      if (Number.isNaN(price) || price <= 0) {
        setRequestPackagesStatus('Введите корректную цену пакета', 'error');
        return;
      }

      try {
        setRequestPackagesStatus('Сохраняю пакет...');
        const url = editingRequestPackageId
          ? `${requestPackagesApiBase}/${editingRequestPackageId}`
          : requestPackagesApiBase;
        await request(url, {
          method: editingRequestPackageId ? 'PUT' : 'POST',
          body: JSON.stringify({ requestCount, price, isActive })
        });
        resetRequestPackageForm();
        await loadRequestPackages();
        setRequestPackagesStatus('Пакет сохранён', 'success');
      } catch (error) {
        setRequestPackagesStatus(error.message, 'error');
      }
    }

    function editRequestPackage(id) {
      // Редактирование подставляет выбранный товар в форму,
      // чтобы менеджер мог быстро изменить цену, объём или видимость.
      const item = requestPackages.find((packageItem) => packageItem._id === id);
      if (!item) return;

      editingRequestPackageId = id;
      requestPackageCountInput.value = item.requestCount;
      requestPackagePriceInput.value = Number(item.price || 0).toFixed(2);
      requestPackageActiveInput.value = item.isActive ? 'true' : 'false';
      requestPackageSubmitBtn.textContent = 'Обновить пакет';
      setRequestPackagesStatus('');
    }

    async function deleteRequestPackage(id) {
      // Удаление убирает пакет из продажи, если он больше не нужен бизнесу.
      const item = requestPackages.find((packageItem) => packageItem._id === id);
      if (!item || !window.confirm(`Удалить пакет на ${item.requestCount} запросов?`)) {
        return;
      }

      try {
        setRequestPackagesStatus('Удаляю пакет...');
        await request(`${requestPackagesApiBase}/${id}`, { method: 'DELETE' });
        await loadRequestPackages();
        setRequestPackagesStatus('Пакет удалён', 'success');
      } catch (error) {
        setRequestPackagesStatus(error.message, 'error');
      }
    }

    async function submitWishForm(event) {
      event.preventDefault();
      const payload = wishFormPayload();

      try {
        setWishStatus(editingWishId ? 'Сохраняю пожелание...' : 'Создаю пожелание...');
        const url = editingWishId ? `${wishesApiBase}/${editingWishId}` : wishesApiBase;
        const method = editingWishId ? 'PUT' : 'POST';
        await request(url, { method, body: JSON.stringify(payload) });
        resetWishForm();
        await reloadWishData();
        setWishStatus('Сохранено', 'success');
      } catch (error) {
        setWishStatus(error.message, 'error');
      }
    }

    async function submitUserBalanceForm(event) {
      event.preventDefault();

      if (!selectedUserProfile || !selectedUserProfile._id) {
        setUserProfileStatus('Сначала откройте профиль пользователя', 'error');
        return;
      }

      const adminName = balanceAdminNameInput.value.trim();
      const targetBalance = Number(userTargetBalanceInput.value);
      const reason = userBalanceReasonInput.value.trim();

      if (!adminName) {
        setUserProfileStatus('Укажите, кто меняет баланс', 'error');
        return;
      }

      if (Number.isNaN(targetBalance) || targetBalance < 0) {
        setUserProfileStatus('Введите корректный баланс', 'error');
        return;
      }

      try {
        setUserProfileStatus('Сохраняю баланс...');
        const result = await request(`${usersApiBase}/${selectedUserProfile._id}/balance`, {
          method: 'PUT',
          body: JSON.stringify({
            adminName,
            targetBalance,
            reason
          })
        });

        selectedUserProfile = result.user;
        renderUserProfile();
        await loadUsers();
        setUserProfileStatus('Баланс обновлён', 'success');
      } catch (error) {
        setUserProfileStatus(error.message, 'error');
      }
    }

    async function submitUserSubscriptionForm(event) {
      event.preventDefault();

      if (!selectedUserProfile || !selectedUserProfile._id) {
        setUserProfileStatus('Сначала откройте профиль пользователя', 'error');
        return;
      }

      const adminName = subscriptionAdminNameInput.value.trim();
      const days = Number(userSubscriptionDaysInput.value);
      const reason = userSubscriptionReasonInput.value.trim();

      if (!adminName) {
        setUserProfileStatus('Укажите, кто выдаёт подписку', 'error');
        return;
      }

      if (!Number.isInteger(days) || days <= 0) {
        setUserProfileStatus('Введите корректное количество дней', 'error');
        return;
      }

      try {
        setUserProfileStatus('Выдаю подписку...');
        const result = await request(`${usersApiBase}/${selectedUserProfile._id}/subscription`, {
          method: 'PUT',
          body: JSON.stringify({
            adminName,
            days,
            reason
          })
        });

        selectedUserProfile = result.user;
        renderUserProfile();
        await loadUsers();
        setUserProfileStatus('Подписка выдана', 'success');
      } catch (error) {
        setUserProfileStatus(error.message, 'error');
      }
    }

    async function clearUserSubscription() {
      if (!selectedUserProfile || !selectedUserProfile._id) {
        setUserProfileStatus('Сначала откройте профиль пользователя', 'error');
        return;
      }

      const adminName = subscriptionAdminNameInput.value.trim();
      const reason = userSubscriptionReasonInput.value.trim();
      if (!adminName) {
        setUserProfileStatus('Укажите, кто удаляет подписку', 'error');
        return;
      }

      if (!window.confirm(`Удалить подписку у пользователя "${selectedUserProfile.name || selectedUserProfile.email || selectedUserProfile._id}"?`)) {
        return;
      }

      try {
        setUserProfileStatus('Удаляю подписку...');
        const result = await request(`${usersApiBase}/${selectedUserProfile._id}/subscription`, {
          method: 'DELETE',
          body: JSON.stringify({
            adminName,
            reason
          })
        });

        selectedUserProfile = result.user;
        renderUserProfile();
        await loadUsers();
        setUserProfileStatus('Подписка удалена', 'success');
      } catch (error) {
        setUserProfileStatus(error.message, 'error');
      }
    }

    async function submitPromoForm(event) {
      event.preventDefault();

      const code = promoCodeValueInput.value.trim().toUpperCase();
      const campaign = promoCodeCampaignInput.value.trim();
      const amount = Number(promoCodeAmountInput.value);
      const maxRedemptionsRaw = promoCodeMaxRedemptionsInput.value.trim();
      const maxRedemptions = maxRedemptionsRaw ? Number(maxRedemptionsRaw) : null;
      const isActive = promoCodeActiveInput.value === 'true';

      if (!code) {
        setPromoStatus('Введите код', 'error');
        return;
      }

      if (Number.isNaN(amount) || amount <= 0) {
        setPromoStatus('Введите корректную положительную сумму', 'error');
        return;
      }

      if (maxRedemptionsRaw && (!Number.isInteger(maxRedemptions) || maxRedemptions <= 0)) {
        setPromoStatus('Введите корректный лимит активаций', 'error');
        return;
      }

      try {
        setPromoStatus(editingPromoCodeId ? 'Сохраняю промокод...' : 'Создаю промокод...');
        const url = editingPromoCodeId
          ? `${promoCodesApiBase}/${editingPromoCodeId}`
          : promoCodesApiBase;
        const method = editingPromoCodeId ? 'PUT' : 'POST';
        await request(url, {
          method,
          body: JSON.stringify({ code, campaign, amount, isActive, maxRedemptions })
        });
        resetPromoForm();
        await loadPromoCodes();
        setPromoStatus('Сохранено', 'success');
      } catch (error) {
        setPromoStatus(error.message, 'error');
      }
    }

    function editPromoCode(id) {
      const promoCode = promoCodes.find((item) => item._id === id);
      if (!promoCode) return;

      editingPromoCodeId = id;
      promoFormTitle.textContent = `Редактирование: ${promoCode.code}`;
      promoSubmitBtn.textContent = 'Обновить';
      promoCodeValueInput.value = promoCode.code || '';
      promoCodeCampaignInput.value = promoCode.campaign || '';
      promoCodeAmountInput.value = Number(promoCode.amount || 0).toFixed(2);
      promoCodeMaxRedemptionsInput.value = promoCode.maxRedemptions || '';
      promoCodeActiveInput.value = promoCode.isActive ? 'true' : 'false';
      setPromoStatus('');
      window.scrollTo({ top: 0, behavior: 'smooth' });
      activateTab('promo-codes');
    }

    async function togglePromoCode(id) {
      const promoCode = promoCodes.find((item) => item._id === id);
      if (!promoCode) return;

      try {
        setPromoStatus('Обновляю статус...');
        await request(`${promoCodesApiBase}/${id}`, {
          method: 'PUT',
          body: JSON.stringify({
            isActive: !promoCode.isActive
          })
        });
        await loadPromoCodes();
        setPromoStatus('Статус обновлён', 'success');
      } catch (error) {
        setPromoStatus(error.message, 'error');
      }
    }

    async function deletePromoCode(id) {
      const promoCode = promoCodes.find((item) => item._id === id);
      if (!promoCode) return;

      if (!window.confirm(`Удалить промокод "${promoCode.code}"?`)) {
        return;
      }

      try {
        setPromoStatus('Удаляю промокод...');
        await request(`${promoCodesApiBase}/${id}`, {
          method: 'DELETE'
        });
        if (editingPromoCodeId === id) {
          resetPromoForm();
        }
        await loadPromoCodes();
        setPromoStatus('Промокод удалён', 'success');
      } catch (error) {
        setPromoStatus(error.message, 'error');
      }
    }

    function showPromoCodeRedemptions(id) {
      const promoCode = promoCodes.find((item) => item._id === id);
      if (!promoCode) return;

      const redemptions = Array.isArray(promoCode.redemptions)
        ? promoCode.redemptions
        : [];

      if (!redemptions.length) {
        window.alert(`Промокод "${promoCode.code}" ещё никто не вводил.`);
        return;
      }

      const lines = redemptions.map((item, index) => {
        const name = item.userName || 'Без имени';
        const email = item.userEmail || '—';
        const userId = item.userId || '—';
        const date = formatDate(item.redeemedAt);
        return `${index + 1}. ${name} <${email}> | ${userId} | ${date}`;
      });

      window.alert(`Промокод: ${promoCode.code}\nКампания: ${promoCode.campaign || '—'}\n\n${lines.join('\n')}`);
    }

    function editWish(id) {
      const wish = wishes.find((item) => item._id === id);
      if (!wish) return;

      editingWishId = id;
      wishFormTitle.textContent = 'Редактирование пожелания';
      wishSubmitBtn.textContent = 'Обновить';
      wishTextInput.value = wish.text;
      renderWishRequestOptions();
      wishRequestIdSelect.value = wish.requestId || '';
      setWishStatus('');
      window.scrollTo({ top: wishForm.offsetTop - 40, behavior: 'smooth' });
    }

    function createWishFromRequest(requestId) {
      const requestItem = wishRequests.find((item) => item._id === requestId);
      if (!requestItem) return;

      resetWishForm();
      wishTextInput.value = requestItem.text;
      wishRequestIdSelect.value = requestItem._id;
      wishFormTitle.textContent = 'Пожелание';
      setWishStatus('');
      window.scrollTo({ top: wishForm.offsetTop - 40, behavior: 'smooth' });
    }

    async function deleteWish(id) {
      const wish = wishes.find((item) => item._id === id);
      if (!wish) return;

      if (!window.confirm(`Удалить пожелание "${wish.text}"?`)) {
        return;
      }

      try {
        setWishStatus('Удаляю пожелание...');
        await request(`${wishesApiBase}/${id}`, { method: 'DELETE' });
        if (editingWishId === id) {
          resetWishForm();
        }
        await reloadWishData();
        setWishStatus('Удалено', 'success');
      } catch (error) {
        setWishStatus(error.message, 'error');
      }
    }

    async function deleteWishRequest(id) {
      const requestItem = wishRequests.find((item) => item._id === id);
      if (!requestItem) return;

      const linkedWish = linkedWishForRequest(id);
      const linkedText = linkedWish
        ? ' Привязанное опубликованное пожелание останется, но будет отвязано от запроса.'
        : '';
      if (!window.confirm(`Удалить запрос "${requestItem.text}"?${linkedText}`)) {
        return;
      }

      try {
        setWishStatus('Удаляю запрос...');
        await request(`${wishRequestsApiBase}/${id}`, { method: 'DELETE' });
        await reloadWishData();
        setWishStatus('Запрос удалён', 'success');
      } catch (error) {
        setWishStatus(error.message, 'error');
      }
    }

    async function clearWishRequests() {
      if (!wishRequests.length) {
        return;
      }

      if (!window.confirm(`Удалить все запросы (${wishRequests.length})? Опубликованные пожелания останутся, но будут отвязаны от запросов.`)) {
        return;
      }

      try {
        setWishStatus('Очищаю запросы...');
        await request(wishRequestsApiBase, { method: 'DELETE' });
        await reloadWishData();
        setWishStatus('Запросы очищены', 'success');
      } catch (error) {
        setWishStatus(error.message, 'error');
      }
    }

    function activateTab(tabName) {
      tabButtons.forEach((button) => {
        button.classList.toggle('is-active', button.dataset.tab === tabName);
      });
      tabPanels.forEach((panel) => {
        panel.classList.toggle('is-active', panel.dataset.tabPanel === tabName);
      });
    }

    listEl.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-action]');
      if (!button) return;

      const id = button.dataset.id;
      const action = button.dataset.action;
      if (action === 'edit') {
        editCharacter(id);
      } else if (action === 'delete') {
        deleteCharacter(id);
      }
    });

    usersListEl.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-user-action]');
      if (!button) return;

      const id = button.dataset.id;
      const action = button.dataset.userAction;
      if (action === 'open') {
        loadUserProfile(id);
      }
    });

    promoListEl.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-promo-action]');
      if (!button) return;

      const id = button.dataset.id;
      const action = button.dataset.promoAction;
      if (action === 'edit') {
        editPromoCode(id);
      } else if (action === 'toggle') {
        togglePromoCode(id);
      } else if (action === 'redemptions') {
        showPromoCodeRedemptions(id);
      } else if (action === 'delete') {
        deletePromoCode(id);
      }
    });

    requestPackagesListEl.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-package-action]');
      if (!button) return;

      const id = button.dataset.id;
      const action = button.dataset.packageAction;
      if (action === 'edit') {
        editRequestPackage(id);
      } else if (action === 'delete') {
        deleteRequestPackage(id);
      }
    });

	    userTransactionFilterInput.addEventListener('change', () => {
	      renderUserProfile();
	    });

	    wishSortInput.addEventListener('change', renderWishes);

	    wishListEl.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-wish-action]');
      if (!button) return;

      const id = button.dataset.id;
      const action = button.dataset.wishAction;
      if (action === 'edit') {
        editWish(id);
      } else if (action === 'delete') {
        deleteWish(id);
      }
    });

    wishRequestsListEl.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-request-action]');
      if (!button) return;

      const requestId = button.dataset.id;
      const action = button.dataset.requestAction;
      if (action === 'publish') {
        createWishFromRequest(requestId);
      } else if (action === 'edit-linked') {
        const linkedWish = linkedWishForRequest(requestId);
        if (linkedWish) {
          editWish(linkedWish._id);
        }
      } else if (action === 'delete') {
        deleteWishRequest(requestId);
      }
    });
    wishRequestsClearBtn.addEventListener('click', clearWishRequests);

    tabButtons.forEach((button) => {
      button.addEventListener('click', () => activateTab(button.dataset.tab));
    });

    avatarFileInput.addEventListener('change', async () => {
      const [file] = avatarFileInput.files || [];
      await uploadAvatarFile(file);
    });

    form.addEventListener('submit', submitForm);
    appForm.addEventListener('submit', submitAppForm);
    translateBtn.addEventListener('click', translateCharacter);
    fieldTranslateButtons.forEach((button) => {
      button.addEventListener('click', () => translateCharacterField(button));
    });
    resetBtn.addEventListener('click', resetForm);
    billingForm.addEventListener('submit', submitBillingForm);
    requestPackageForm.addEventListener('submit', submitRequestPackageForm);
    requestPackageResetBtn.addEventListener('click', resetRequestPackageForm);
    userBalanceForm.addEventListener('submit', submitUserBalanceForm);
    userSubscriptionForm.addEventListener('submit', submitUserSubscriptionForm);
    userSubscriptionClearBtn.addEventListener('click', clearUserSubscription);
    promoForm.addEventListener('submit', submitPromoForm);
    promoResetBtn.addEventListener('click', resetPromoForm);
    wishForm.addEventListener('submit', submitWishForm);
    wishResetBtn.addEventListener('click', resetWishForm);

    loadCharacters();
    resetForm();
    loadAppVersionSettings();
    loadBillingSettings();
    resetRequestPackageForm();
    loadRequestPackages();
    loadCharges();
    loadUsers();
    renderUserProfile();
    resetPromoForm();
    loadPromoCodes();
    reloadWishData();
  </script>
</body>
</html>
''';
}
