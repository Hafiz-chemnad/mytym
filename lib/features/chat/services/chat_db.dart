import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class ChatDbService {
  static final ChatDbService instance = ChatDbService._init();
  ChatDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  Future<void> upsertMessage(
    String restaurantId,
    Map<String, dynamic> msg, {
    String syncStatus = 'synced',
  }) async {
    final database = await _db;

    String msgId = msg['_id']?.toString() ?? msg['id']?.toString() ?? msg['msgId']?.toString() ?? '';
      String customerNumber = msg['customerNumber']?.toString() ?? msg['customer_number']?.toString() ?? '';
      if (msgId.isEmpty || customerNumber.isEmpty) return; // ✅ reject broken rows
      

    String contentJson;
    try {
      contentJson = jsonEncode(msg['messageContent'] ?? msg['content'] ?? {});
    } catch (e) {
      contentJson = '{}';
    }

    final map = {
      'restaurant_id': restaurantId,
      'msg_id': msgId,
      'customer_number': msg['customerNumber']?.toString() ?? msg['customer_number']?.toString() ?? '',
      'direction': msg['direction']?.toString() ?? 'inbound',
      'is_outgoing': (msg['isOutgoing'] == true || msg['is_outgoing'] == true || msg['direction']?.toString().contains('out') == true) ? 1 : 0,
      'message_type': msg['messageType']?.toString() ?? msg['type']?.toString() ?? 'text',
      'message_content_json': contentJson,
      'status': msg['status']?.toString() ?? 'delivered',
      'created_at': _resolveTimestamp(msg),
      'sync_status': syncStatus,
    };

    await database.insert(
      DbConnection.tableMessages,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllMessages(String restaurantId) async {
    final database = await _db;

    final result = await database.rawQuery(
      '''
      SELECT m.*,
             COALESCE(NULLIF(c.name, ''), m.customer_number) AS customer_name,
             c.read_at AS contact_read_at,
             inb.last_inbound_time AS last_inbound_time
      FROM ${DbConnection.tableMessages} m
      INNER JOIN (
        SELECT restaurant_id, customer_number, MAX(created_at) AS max_created
        FROM ${DbConnection.tableMessages}
        WHERE restaurant_id = ?
        GROUP BY restaurant_id, customer_number
      ) latest
        ON m.restaurant_id   = latest.restaurant_id
       AND m.customer_number = latest.customer_number
       AND m.created_at      = latest.max_created
       AND m.restaurant_id   = ?
      LEFT JOIN ${DbConnection.tableContacts} c
        ON c.restaurant_id   = m.restaurant_id
       AND c.customer_number = m.customer_number
      LEFT JOIN (
        SELECT i.customer_number, i.last_inbound_time, m2.message_content_json AS last_inbound_content
        FROM (
          SELECT customer_number, MAX(created_at) AS last_inbound_time
          FROM ${DbConnection.tableMessages}
          WHERE restaurant_id = ?
            AND (direction = 'inbound' OR is_outgoing = 0)
            AND message_content_json <> '{}' AND message_content_json IS NOT NULL
          GROUP BY customer_number
        ) i
        INNER JOIN ${DbConnection.tableMessages} m2
          ON m2.customer_number = i.customer_number
         AND m2.created_at = i.last_inbound_time
         AND m2.restaurant_id = ?
         AND (m2.direction = 'inbound' OR m2.is_outgoing = 0)
      )  inb ON inb.customer_number = m.customer_number
             AND inb.customer_number = m.customer_number
      ORDER BY m.created_at DESC
    ''',
      [restaurantId, restaurantId, restaurantId, restaurantId],
    );

    final rows = result.map((row) => {
      'id': row['msg_id'],
      '_id': row['msg_id'],
      'customerNumber': row['customer_number'],
      'customerName': () {
        final name = row['customer_name']?.toString() ?? '';
        final phone = row['customer_number']?.toString() ?? '';
        if (name.isEmpty || name == 'WhatsApp User') return phone;
        return name;
      }(),
      'direction': row['direction'],
      'isOutgoing': row['is_outgoing'] == 1,
      'messageType': row['message_type'],
      'messageContent': _safeJsonDecode(row['message_content_json']?.toString()),
      'status': row['status'],
      'createdAt': row['created_at'],
      'syncStatus': row['sync_status'],
      'contactReadAt': row['contact_read_at']?.toString(),
      'lastInboundTime': row['last_inbound_time']?.toString(),
      'lastInboundContent': row['last_inbound_content']?.toString(),
    }).toList();

    rows.sort((a, b) {
      DateTime _parse(String? s) {
        if (s == null || s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
        final ms = int.tryParse(s);
        if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
        try {
          return DateTime.parse(s);
        } catch (_) {
          return DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
      return _parse(b['createdAt']?.toString()).compareTo(_parse(a['createdAt']?.toString()));
    });

    return rows;
  }

  Future<List<Map<String, dynamic>>> getThreadForContact(String restaurantId, String customerNumber) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableMessages,
      where: 'restaurant_id = ? AND customer_number = ?',
      whereArgs: [restaurantId, customerNumber],
      orderBy: 'created_at DESC',
      limit: 100,
    );

    return result.map((row) => {
      'id': row['msg_id'],
      '_id': row['msg_id'],
      'customerNumber': row['customer_number'],
      'direction': row['direction'],
      'isOutgoing': row['is_outgoing'] == 1,
      'messageType': row['message_type'],
      'messageContent': jsonDecode(row['message_content_json'].toString()),
      'status': row['status'],
      'createdAt': row['created_at'],
      'syncStatus': row['sync_status'],
    }).toList();
  }

  dynamic _safeJsonDecode(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      return jsonDecode(s);
    } catch (_) {
      return {};
    }
  }

  static String _resolveTimestamp(Map<String, dynamic> msg) {
    final candidates = [msg['timestamp'], msg['createdAt'], msg['created_at']];
    for (final raw in candidates) {
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isEmpty) continue;
      final epoch = int.tryParse(s);
      if (epoch != null) {
        final ms = s.length >= 13 ? epoch : epoch * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
      }
      try {
        return DateTime.parse(s).toUtc().toIso8601String();
      } catch (_) {}
    }
    return DateTime.now().toUtc().toIso8601String();
  }
  // 🚀 ADDED — single source of truth for "is this contact unread", used by
// both the dashboard badge and the inbox list so they can never drift apart.
static bool isContactUnread(Map<String, dynamic> msg) {
  final String? lastInbound = msg['lastInboundTime']?.toString();
  if (lastInbound == null || lastInbound.isEmpty) return false;

  final String? readAt = msg['contactReadAt']?.toString();
  if (readAt == null || readAt.isEmpty) return true;

  try {
    return DateTime.parse(lastInbound).toUtc().isAfter(DateTime.parse(readAt).toUtc());
  } catch (_) {
    return false;
  }
}
}