import 'package:main_api/src/models/wish.dart';
import 'package:main_api/src/services/app_config.dart';
import 'package:main_api/src/services/database/collections.dart';
import 'package:main_api/src/services/database/mongo_service.dart';
import 'package:mongo_dart/mongo_dart.dart';

Future<void> main() async {
  AppConfig.loadEnv();
  await MongoService.instance.connect(AppConfig.mongoUri);

  try {
    final db = MongoService.instance.db;
    final appId = defaultWishAppId;

    final wishRequestsResult = await db.collection(
      Collections.wishRequests,
    ).updateMany(
      where.raw({
        '\$or': [
          {'appId': {'\$exists': false}},
          {'app_id': {'\$exists': false}},
          {'appId': null},
          {'app_id': null},
          {'appId': ''},
          {'app_id': ''},
        ],
      }),
      modify.set('appId', appId).set('app_id', appId),
    );

    final wishesResult = await db.collection(Collections.wishes).updateMany(
      where.raw({
        '\$or': [
          {'appId': {'\$exists': false}},
          {'app_id': {'\$exists': false}},
          {'appId': null},
          {'app_id': null},
          {'appId': ''},
          {'app_id': ''},
        ],
      }),
      modify.set('appId', appId).set('app_id', appId),
    );

    print(
      'Wish requests backfilled: ${wishRequestsResult.nModified}, wishes backfilled: ${wishesResult.nModified}',
    );
  } finally {
    await MongoService.instance.close();
  }
}
