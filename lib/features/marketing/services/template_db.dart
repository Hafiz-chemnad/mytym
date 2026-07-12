import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class TemplateDbService {
  static final TemplateDbService instance = TemplateDbService._init();
  TemplateDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  /// Saves or completely updates an incoming backend template mirror configuration locally.
  Future<void> upsertTemplate(String restaurantId, Map<String, dynamic> item) async {
    final database = await _db;
    
    // 🚀 Adjusted to correctly look for the mapping structure
    String mappingsJson = '{}';
    if (item.containsKey('default_mappings') && item['default_mappings'] != null) {
      mappingsJson = jsonEncode(item['default_mappings']);
    }
    String buttonsJson = '[]';
  if (item.containsKey('buttons') && item['buttons'] != null) {
    buttonsJson = jsonEncode(item['buttons']);
  }
    final map = {
      'restaurant_id': restaurantId,
      'template_id': item['template_id']?.toString() ?? '',
      'name': item['name'] ?? '',
      'category': item['category'] ?? 'MARKETING',
      'language': item['language'] ?? 'en_US',
      'body_text': item['body_text'] ?? '',
      'variable_count': int.tryParse(item['variable_count']?.toString() ?? '0') ?? 0,
      'status': item['status'] ?? 'PENDING',
      'rejected_reason': item['rejected_reason']?.toString(),
      'variable_mapping_json': mappingsJson, // 🚀 Renamed to exactly match the SQL Schema
      // In upsertTemplate(), add to the map:
      'header_type': item['header_type'] ?? 'NONE',
      'header_text': item['header_text'],
      'buttons_json': buttonsJson,  // 🚀 ADDED
      'created_at': item['created_at'] ?? DateTime.now().toIso8601String(), // 🚀 Preserved created_at mapping

      'updated_at': DateTime.now().toIso8601String(),
    };

    await database.insert(
      DbConnection.tableTemplates, // 🚀 Now uses centralized constant
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches everything in local cache to render the template list view screen.
  Future<List<Map<String, dynamic>>> getAllTemplates(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableTemplates,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC', // 🚀 Adjusted default listing parameter to created_at
    );

    return result.map((row) => {
      'template_id': row['template_id'],
      'name': row['name'],
      'category': row['category'],
      'language': row['language'],
      'body_text': row['body_text'],
      'variable_count': row['variable_count'],
      'status': row['status'],
      'rejected_reason': row['rejected_reason'],
      'default_mappings': jsonDecode(row['variable_mapping_json']?.toString() ?? '{}'), // 🚀 Reads exact SQL column structure
      // In getAllTemplates() & getApprovedTemplates(), add to the return map:
      // 🚀 FIX: Add safe fallbacks
      'header_type': row['header_type'] ?? 'NONE',
      'header_text': row['header_text'],
      'buttons': jsonDecode(row['buttons_json']?.toString() ?? '[]'),  // 🚀 ADDED // 🚀 ADDED
    }).toList();
  }

  /// Sourced exclusively to target dynamic dropdowns safely. Only APPROVED templates pass.
  Future<List<Map<String, dynamic>>> getApprovedTemplates(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableTemplates,
      where: 'restaurant_id = ? AND status = ?',
      whereArgs: [restaurantId, 'APPROVED'],
      orderBy: 'name ASC',
    );

    return result.map((row) => {
      'template_id': row['template_id'],
      'name': row['name'],
      'category': row['category'],
      'language': row['language'],
      'body_text': row['body_text'],
      'variable_count': row['variable_count'],
      'default_mappings': jsonDecode(row['variable_mapping_json']?.toString() ?? '{}'),
      // In getAllTemplates() & getApprovedTemplates(), add to the return map:
      // 🚀 FIX: Add safe fallbacks
      'header_type': row['header_type'] ?? 'NONE',
      'header_text': row['header_text'],
      'buttons': jsonDecode(row['buttons_json']?.toString() ?? '[]'),  // 🚀 ADDED  // 🚀 ADDED
    }).toList();
  }

  /// Commits variable mapping selections directly to memory cache to remember them later.
  Future<void> updateVariableMapping(String restaurantId, String name, Map<String, dynamic> mappings) async {
    final database = await _db;
    await database.update(
      DbConnection.tableTemplates,
      {'variable_mapping_json': jsonEncode(mappings)}, // 🚀 Renamed
      where: 'restaurant_id = ? AND name = ?',
      whereArgs: [restaurantId, name],
    );
  }

  /// Drops template locally when deleted.
  Future<void> deleteTemplateLocal(String restaurantId, String name) async {
    final database = await _db;
    await database.delete(
      DbConnection.tableTemplates,
      where: 'restaurant_id = ? AND name = ?',
      whereArgs: [restaurantId, name],
    );
  }
}