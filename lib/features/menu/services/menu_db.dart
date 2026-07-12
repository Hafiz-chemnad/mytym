import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class MenuDbService {
  static final MenuDbService instance = MenuDbService._init();
  MenuDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

 Future<void> upsertMenuItem(
    String restaurantId,
    Map<String, dynamic> item, {
    String syncStatus = 'synced',
  }) async {
    final database = await _db;

    final map = {
      'restaurant_id': restaurantId,
      'retailer_id': item['id'] ?? item['retailerId'] ?? item['retailer_id'],
      'name': item['name'] ?? item['title'],
      'price': double.tryParse(item['price'].toString()) ?? 0.0,
      'category': item['category'] ?? item['description'] ?? 'Menu Item',
      
      // 🚀 FIX: Added item['image_url'] to catch the backend's JSON key
      'image_url': item['imageUrl'] ?? item['image_url'] ?? item['image_link'] ?? '',
      
      // 🚀 FIX: Also added snake_case fallbacks for your boolean toggles 
      // so your availability and veg/non-veg statuses sync correctly!
      'is_available': (item['isAvailable'] ?? item['is_available'] ?? true) ? 1 : 0,
      'is_veg': (item['isVeg'] ?? item['is_veg'] ?? false) ? 1 : 0,
      
      'sync_status': syncStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await database.insert(
      DbConnection.tableMenu,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllMenuItems(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableMenu,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'category ASC, name ASC',
    );

    return result.map((row) => {
      'id': row['retailer_id'],
      'retailerId': row['retailer_id'],
      'name': row['name'],
      'price': row['price'],
      'category': row['category'],
      'imageUrl': row['image_url'],
      'isAvailable': row['is_available'] == 1,
      'isVeg': row['is_veg'] == 1,
      'syncStatus': row['sync_status'],
    }).toList();
  }

  Future<void> deleteMenuItemLocally(String restaurantId, String retailerId) async {
    final database = await _db;
    await database.delete(
      DbConnection.tableMenu,
      where: 'restaurant_id = ? AND retailer_id = ?',
      whereArgs: [restaurantId, retailerId],
    );
  }
  Future<void> clearMenuLocally(String restaurantId) async {
    final database = await _db;
    await database.delete(
      DbConnection.tableMenu,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );
  }
}