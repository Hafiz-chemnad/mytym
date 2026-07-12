import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class AuthDbService {
  // Singleton pattern for the service
  static final AuthDbService instance = AuthDbService._init();
  AuthDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  Future<String?> getSessionRestaurantId() async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableActiveSession,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (result.isEmpty) return null;
    final id = result.first['restaurant_id'] as String?;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  Future<void> saveSessionRestaurantId(String restaurantId) async {
    final database = await _db;
    final existing = await database.query(
      DbConnection.tableActiveSession,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (existing.isEmpty) {
      await database.insert(DbConnection.tableActiveSession, {
        'id': 1,
        'restaurant_id': restaurantId,
      });
    } else {
      await database.update(
        DbConnection.tableActiveSession,
        {'restaurant_id': restaurantId},
        where: 'id = ?',
        whereArgs: [1],
      );
    }
  }

  Future<void> clearSession() async {
    final database = await _db;
    await database.update(
      DbConnection.tableActiveSession,
      {'restaurant_id': null},
      where: 'id = ?',
      whereArgs: [1],
    );
  }
}