import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class OrderDbService {
  static final OrderDbService instance = OrderDbService._init();
  OrderDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  Future<void> upsertOrder(
    String restaurantId,
    Map<String, dynamic> order, {
    String syncStatus = 'synced',
  }) async {
    final database = await _db;

    String rawMongoId = '';
    if (order['_id'] is Map) {
      rawMongoId = order['_id']['\$oid']?.toString() ?? '';
    } else {
      rawMongoId = order['_id']?.toString() ?? order['id']?.toString() ?? '';
    }

    String displayId = order['orderId']?.toString() ?? '';
    if (rawMongoId.isEmpty) rawMongoId = displayId;
    if (rawMongoId.isEmpty) return;

    String createdAtDate = order['createdAt'] is Map
        ? (order['createdAt']['\$date']?.toString() ?? '')
        : (order['createdAt']?.toString() ?? DateTime.now().toIso8601String());

    final existingRows = await database.query(
      DbConnection.tableOrders,
      columns: ['additional_notes', 'payment_status'],
      where: 'restaurant_id = ? AND order_id = ?',
      whereArgs: [restaurantId, rawMongoId],
    );
    
    String localNotes = existingRows.isNotEmpty ? (existingRows.first['additional_notes']?.toString() ?? '') : '';
    String incomingNotes = order['additionalNotes']?.toString() ?? '';

    if (localNotes.contains('[ACCEPTED]') && !incomingNotes.contains('[ACCEPTED]')) {
      incomingNotes = incomingNotes.isEmpty ? '[ACCEPTED]' : '$incomingNotes\n[ACCEPTED]';
    }
    if (localNotes.contains('[REJECTED]') && !incomingNotes.contains('[REJECTED]')) {
      incomingNotes = incomingNotes.isEmpty ? '[REJECTED]' : '$incomingNotes\n[REJECTED]';
    }
    
    final dbTagMatch = RegExp(r'\[DELIVERY_BOY:[^\]]*\]').firstMatch(localNotes);
    if (dbTagMatch != null && !incomingNotes.contains('[DELIVERY_BOY:')) {
      final dbTag = dbTagMatch.group(0)!;
      incomingNotes = incomingNotes.isEmpty ? dbTag : '$incomingNotes\n$dbTag';
    }

    const Map<String, int> _statusRank = {
      'pending': 0, 'cod': 1, 'online': 1, 'accepted': 2, 'preparing': 3,
      'assigned': 4, 'ready': 5, 'completed': 6, 'paid': 6, 'rejected': 6,
    };
    
    String localPayStatus = existingRows.isNotEmpty ? (existingRows.first['payment_status']?.toString() ?? '') : '';
    String incomingPayStatus = order['paymentStatus']?.toString() ?? 'pending';

    int localRank = _statusRank[localPayStatus.toLowerCase()] ?? 0;
    int incomingRank = _statusRank[incomingPayStatus.toLowerCase()] ?? 0;

    String resolvedPayStatus = localRank >= incomingRank ? localPayStatus : incomingPayStatus;
    if (localPayStatus.isEmpty) resolvedPayStatus = incomingPayStatus;

    final map = {
      'restaurant_id': restaurantId,
      'order_id': rawMongoId,
      'display_id': displayId,
      'customer_number': order['customerNumber']?.toString() ?? '',
      'total_amount': double.tryParse(order['totalAmount']?.toString() ?? '0') ?? 0.0,
      'payment_status': resolvedPayStatus,
      'order_status': resolvedPayStatus,
      'order_type': order['orderType']?.toString() ?? 'whatsapp',
      'items_json': jsonEncode(order['items'] ?? []),
      'location_json': jsonEncode(order['location'] ?? {}),
      'additional_notes': incomingNotes,
      'created_at': createdAtDate,
      'sync_status': syncStatus,
    };

    await database.insert(
      DbConnection.tableOrders,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateOrderStatusLocally(
    String restaurantId,
    String mongoOrderId,
    String newStatus, {
    String? notes,
  }) async {
    final database = await _db;
    final values = <String, dynamic>{
      'payment_status': newStatus,
      'order_status': newStatus,
    };
    if (notes != null) values['additional_notes'] = notes;
    await database.update(
      DbConnection.tableOrders,
      values,
      where: 'restaurant_id = ? AND order_id = ?',
      whereArgs: [restaurantId, mongoOrderId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllOrders(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableOrders,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC',
      limit: 200,
    );

    return result.map((row) => {
      '_id': row['order_id'],
      'displayId': row['display_id'],
      'orderId': row['display_id'] != null && row['display_id'].toString().isNotEmpty ? row['display_id'] : row['order_id'],
      'customerNumber': row['customer_number'],
      'totalAmount': row['total_amount'],
      'paymentStatus': row['payment_status'],
      'orderType': row['order_type'],
      'items': jsonDecode(row['items_json'].toString()),
      'location': jsonDecode(row['location_json'].toString()),
      'additionalNotes': row['additional_notes'],
      'createdAt': row['created_at'],
      'syncStatus': row['sync_status'],
    }).toList();
  }

}