import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';

class CrmDbService {
  static final CrmDbService instance = CrmDbService._init();
  CrmDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  // ====================================================================
  // 📢 CRM CONTACTS
  // ====================================================================
  /// Returns true if a NEW contact row was inserted, false if one already
  /// existed (no-op) for this phone. The return value lets callers (e.g.
  /// ChatApi's message sync loop) know when it's actually worth pushing
  /// this contact up to the backend — no point re-pushing on every poll
  /// cycle for a contact that already exists both locally and in Mongo.
  Future<bool> upsertContactIfAbsent(String restaurantId, Map<String, dynamic> contact) async {
    final database = await _db;
    final String phone = contact['phone']?.toString() ?? '';
    if (phone.isEmpty) return false;

    final existing = await database.query(
      DbConnection.tableContacts,
      where: 'restaurant_id = ? AND customer_number = ?',
      whereArgs: [restaurantId, phone],
      limit: 1,
    );
    if (existing.isNotEmpty) return false; 

    final String name = (contact['name']?.toString() ?? '').trim();
    final String displayName = name.isNotEmpty && name != 'WhatsApp User' ? name : phone;
    
await database.insert(DbConnection.tableContacts, {
  'restaurant_id': restaurantId,
  'customer_number': phone,
  'name': displayName,
  'status': 'Active',
  'labels_json': '[]',
  'sync_status': 'synced',
  'read_at': null,
  'source': 'whatsapp',                              // 🚀 ADD THIS
  'created_at': DateTime.now().toIso8601String(),     // 🚀 ADD THIS
}, conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

Future<void> upsertContact(String restaurantId, Map<String, dynamic> contact) async {
  final database = await _db;
  final String phone = contact['phone']?.toString() ?? '';
  final String rawName = contact['name']?.toString() ?? '';
  final String displayName = rawName.isNotEmpty && rawName != 'WhatsApp User' ? rawName : phone;

  if (phone.isEmpty) return;

  // 🚀 FIX: ConflictAlgorithm.replace does a full row replace, so any
  // column not included in `map` (like read_at) gets reset to NULL.
  // That was silently wiping "read" state every time contacts synced
  // from the backend, making already-read chats look unread again.
  // Preserve the existing read_at explicitly instead of dropping it.
  final existing = await database.query(
    DbConnection.tableContacts,
    columns: ['read_at'],
    where: 'restaurant_id = ? AND customer_number = ?',
    whereArgs: [restaurantId, phone],
    limit: 1,
  );
  final String? existingReadAt = existing.isNotEmpty ? existing.first['read_at']?.toString() : null;

  final map = {
    'restaurant_id': restaurantId,
    'customer_number': phone,
    'name': displayName,
    'status': contact['status']?.toString() ?? 'Active',
    'labels_json': jsonEncode(contact['labels'] ?? []),
    'sync_status': 'synced',
    'read_at': existingReadAt,
    'source': contact['source']?.toString() ?? 'manual',             // 🚀 ADD THIS
    'created_at': contact['created_at']?.toString() ?? DateTime.now().toIso8601String(),
  };

  await database.insert(
    DbConnection.tableContacts,
    map,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

  Future<List<Map<String, dynamic>>> getAllContacts(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableContacts,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'name ASC',
    );
    return result.map((row) => {
      'phone': row['customer_number'],
      'name': row['name'],
      'status': row['status'],
      'labels': jsonDecode(row['labels_json'].toString()),
      'syncStatus': row['sync_status'],
      'source': row['source'],           // 🚀 ADD THIS
      'created_at': row['created_at'],
    }).toList();
  }

  /// Stores the timestamp of the message the user last read for this contact.
  /// A contact is unread only if a newer message has arrived after this timestamp.
  Future<void> markContactAsRead(
    String restaurantId,
    String customerNumber,
    String msgId,
  ) async {
    final database = await _db;
    // Use current time — any inbound message that arrived before right now is "read"
    final String readAt = DateTime.now().toUtc().toIso8601String();
    await database.execute(
      '''
      UPDATE ${DbConnection.tableContacts}
      SET read_at = ?
      WHERE restaurant_id = ? AND customer_number = ?
      ''',
      [readAt, restaurantId, customerNumber],
    );
  }

  /// Scans the messages table for any customer numbers that don't yet have
  /// a contacts row, and creates one for them. Called after a message sync
  /// so every customer who has messaged in shows up in the contacts list.
  /// Returns the list of phone numbers that were NEWLY inserted this call
  /// (previously this only logged a count). Callers that need to push new
  /// contacts to a backend (e.g. ChatApi) use this return value — kept
  /// here as pure local SQLite logic, no network/API calls, to avoid a
  /// circular import (contact_api.dart already imports this file).
  Future<List<String>> backfillContactsFromMessages(String restaurantId) async {
    final database = await _db;
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT customer_number
      FROM ${DbConnection.tableMessages}
      WHERE restaurant_id = ?
      ''',
      [restaurantId],
    );

    final List<String> newlyInserted = [];
    for (var row in rows) {
      final phone = row['customer_number']?.toString() ?? '';
      if (phone.isEmpty) continue;
      final inserted = await upsertContactIfAbsent(restaurantId, {'phone': phone, 'name': ''});
      if (inserted) newlyInserted.add(phone);
    }
    print("✅ Backfill done: ${newlyInserted.length} contacts synced from messages table.");
    return newlyInserted;
  }

  /// A contact is "read" if their last inbound message arrived BEFORE or AT
  /// the time the user last opened that chat.
  Future<Set<String>> getReadContactNumbers(String restaurantId) async {
    final database = await _db;
    final rows = await database.rawQuery(
      '''
      SELECT c.customer_number
      FROM ${DbConnection.tableContacts} c
      INNER JOIN (
        SELECT customer_number, MAX(created_at) AS last_msg_time
        FROM ${DbConnection.tableMessages}
        WHERE restaurant_id = ?
          AND (direction = 'inbound' OR is_outgoing = 0)
        GROUP BY customer_number
      ) latest ON c.customer_number = latest.customer_number
      WHERE c.restaurant_id = ?
        AND c.read_at IS NOT NULL
        AND latest.last_msg_time <= c.read_at
      ''',
      [restaurantId, restaurantId],
    );
    return rows.map((r) => r['customer_number'].toString()).toSet();
  }

  // ====================================================================
  // 🏷️ CRM LABELS
  // ====================================================================
  Future<void> upsertLabel(String restaurantId, Map<String, dynamic> label) async {
    final database = await _db;
    if (label['is_automated'] != 1) {
      final existing = await database.query(
        DbConnection.tableLabels,
        where: 'restaurant_id = ? AND label_id = ?',
        whereArgs: [restaurantId, label['id'] ?? label['name']],
      );
      if (existing.isNotEmpty && existing.first['is_automated'] == 1) return; 
    }
    final map = {
      'restaurant_id': restaurantId,
      'label_id': label['id'] ?? label['label_id'] ?? label['name'],
      'name': label['name'],
      'description': label['description'] ?? '',
      'contact_count': label['count'] ?? 0,
      'is_automated': label['is_automated'] ?? 0,
      'created_at': label['date'] ?? DateTime.now().toIso8601String(),
    };
    await database.insert(
      DbConnection.tableLabels,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllLabels(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableLabels,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC',
    );
    return result.map((row) => {
      'id': row['label_id'],
      'name': row['name'],
      'description': row['description'],
      'count': row['contact_count'],
      'is_automated': row['is_automated'] ?? 0,
      'date': row['created_at'],
    }).toList();
  }

  Future<void> deleteLabel(String restaurantId, String labelId) async {
    final database = await _db;
    final labelRows = await database.query(
      DbConnection.tableLabels,
      where: 'restaurant_id = ? AND label_id = ? AND is_automated = 0',
      whereArgs: [restaurantId, labelId],
    );
    if (labelRows.isEmpty) return; 

    final String labelName = labelRows.first['name']?.toString() ?? '';

    await database.delete(
      DbConnection.tableLabels,
      where: 'restaurant_id = ? AND label_id = ? AND is_automated = 0',
      whereArgs: [restaurantId, labelId],
    );

    if (labelName.isNotEmpty) {
      final contacts = await database.query(
        DbConnection.tableContacts,
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
      );

      for (var row in contacts) {
        List<dynamic> labels = jsonDecode(row['labels_json']?.toString() ?? '[]');
        if (labels.contains(labelName)) {
          labels.remove(labelName);
          await database.update(
            DbConnection.tableContacts,
            {'labels_json': jsonEncode(labels)},
            where: 'restaurant_id = ? AND customer_number = ?',
            whereArgs: [restaurantId, row['customer_number']],
          );
        }
      }
    }
  }

  Future<void> recalculateLabelCounts(String restaurantId) async {
    final database = await _db;
    final contacts = await database.query(
      DbConnection.tableContacts,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );

    final Map<String, int> counts = {};
    for (var row in contacts) {
      final List<dynamic> labels = jsonDecode(row['labels_json']?.toString() ?? '[]');
      for (var label in labels) {
        final name = label.toString();
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }

    final labelRows = await database.query(
      DbConnection.tableLabels,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );

    for (var labelRow in labelRows) {
      final String name = labelRow['name']?.toString() ?? '';
      final int newCount = counts[name] ?? 0;
      await database.update(
        DbConnection.tableLabels,
        {'contact_count': newCount},
        where: 'restaurant_id = ? AND label_id = ?',
        whereArgs: [restaurantId, labelRow['label_id']],
      );
    }
  }

  /// Additive helper — updates ONLY labels_json for a contact, leaving name/
  /// status untouched. Needed because upsertContact() falls back to phone
  /// when name is blank, which would otherwise wipe a contact's real name
  /// every time only its labels change.
  Future<void> updateLocalContactLabels(String restaurantId, String phone, List<String> labels) async {
    final database = await _db;
    await database.update(
      DbConnection.tableContacts,
      {'labels_json': jsonEncode(labels)},
      where: 'restaurant_id = ? AND customer_number = ?',
      whereArgs: [restaurantId, phone],
    );
  }

  /// Additive helper — translates a backend label_id into its local display
  /// name, so contact_api.dart can convert the backend's label_ids into the
  /// names crm_db.dart's contacts table already expects, without touching
  /// any existing label storage logic (smart automation keeps working as-is).
  Future<String?> getLabelNameById(String restaurantId, String labelId) async {
    final database = await _db;
    final rows = await database.query(
      DbConnection.tableLabels,
      columns: ['name'],
      where: 'restaurant_id = ? AND label_id = ?',
      whereArgs: [restaurantId, labelId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name']?.toString();
  }

  /// Additive helper — the reverse lookup, used when pushing a contact's
  /// current (name-based) label list up to the backend as label_ids.
  Future<String?> getLabelIdByName(String restaurantId, String name) async {
    final database = await _db;
    final rows = await database.query(
      DbConnection.tableLabels,
      columns: ['label_id'],
      where: 'restaurant_id = ? AND name = ?',
      whereArgs: [restaurantId, name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['label_id']?.toString();
  }

  Future<void> cleanupOrphanedLabels(String restaurantId) async {
    final database = await _db;
    final labelRows = await database.query(
      DbConnection.tableLabels,
      columns: ['name'],
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );
    final Set<String> validLabelNames = labelRows.map((r) => r['name'].toString()).toSet();

    final contacts = await database.query(
      DbConnection.tableContacts,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );

    for (var row in contacts) {
      List<dynamic> labels = jsonDecode(row['labels_json']?.toString() ?? '[]');
      List<dynamic> cleanedLabels = labels.where((l) => validLabelNames.contains(l.toString())).toList();

      if (cleanedLabels.length != labels.length) {
        await database.update(
          DbConnection.tableContacts,
          {'labels_json': jsonEncode(cleanedLabels)},
          where: 'restaurant_id = ? AND customer_number = ?',
          whereArgs: [restaurantId, row['customer_number']],
        );
      }
    }
  }

  // ====================================================================
  // 📣 CRM CAMPAIGNS
  // ====================================================================

  /// Upserts a campaign from the backend's shape (CampaignOut / list item).
  /// `campaign['recipients']` is OPTIONAL here — the list endpoint doesn't
  /// send per-recipient detail (only counts), while the single-campaign
  /// detail endpoint does. When it's not provided, we preserve whatever
  /// recipients_json is already stored locally instead of wiping it —
  /// same reasoning as the contacts read_at fix: a ConflictAlgorithm.replace
  /// silently nukes any column left out of the map.
  Future<void> upsertCampaign(String restaurantId, Map<String, dynamic> campaign) async {
    final database = await _db;
    final String campaignId = campaign['campaign_id']?.toString() ?? campaign['id']?.toString() ?? '';
    if (campaignId.isEmpty) return;

    String recipientsJson;
    if (campaign.containsKey('recipients') && campaign['recipients'] != null) {
      recipientsJson = jsonEncode(campaign['recipients']);
    } else {
      final existing = await database.query(
        DbConnection.tableCampaigns,
        columns: ['recipients_json'],
        where: 'restaurant_id = ? AND campaign_id = ?',
        whereArgs: [restaurantId, campaignId],
        limit: 1,
      );
      recipientsJson = existing.isNotEmpty ? (existing.first['recipients_json']?.toString() ?? '[]') : '[]';
    }

    final map = {
      'restaurant_id': restaurantId,
      'campaign_id': campaignId,
      'name': campaign['name'],
      'template_name': campaign['template_name'] ?? '',
      'audience_type': campaign['audience_type'] ?? 'All',
      'label_id': campaign['label_id'],
      'recipients_count': campaign['recipients_count'] ?? 0,
      'sent_count': campaign['sent_count'] ?? 0,
      'failed_count': campaign['failed_count'] ?? 0,
      'delivered_count': campaign['delivered_count'] ?? 0,
      'read_count': campaign['read_count'] ?? 0,
      'status': campaign['status'] ?? 'sending',
      'recipients_json': recipientsJson,
      'created_at': campaign['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    };

    await database.insert(
      DbConnection.tableCampaigns,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCampaigns(String restaurantId) async {
    final database = await _db;
    final result = await database.query(
      DbConnection.tableCampaigns,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC',
    );
    return result.map((row) => {
      'id': row['campaign_id'],
      'name': row['name'],
      'template_name': row['template_name'],
      'audience_type': row['audience_type'],
      'label_id': row['label_id'],
      'recipients': row['recipients_count'], // kept as 'recipients' — matches what campaigns_tab.dart already reads
      'sent_count': row['sent_count'],
      'failed_count': row['failed_count'],
      'delivered_count': row['delivered_count'],
      'read_count': row['read_count'],
      'status': row['status'],
      'date': row['created_at'],
    }).toList();
  }

  Future<void> deleteCampaignLocal(String restaurantId, String campaignId) async {
    final database = await _db;
    await database.delete(
      DbConnection.tableCampaigns,
      where: 'restaurant_id = ? AND campaign_id = ?',
      whereArgs: [restaurantId, campaignId],
    );
  }
// 🚀 NEW: Quick update for the Block button
  Future<void> updateLocalContactStatus(String restaurantId, String phone, String status) async {
    final database = await _db;
    await database.update(
      DbConnection.tableContacts,
      {'status': status},
      where: 'restaurant_id = ? AND customer_number = ?',
      whereArgs: [restaurantId, phone],
    );
  }


  // ====================================================================
  // 🧠 SMART CRM ENGINE
  // ====================================================================
  Future<void> runSmartCRMAutomation(String restaurantId) async {
    final database = await _db;

    final autoLabels = [
      {'id': 'auto_vip', 'name': '🌟 VIP (5+ Orders)', 'desc': 'Highly frequent customers', 'is_automated': 1},
      {'id': 'auto_high_roller', 'name': '💰 High Spender (₹2000+)', 'desc': 'High lifetime value', 'is_automated': 1},
      {'id': 'auto_lapsing', 'name': '⚠️ Lapsing (30+ Days)', 'desc': 'No orders in a month', 'is_automated': 1},
    ];

    for (var label in autoLabels) {
      await database.insert(DbConnection.tableLabels, {
        'restaurant_id': restaurantId,
        'label_id': label['id'],
        'name': label['name'],
        'description': label['desc'],
        'is_automated': label['is_automated'],
        'contact_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final List<Map<String, dynamic>> orderStats = await database.rawQuery('''
      SELECT customer_number, COUNT(order_id) as total_orders, SUM(total_amount) as total_spent, MAX(created_at) as last_order_date
      FROM ${DbConnection.tableOrders} 
      WHERE restaurant_id = ? AND customer_number != '' 
      GROUP BY customer_number
    ''', [restaurantId]);

    for (var stat in orderStats) {
      String phone = stat['customer_number'].toString();
      int orderCount = int.tryParse(stat['total_orders'].toString()) ?? 0;
      double totalSpent = double.tryParse(stat['total_spent'].toString()) ?? 0.0;
      DateTime? lastOrder;
      try {
        lastOrder = DateTime.parse(stat['last_order_date'].toString());
      } catch (e) {}

      List<String> newSmartTags = [];
      if (orderCount >= 5) newSmartTags.add('🌟 VIP (5+ Orders)');
      if (totalSpent >= 2000) newSmartTags.add('💰 High Spender (₹2000+)');
      if (lastOrder != null && DateTime.now().difference(lastOrder).inDays >= 30) {
        newSmartTags.add('⚠️ Lapsing (30+ Days)');
      }

      if (newSmartTags.isEmpty) continue;

      final existingContact = await database.query(
        DbConnection.tableContacts,
        where: 'restaurant_id = ? AND customer_number = ?',
        whereArgs: [restaurantId, phone],
      );

      List<String> currentLabels = [];
      String contactName = "WhatsApp User";

      if (existingContact.isNotEmpty) {
        contactName = existingContact.first['name']?.toString() ?? "WhatsApp User";
        try {
          currentLabels = List<String>.from(jsonDecode(existingContact.first['labels_json']?.toString() ?? '[]'));
        } catch (e) {}
      }

      currentLabels.removeWhere((l) => l.startsWith('🌟') || l.startsWith('💰') || l.startsWith('⚠️'));
      currentLabels.addAll(newSmartTags);

      await upsertContact(restaurantId, {
        'phone': phone,
        'name': contactName,
        'status': 'Active',
        'labels': currentLabels.toSet().toList(),
      });
    }
  }
}