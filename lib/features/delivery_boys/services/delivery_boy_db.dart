import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class DeliveryBoyDbService {
  static final DeliveryBoyDbService instance = DeliveryBoyDbService._init();
  DeliveryBoyDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  Future<int> addDeliveryBoy(String restaurantId, String name, String phone) async {
    final database = await _db;
    try {
      return await database.insert(
        DbConnection.tableDeliveryBoys,
        {'restaurant_id': restaurantId, 'name': name, 'phone': phone},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      return -1;
    }
  }

  Future<List<Map<String, String>>> getAllDeliveryBoys(String restaurantId) async {
    final database = await _db;
    final rows = await database.query(
      DbConnection.tableDeliveryBoys,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'name ASC',
    );
    return rows.map((r) => {
      'id': r['id'].toString(),
      'name': r['name'].toString(),
      'phone': r['phone'].toString(),
    }).toList();
  }

  /// Insert-or-replace, keyed by (restaurant_id, phone) — used to seed the
  /// local cache from the erp_backend response (add + refresh).
  Future<void> upsertDeliveryBoyLocal(String restaurantId, Map<String, dynamic> boy) async {
    final database = await _db;
    await database.insert(
      DbConnection.tableDeliveryBoys,
      {
        'restaurant_id': restaurantId,
        'name': boy['name'],
        'phone': boy['phone'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateDeliveryBoyNameLocal(String restaurantId, String phone, String newName) async {
    final database = await _db;
    await database.update(
      DbConnection.tableDeliveryBoys,
      {'name': newName},
      where: 'restaurant_id = ? AND phone = ?',
      whereArgs: [restaurantId, phone],
    );
  }

  Future<void> deleteDeliveryBoyLocal(String restaurantId, String phone) async {
    final database = await _db;
    await database.delete(
      DbConnection.tableDeliveryBoys,
      where: 'restaurant_id = ? AND phone = ?',
      whereArgs: [restaurantId, phone],
    );
  }
}