import 'package:main_api/src/services/billing/billing_service.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

class CustomContentService {
  DbCollection get _collections =>
      MongoService.instance.db.collection(Collections.customContentCollections);

  DbCollection get _items =>
      MongoService.instance.db.collection(Collections.customContentItems);

  Future<List<Map<String, dynamic>>> listCollections({
    required String appId,
    bool includeInactive = true,
  }) async {
    final selector = where.eq('appId', _appId(appId));
    if (!includeInactive) selector.eq('isActive', true);
    final rows = await _collections.find(selector).toList();
    rows.sort((a, b) => _string(a['name']).compareTo(_string(b['name'])));
    return rows.map(_publicCollection).toList(growable: false);
  }

  Future<Map<String, dynamic>?> getCollection({
    required String appId,
    required String collectionKey,
  }) async {
    final row = await _collections.findOne(
      where.eq('appId', _appId(appId)).eq('collectionKey', _key(collectionKey)),
    );
    return row == null ? null : _publicCollection(row);
  }

  Future<Map<String, dynamic>> createCollection({
    required String appId,
    required Map<String, dynamic> data,
  }) async {
    final normalizedAppId = _appId(appId);
    final collectionKey = _key(data['collectionKey'] ?? data['key']);
    if (collectionKey.isEmpty) {
      throw const FormatException('collectionKey is required');
    }
    final existing = await _collections.findOne(
      where.eq('appId', normalizedAppId).eq('collectionKey', collectionKey),
    );
    if (existing != null) {
      throw const FormatException('Collection already exists');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final row = {
      'appId': normalizedAppId,
      'app_id': normalizedAppId,
      'collectionKey': collectionKey,
      'key': collectionKey,
      'name': _string(data['name']).isEmpty
          ? collectionKey
          : _string(data['name']),
      'description': _nullableString(data['description']),
      'schema': _map(data['schema']),
      'settings': _map(data['settings']),
      'isActive': data['isActive'] != false,
      'createdAt': now,
      'updatedAt': now,
    };
    final result = await _collections.insertOne(row);
    if (!result.isSuccess) {
      throw StateError('Failed to create custom content collection');
    }
    final created = await _collections.findOne(where.eq('_id', result.id));
    return _publicCollection(created ?? row);
  }

  Future<Map<String, dynamic>?> updateCollection({
    required String appId,
    required String collectionKey,
    required Map<String, dynamic> data,
  }) async {
    final normalizedAppId = _appId(appId);
    final normalizedKey = _key(collectionKey);
    final existing = await _collections.findOne(
      where.eq('appId', normalizedAppId).eq('collectionKey', normalizedKey),
    );
    if (existing == null) return null;

    final changes = modify.set(
      'updatedAt',
      DateTime.now().toUtc().toIso8601String(),
    );
    if (data.containsKey('name')) changes.set('name', _string(data['name']));
    if (data.containsKey('description')) {
      changes.set('description', _nullableString(data['description']));
    }
    if (data.containsKey('schema')) changes.set('schema', _map(data['schema']));
    if (data.containsKey('settings')) {
      changes.set('settings', _map(data['settings']));
    }
    if (data.containsKey('isActive')) {
      changes.set('isActive', data['isActive'] != false);
    }

    await _collections.updateOne(
      where.eq('appId', normalizedAppId).eq('collectionKey', normalizedKey),
      changes,
    );
    final updated = await _collections.findOne(
      where.eq('appId', normalizedAppId).eq('collectionKey', normalizedKey),
    );
    return updated == null ? null : _publicCollection(updated);
  }

  Future<int> deleteCollection({
    required String appId,
    required String collectionKey,
    bool deleteItems = false,
  }) async {
    final normalizedAppId = _appId(appId);
    final normalizedKey = _key(collectionKey);
    final result = await _collections.deleteOne(
      where.eq('appId', normalizedAppId).eq('collectionKey', normalizedKey),
    );
    if (deleteItems) {
      await _items.deleteMany(
        where.eq('appId', normalizedAppId).eq('collectionKey', normalizedKey),
      );
    }
    return result.nRemoved;
  }

  Future<List<Map<String, dynamic>>> listItems({
    required String appId,
    required String collectionKey,
    bool includeInactive = false,
    String? q,
    List<String> tags = const [],
    int limit = 100,
    int skip = 0,
  }) async {
    final selector = where
        .eq('appId', _appId(appId))
        .eq('collectionKey', _key(collectionKey));
    if (!includeInactive) selector.eq('isActive', true);
    final normalizedTags = tags
        .map(_key)
        .where((tag) => tag.isNotEmpty)
        .toList();
    for (final tag in normalizedTags) {
      selector.eq('tags', tag);
    }
    final rows = await _items.find(selector).toList();
    final query = _string(q).toLowerCase();
    final filtered = query.isEmpty
        ? rows
        : rows.where((row) {
            return _string(row['title']).toLowerCase().contains(query) ||
                _string(row['description']).toLowerCase().contains(query) ||
                _string(row['itemId']).toLowerCase().contains(query);
          }).toList();
    filtered.sort((a, b) {
      final sortCompare = _int(a['sortOrder']).compareTo(_int(b['sortOrder']));
      if (sortCompare != 0) return sortCompare;
      return _string(b['updatedAt']).compareTo(_string(a['updatedAt']));
    });
    final safeSkip = skip < 0 ? 0 : skip;
    final safeLimit = limit.clamp(1, 500);
    return filtered
        .skip(safeSkip)
        .take(safeLimit)
        .map(_publicItem)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getItem({
    required String appId,
    required String collectionKey,
    required String itemId,
    bool includeInactive = false,
  }) async {
    final selector = where
        .eq('appId', _appId(appId))
        .eq('collectionKey', _key(collectionKey))
        .eq('itemId', _key(itemId));
    if (!includeInactive) selector.eq('isActive', true);
    final row = await _items.findOne(selector);
    return row == null ? null : _publicItem(row);
  }

  Future<Map<String, dynamic>> createItem({
    required String appId,
    required String collectionKey,
    required Map<String, dynamic> data,
  }) async {
    final normalizedAppId = _appId(appId);
    final normalizedKey = _key(collectionKey);
    final itemId = _key(data['itemId'] ?? data['slug'] ?? data['id']);
    if (itemId.isEmpty) {
      throw const FormatException('itemId is required');
    }
    final existing = await _items.findOne(
      where
          .eq('appId', normalizedAppId)
          .eq('collectionKey', normalizedKey)
          .eq('itemId', itemId),
    );
    if (existing != null) {
      throw const FormatException('Item already exists');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final row = {
      'appId': normalizedAppId,
      'app_id': normalizedAppId,
      'collectionKey': normalizedKey,
      'collection_key': normalizedKey,
      'itemId': itemId,
      'slug': itemId,
      'title': _string(data['title']),
      'description': _nullableString(data['description']),
      'imageUrl': _nullableString(data['imageUrl'] ?? data['image_url']),
      'data': _map(data['data']),
      'tags': _stringList(data['tags']),
      'sortOrder': _int(data['sortOrder'] ?? data['sort_order']),
      'isActive': data['isActive'] != false,
      'createdAt': now,
      'updatedAt': now,
    };
    final result = await _items.insertOne(row);
    if (!result.isSuccess) {
      throw StateError('Failed to create custom content item');
    }
    final created = await _items.findOne(where.eq('_id', result.id));
    return _publicItem(created ?? row);
  }

  Future<Map<String, dynamic>?> updateItem({
    required String appId,
    required String collectionKey,
    required String itemId,
    required Map<String, dynamic> data,
  }) async {
    final selector = where
        .eq('appId', _appId(appId))
        .eq('collectionKey', _key(collectionKey))
        .eq('itemId', _key(itemId));
    final existing = await _items.findOne(selector);
    if (existing == null) return null;

    final changes = modify.set(
      'updatedAt',
      DateTime.now().toUtc().toIso8601String(),
    );
    if (data.containsKey('title')) changes.set('title', _string(data['title']));
    if (data.containsKey('description')) {
      changes.set('description', _nullableString(data['description']));
    }
    if (data.containsKey('imageUrl') || data.containsKey('image_url')) {
      changes.set(
        'imageUrl',
        _nullableString(data['imageUrl'] ?? data['image_url']),
      );
    }
    if (data.containsKey('data')) changes.set('data', _map(data['data']));
    if (data.containsKey('tags')) {
      changes.set('tags', _stringList(data['tags']));
    }
    if (data.containsKey('sortOrder') || data.containsKey('sort_order')) {
      changes.set('sortOrder', _int(data['sortOrder'] ?? data['sort_order']));
    }
    if (data.containsKey('isActive')) {
      changes.set('isActive', data['isActive'] != false);
    }

    await _items.updateOne(selector, changes);
    final updated = await _items.findOne(selector);
    return updated == null ? null : _publicItem(updated);
  }

  Future<int> deleteItem({
    required String appId,
    required String collectionKey,
    required String itemId,
  }) async {
    final result = await _items.deleteOne(
      where
          .eq('appId', _appId(appId))
          .eq('collectionKey', _key(collectionKey))
          .eq('itemId', _key(itemId)),
    );
    return result.nRemoved;
  }

  static String _appId(String? value) => BillingService.normalizeAppId(value);

  static String _key(Object? value) => _string(value).trim().toLowerCase();

  static String _string(Object? value) => value?.toString() ?? '';

  static String? _nullableString(Object? value) {
    final text = _string(value).trim();
    return text.isEmpty ? null : text;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_string(value)) ?? 0;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map(_key).where((item) => item.isNotEmpty).toList();
  }

  static Map<String, dynamic> _publicCollection(Map<String, dynamic> row) {
    return {
      '_id': row['_id']?.toString(),
      'appId': row['appId'],
      'app_id': row['appId'],
      'collectionKey': row['collectionKey'],
      'key': row['collectionKey'],
      'name': row['name'],
      'description': row['description'],
      'schema': _map(row['schema']),
      'settings': _map(row['settings']),
      'isActive': row['isActive'] != false,
      'createdAt': row['createdAt'],
      'updatedAt': row['updatedAt'],
    };
  }

  static Map<String, dynamic> _publicItem(Map<String, dynamic> row) {
    return {
      '_id': row['_id']?.toString(),
      'appId': row['appId'],
      'app_id': row['appId'],
      'collectionKey': row['collectionKey'],
      'collection_key': row['collectionKey'],
      'itemId': row['itemId'],
      'slug': row['itemId'],
      'title': row['title'],
      'description': row['description'],
      'imageUrl': row['imageUrl'],
      'image_url': row['imageUrl'],
      'data': _map(row['data']),
      'tags': _stringList(row['tags']),
      'sortOrder': _int(row['sortOrder']),
      'sort_order': _int(row['sortOrder']),
      'isActive': row['isActive'] != false,
      'createdAt': row['createdAt'],
      'updatedAt': row['updatedAt'],
    };
  }
}
