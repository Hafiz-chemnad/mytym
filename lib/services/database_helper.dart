import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // Table Names
  static const String tableSettings = 'settings';
  static const String tableMenu = 'menu_items';
  static const String tableOrders = 'orders';
  static const String tableMessages = 'messages';
  static const String tableContacts = 'contacts';
  static const String tableLabels = 'labels';
  static const String tableCampaigns = 'campaigns';
  static const String tableDeliveryBoys = 'delivery_boys';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tym_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // 🚀 BUMPED VERSION TO 5 — added delivery_boys table
    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. SETTINGS TABLE (Single row config per restaurant context)
    await db.execute('''
      CREATE TABLE $tableSettings (
        id INTEGER PRIMARY KEY DEFAULT 1,
        restaurant_id TEXT,
        name TEXT,
        waba_id TEXT,
        phone_number_id TEXT,
        wa_token TEXT,
        catalog_id TEXT,
        address TEXT,
        latitude REAL,
        longitude REAL,
        service_type TEXT,
        payment_availability TEXT,
        primary_flow TEXT,
        delivery_flow TEXT,
        delivery_radius REAL,
        welcome_video_url TEXT,
        welcome_video_id TEXT,
        rzp_key TEXT,
        rzp_secret TEXT,
        sheet_url TEXT,
        sheet_id TEXT
      )
    ''');

    // 2. MENU ITEMS TABLE
    await db.execute('''
      CREATE TABLE $tableMenu (
        restaurant_id TEXT,
        retailer_id TEXT,
        name TEXT,
        price REAL,
        category TEXT,
        image_url TEXT,
        is_available INTEGER DEFAULT 1,
        is_veg INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'synced', 
        updated_at TEXT,
        PRIMARY KEY (restaurant_id, retailer_id)
      )
    ''');

    // 3. ORDERS TABLE
    await db.execute('''
      CREATE TABLE $tableOrders (
        restaurant_id TEXT,
        order_id TEXT,
        display_id TEXT, 
        customer_number TEXT,
        total_amount REAL,
        payment_status TEXT,
        order_status TEXT DEFAULT 'pending',
        order_type TEXT,
        items_json TEXT, 
        location_json TEXT,
        additional_notes TEXT,
        created_at TEXT,
        sync_status TEXT DEFAULT 'synced',
        PRIMARY KEY (restaurant_id, order_id)
      )
    ''');

    // 4. MESSAGES TABLE
    await db.execute('''
      CREATE TABLE $tableMessages (
        restaurant_id TEXT,
        msg_id TEXT, 
        customer_number TEXT, 
        direction TEXT, 
        is_outgoing INTEGER, 
        message_type TEXT, 
        message_content_json TEXT, 
        status TEXT, 
        created_at TEXT, 
        sync_status TEXT DEFAULT 'synced',
        read_at TEXT,
        PRIMARY KEY (restaurant_id, msg_id)
      )
    ''');

    // 5. CRM CONTACTS TABLE
    await db.execute('''
      CREATE TABLE $tableContacts (
        restaurant_id TEXT,
        customer_number TEXT,
        name TEXT,
        status TEXT DEFAULT 'Active',
        labels_json TEXT DEFAULT '[]',
        sync_status TEXT DEFAULT 'synced',
        read_at TEXT,
        PRIMARY KEY (restaurant_id, customer_number)
      )
    ''');

    // 6. CRM LABELS TABLE
    await db.execute('''
      CREATE TABLE $tableLabels (
        restaurant_id TEXT,
        label_id TEXT,
        name TEXT,
        description TEXT,
        contact_count INTEGER DEFAULT 0,
        is_automated INTEGER DEFAULT 0, 
        created_at TEXT,
        PRIMARY KEY (restaurant_id, label_id)
      )
    ''');

    // 7. CRM CAMPAIGNS TABLE
    await db.execute('''
      CREATE TABLE $tableCampaigns (
        restaurant_id TEXT,
        campaign_id TEXT,
        name TEXT,
        template_name TEXT,
        audience_type TEXT,
        recipients_count INTEGER,
        status TEXT,
        created_at TEXT,
        PRIMARY KEY (restaurant_id, campaign_id)
      )
    ''');

    // 8. DELIVERY BOYS TABLE (global — not per restaurant)
    await db.execute('''
      CREATE TABLE $tableDeliveryBoys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL UNIQUE
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE $tableOrders ADD COLUMN display_id TEXT');
      } catch (e) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $tableContacts (customer_number TEXT PRIMARY KEY, name TEXT, status TEXT DEFAULT "Active", labels_json TEXT DEFAULT "[]", sync_status TEXT DEFAULT "synced")',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $tableLabels (label_id TEXT PRIMARY KEY, name TEXT, description TEXT, contact_count INTEGER DEFAULT 0, is_automated INTEGER DEFAULT 0, created_at TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $tableCampaigns (campaign_id TEXT PRIMARY KEY, name TEXT, template_name TEXT, audience_type TEXT, recipients_count INTEGER, status TEXT, created_at TEXT)',
        );
      } catch (e) {}
    }
    // 🚀 FIX: MIGRATION BLOCK TO V4 FOR MULTI-TENANT ISOLATION
    if (oldVersion < 4) {
      try {
        // Drop old tables and rebuild them safely with composite restaurant_id primary keys
        await db.execute('DROP TABLE IF EXISTS $tableMenu');
        await db.execute('DROP TABLE IF EXISTS $tableOrders');
        await db.execute('DROP TABLE IF EXISTS $tableMessages');
        await db.execute('DROP TABLE IF EXISTS $tableContacts');
        await db.execute('DROP TABLE IF EXISTS $tableLabels');
        await db.execute('DROP TABLE IF EXISTS $tableCampaigns');

        // Re-execute creation queries with version 4 standards
        await _createDB(db, 4);
        print(
          "💾 Database successfully upgraded to V4 layout with tenant scoping partitions.",
        );
      } catch (e) {
        print("Error executing database V4 migration: $e");
      }
    }
    // 🚀 V5: Add delivery boys table (safe — won't destroy existing data)
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableDeliveryBoys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL UNIQUE
          )
        ''');
        print("💾 Database upgraded to V5 — delivery_boys table added.");
      } catch (e) {
        print("Error executing database V5 migration: $e");
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE $tableMessages ADD COLUMN read_at TEXT');
        print("💾 Database upgraded to V6 — read_at column added to messages.");
      } catch (e) {
        print("Error executing database V6 migration: $e");
      }
    }
    // Add at the end of _upgradeDB:
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE $tableContacts ADD COLUMN read_at TEXT');
        print("💾 Database upgraded to V7 — read_at column added to contacts.");
      } catch (e) {
        print("Error executing database V7 migration: $e");
      }
    }
  }

  // ====================================================================
  // 🚚 DELIVERY BOYS CRUD
  // ====================================================================

  /// Insert a new delivery boy. Returns the new row id, or -1 if phone already exists.
  Future<int> addDeliveryBoy(String name, String phone) async {
    final db = await instance.database;
    try {
      return await db.insert(
        tableDeliveryBoys,
        {'name': name, 'phone': phone},
        conflictAlgorithm: ConflictAlgorithm.ignore, // ignore duplicate phones
      );
    } catch (e) {
      print("addDeliveryBoy error: $e");
      return -1;
    }
  }

  /// Returns all delivery boys ordered by name.
  Future<List<Map<String, String>>> getAllDeliveryBoys() async {
    final db = await instance.database;
    final rows = await db.query(tableDeliveryBoys, orderBy: 'name ASC');
    return rows
        .map(
          (r) => {
            'id': r['id'].toString(),
            'name': r['name'].toString(),
            'phone': r['phone'].toString(),
          },
        )
        .toList();
  }

  /// Delete a delivery boy by id.
  Future<void> deleteDeliveryBoy(int id) async {
    final db = await instance.database;
    await db.delete(tableDeliveryBoys, where: 'id = ?', whereArgs: [id]);
  }

  // ====================================================================
  // ⚙️ SETTINGS CRUD
  // ====================================================================

  // ====================================================================
  // ⚙️ SETTINGS CRUD
  // ====================================================================

  Future<void> saveSettings(Map<String, dynamic> rawData) async {
    final db = await instance.database;

    // 🚀 FIX: Helper to safely extract strings, even from MongoDB $oid maps
    String extractString(dynamic val) {
      if (val == null) return '';
      if (val is Map) return val['\$oid']?.toString() ?? '';
      if (val is List) return ''; // Block SQLite from crashing on arrays
      return val.toString();
    }

    // 🚀 FIX: Map the raw API response specifically to our SQLite columns
    final cleanSettings = {
      'id': 1, // Force single row
      'restaurant_id': extractString(rawData['_id'] ?? rawData['id']),
      'name': extractString(rawData['name']),
      'waba_id': extractString(rawData['wabaId']),
      'phone_number_id': extractString(rawData['phoneNumberId']),
      'wa_token': extractString(rawData['waToken']),
      'catalog_id': extractString(rawData['catalogId']),
      'address': extractString(rawData['address']),
      'latitude':
          double.tryParse(rawData['latitude']?.toString() ?? '0') ?? 0.0,
      'longitude':
          double.tryParse(rawData['longitude']?.toString() ?? '0') ?? 0.0,
      'service_type': extractString(rawData['serviceType']),
      'payment_availability': extractString(rawData['paymentAvailability']),
      'primary_flow': extractString(rawData['primaryFlowType']),
      'delivery_flow': extractString(rawData['deliveryFlowType']),
      'delivery_radius':
          double.tryParse(rawData['deliveryRadius']?.toString() ?? '0') ?? 0.0,
      'welcome_video_url': extractString(rawData['welcomeVideoUrl']),
      'welcome_video_id': extractString(rawData['welcomeVideoMediaId']),
      'rzp_key': extractString(rawData['razorpayKeyId']),
      'rzp_secret': extractString(rawData['razorpayKeySecret']),
      'sheet_url': extractString(rawData['googleSheetUrl']),
      'sheet_id': extractString(rawData['googleSheetId']),
    };

    await db.insert(
      tableSettings,
      cleanSettings,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSettings() async {
    final db = await instance.database;
    final result = await db.query(
      tableSettings,
      where: 'id = ?',
      whereArgs: [1],
    );

    if (result.isNotEmpty) {
      final row = result.first;
      // 🚀 FIX: Return camelCase so the rest of the app doesn't break!
      return {
        'id': row['restaurant_id'],
        'name': row['name'],
        'wabaId': row['waba_id'],
        'phoneNumberId': row['phone_number_id'],
        'waToken': row['wa_token'],
        'catalogId': row['catalog_id'],
        'address': row['address'],
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'serviceType': row['service_type'],
        'paymentAvailability': row['payment_availability'],
        'primaryFlowType': row['primary_flow'],
        'deliveryFlowType': row['delivery_flow'],
        'deliveryRadius': row['delivery_radius'],
        'welcomeVideoUrl': row['welcome_video_url'],
        'welcomeVideoMediaId': row['welcome_video_id'],
        'razorpayKeyId': row['rzp_key'],
        'razorpayKeySecret': row['rzp_secret'],
        'googleSheetUrl': row['sheet_url'],
        'googleSheetId': row['sheet_id'],
      };
    }
    return null;
  }

  // ====================================================================
  // 🍔 MENU ITEMS CRUD (Tenant-Scoped)
  // ====================================================================
  Future<void> upsertMenuItem(
    String restaurantId,
    Map<String, dynamic> item, {
    String syncStatus = 'synced',
  }) async {
    final db = await instance.database;

    final map = {
      'restaurant_id': restaurantId,
      'retailer_id': item['id'] ?? item['retailerId'] ?? item['retailer_id'],
      'name': item['name'] ?? item['title'],
      'price': double.tryParse(item['price'].toString()) ?? 0.0,
      'category': item['category'] ?? item['description'] ?? 'Menu Item',
      'image_url': item['imageUrl'] ?? item['image_link'] ?? '',
      'is_available': (item['isAvailable'] ?? true) ? 1 : 0,
      'is_veg': (item['isVeg'] ?? false) ? 1 : 0,
      'sync_status': syncStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await db.insert(
      tableMenu,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllMenuItems(
    String restaurantId,
  ) async {
    final db = await instance.database;
    final result = await db.query(
      tableMenu,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'category ASC, name ASC',
    );

    return result
        .map(
          (row) => {
            'id': row['retailer_id'],
            'retailerId': row['retailer_id'],
            'name': row['name'],
            'price': row['price'],
            'category': row['category'],
            'imageUrl': row['image_url'],
            'isAvailable': row['is_available'] == 1,
            'isVeg': row['is_veg'] == 1,
            'syncStatus': row['sync_status'],
          },
        )
        .toList();
  }

  Future<void> deleteMenuItemLocally(
    String restaurantId,
    String retailerId,
  ) async {
    final db = await instance.database;
    await db.delete(
      tableMenu,
      where: 'restaurant_id = ? AND retailer_id = ?',
      whereArgs: [restaurantId, retailerId],
    );
  }

  // ====================================================================
  // 💬 MESSAGES CRUD (Tenant-Scoped)
  // ====================================================================
  Future<void> upsertMessage(
    String restaurantId,
    Map<String, dynamic> msg, {
    String syncStatus = 'synced',
  }) async {
    final db = await instance.database;

    String msgId =
        msg['_id']?.toString() ??
        msg['id']?.toString() ??
        msg['msgId']?.toString() ??
        '';
    if (msgId.isEmpty) return;

    String contentJson;
    try {
      contentJson = jsonEncode(msg['messageContent'] ?? msg['content'] ?? {});
    } catch (e) {
      contentJson = '{}';
    }

    final map = {
      'restaurant_id': restaurantId,
      'msg_id': msgId,
      'customer_number':
          msg['customerNumber']?.toString() ??
          msg['customer_number']?.toString() ??
          '',
      'direction': msg['direction']?.toString() ?? 'inbound',
      'is_outgoing':
          (msg['isOutgoing'] == true ||
              msg['is_outgoing'] == true ||
              msg['direction']?.toString().contains('out') == true)
          ? 1
          : 0,
      'message_type':
          msg['messageType']?.toString() ?? msg['type']?.toString() ?? 'text',
      'message_content_json': contentJson,
      'status': msg['status']?.toString() ?? 'delivered',
      'created_at': _resolveTimestamp(msg),
      'sync_status': syncStatus,
    };

    await db.insert(
      tableMessages,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllMessages(String restaurantId) async {
    final db = await instance.database;

    // For each contact, we need TWO things independently:
    // 1. The latest message (any direction) — for preview text and sort order
    // 2. The latest INBOUND message — for unread detection
    // We return the latest-overall row but also attach the latest inbound created_at
    // so the badge/green-dot logic can compare against read_at correctly.
    final result = await db.rawQuery(
      '''
      SELECT m.*,
             COALESCE(NULLIF(c.name, ''), m.customer_number) AS customer_name,
             c.read_at AS contact_read_at,
             inb.last_inbound_time AS last_inbound_time
      FROM $tableMessages m
      INNER JOIN (
        SELECT restaurant_id, customer_number, MAX(created_at) AS max_created
        FROM $tableMessages
        WHERE restaurant_id = ?
        GROUP BY restaurant_id, customer_number
      ) latest
        ON m.restaurant_id   = latest.restaurant_id
       AND m.customer_number = latest.customer_number
       AND m.created_at      = latest.max_created
       AND m.restaurant_id   = ?
      LEFT JOIN $tableContacts c
        ON c.restaurant_id   = m.restaurant_id
       AND c.customer_number = m.customer_number
      LEFT JOIN (
        SELECT i.customer_number, i.last_inbound_time, m2.message_content_json AS last_inbound_content
        FROM (
          SELECT customer_number, MAX(created_at) AS last_inbound_time
          FROM $tableMessages
          WHERE restaurant_id = ?
            AND (direction = 'inbound' OR is_outgoing = 0)
          GROUP BY customer_number
        ) i
        INNER JOIN $tableMessages m2
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

    final rows = result
        .map(
          (row) => {
            'id': row['msg_id'],
            '_id': row['msg_id'],
            'customerNumber': row['customer_number'],
            // Show phone number when no real name is saved
            'customerName': () {
              final name = row['customer_name']?.toString() ?? '';
              final phone = row['customer_number']?.toString() ?? '';
              if (name.isEmpty || name == 'WhatsApp User') return phone;
              return name;
            }(),
            'direction': row['direction'],
            'isOutgoing': row['is_outgoing'] == 1,
            'messageType': row['message_type'],
            'messageContent': _safeJsonDecode(
              row['message_content_json']?.toString(),
            ),
            'status': row['status'],
            'createdAt': row['created_at'],
            'syncStatus': row['sync_status'],
            'contactReadAt': row['contact_read_at']?.toString(),
            'lastInboundTime': row['last_inbound_time']?.toString(),
            'lastInboundContent': row['last_inbound_content']
                ?.toString(), // ADD
          },
        )
        .toList();

    // 🚀 FIX: Sort by parsed DateTime so mixed timestamp formats (ISO string vs
    // epoch ms) always produce newest-first order. SQLite string MAX/ORDER can
    // mis-sort when formats are inconsistent across rows.
    rows.sort((a, b) {
      DateTime _parse(String? s) {
        if (s == null || s.isEmpty)
          return DateTime.fromMillisecondsSinceEpoch(0);
        final ms = int.tryParse(s);
        if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
        try {
          return DateTime.parse(s);
        } catch (_) {
          return DateTime.fromMillisecondsSinceEpoch(0);
        }
      }

      return _parse(
        b['createdAt']?.toString(),
      ).compareTo(_parse(a['createdAt']?.toString()));
    });

    return rows;
  }

  dynamic _safeJsonDecode(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      return jsonDecode(s);
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getThreadForContact(
    String restaurantId,
    String customerNumber,
  ) async {
    final db = await instance.database;
    final result = await db.query(
      tableMessages,
      where: 'restaurant_id = ? AND customer_number = ?',
      whereArgs: [restaurantId, customerNumber],
      orderBy: 'created_at DESC',
      limit: 100,
    );

    return result
        .map(
          (row) => {
            'id': row['msg_id'],
            '_id': row['msg_id'],
            'customerNumber': row['customer_number'],
            'direction': row['direction'],
            'isOutgoing': row['is_outgoing'] == 1,
            'messageType': row['message_type'],
            'messageContent': jsonDecode(
              row['message_content_json'].toString(),
            ),
            'status': row['status'],
            'createdAt': row['created_at'],
            'syncStatus': row['sync_status'],
          },
        )
        .toList();
  }

  // ====================================================================
  // 🛒 ORDERS CRUD (Tenant-Scoped)
  // ====================================================================
  Future<void> upsertOrder(
    String restaurantId,
    Map<String, dynamic> order, {
    String syncStatus = 'synced',
  }) async {
    final db = await instance.database;

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

    // 🚀 BUG FIX: Must fetch BOTH columns — previous code fetched only 'additional_notes'
    // so localPayStatus was always '' and the piggyback guard never fired.
    final existingRows = await db.query(
      tableOrders,
      columns: ['additional_notes', 'payment_status'],
      where: 'restaurant_id = ? AND order_id = ?',
      whereArgs: [restaurantId, rawMongoId],
    );
    String localNotes = existingRows.isNotEmpty
        ? (existingRows.first['additional_notes']?.toString() ?? '')
        : '';
    String incomingNotes = order['additionalNotes']?.toString() ?? '';

    if (localNotes.contains('[ACCEPTED]') &&
        !incomingNotes.contains('[ACCEPTED]'))
      incomingNotes = incomingNotes.isEmpty
          ? '[ACCEPTED]'
          : '$incomingNotes\n[ACCEPTED]';
    if (localNotes.contains('[REJECTED]') &&
        !incomingNotes.contains('[REJECTED]'))
      incomingNotes = incomingNotes.isEmpty
          ? '[REJECTED]'
          : '$incomingNotes\n[REJECTED]';
    // Preserve [DELIVERY_BOY:Name|Phone] tag — the server never stores this, so every
    // background sync wipes it from SQLite without this guard.
    final dbTagMatch = RegExp(
      r'\[DELIVERY_BOY:[^\]]*\]',
    ).firstMatch(localNotes);
    if (dbTagMatch != null && !incomingNotes.contains('[DELIVERY_BOY:')) {
      final dbTag = dbTagMatch.group(0)!;
      incomingNotes = incomingNotes.isEmpty ? dbTag : '$incomingNotes\n$dbTag';
    }

    // 🚀 PIGGYBACK FIX: Status can only move FORWARD...

    // 🚀 PIGGYBACK FIX: Status can only move FORWARD, never backward.
    // We define a strict rank order. The resolved status is whichever rank is higher.
    // This prevents a background sync from reverting "completed" back to "assigned"
    // even when the API PUT failed silently and the server still has the old value.
    const Map<String, int> _statusRank = {
      'pending': 0,
      'cod': 1,
      'online': 1,
      'accepted': 2,
      'preparing': 3,
      'assigned': 4,
      'ready': 5,          // 🆕 ADD THIS LINE
      'completed': 6,       // shift completed/paid/rejected up by 1
      'paid': 6,
      'rejected': 6,
    };
    String localPayStatus = existingRows.isNotEmpty
        ? (existingRows.first['payment_status']?.toString() ?? '')
        : '';
    String incomingPayStatus = order['paymentStatus']?.toString() ?? 'pending';

    int localRank = _statusRank[localPayStatus.toLowerCase()] ?? 0;
    int incomingRank = _statusRank[incomingPayStatus.toLowerCase()] ?? 0;

    // Keep whichever status is further along in the fulfilment flow.
    // If ranks are equal, prefer local (already written by the operator's action).
    String resolvedPayStatus = localRank >= incomingRank
        ? localPayStatus
        : incomingPayStatus;
    // Edge case: if local is empty (new order being inserted for the first time), use incoming.
    if (localPayStatus.isEmpty) resolvedPayStatus = incomingPayStatus;

    final map = {
      'restaurant_id': restaurantId,
      'order_id': rawMongoId,
      'display_id': displayId,
      'customer_number': order['customerNumber']?.toString() ?? '',
      'total_amount':
          double.tryParse(order['totalAmount']?.toString() ?? '0') ?? 0.0,
      'payment_status': resolvedPayStatus,
      // order_status mirrors payment_status since we piggyback on one field
      'order_status': resolvedPayStatus,
      'order_type': order['orderType']?.toString() ?? 'whatsapp',
      'items_json': jsonEncode(order['items'] ?? []),
      'location_json': jsonEncode(order['location'] ?? {}),
      'additional_notes': incomingNotes,
      'created_at': createdAtDate,
      'sync_status': syncStatus,
    };

    await db.insert(
      tableOrders,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 🚀 PIGGYBACK HELPER: Updates ONLY the payment_status (combined status) and optional notes
  // for a known mongo order_id. Use this from the screen after every status change so the
  // local DB is updated instantly and background sync can't revert it.
  Future<void> updateOrderStatusLocally(
    String restaurantId,
    String mongoOrderId,
    String newStatus, {
    String? notes,
  }) async {
    final db = await instance.database;
    final values = <String, dynamic>{
      'payment_status': newStatus,
      'order_status': newStatus,
    };
    if (notes != null) values['additional_notes'] = notes;
    await db.update(
      tableOrders,
      values,
      where: 'restaurant_id = ? AND order_id = ?',
      whereArgs: [restaurantId, mongoOrderId],
    );
    print('💾 Local status updated: $mongoOrderId → $newStatus');
  }

  Future<List<Map<String, dynamic>>> getAllOrders(String restaurantId) async {
    final db = await instance.database;
    final result = await db.query(
      tableOrders,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC',
      limit: 200,
    );

    return result
        .map(
          (row) => {
            '_id': row['order_id'],
            'displayId': row['display_id'],
            'orderId':
                row['display_id'] != null &&
                    row['display_id'].toString().isNotEmpty
                ? row['display_id']
                : row['order_id'],
            'customerNumber': row['customer_number'],
            'totalAmount': row['total_amount'],
            // 🚀 PIGGYBACK: paymentStatus carries the combined progress+payment status.
            // The UI reads only this field to decide what to show.
            'paymentStatus': row['payment_status'],
            'orderType': row['order_type'],
            'items': jsonDecode(row['items_json'].toString()),
            'location': jsonDecode(row['location_json'].toString()),
            'additionalNotes': row['additional_notes'],
            'createdAt': row['created_at'],
            'syncStatus': row['sync_status'],
          },
        )
        .toList();
  }

  // ====================================================================
  // 📢 CRM & MARKETING CRUD (Tenant-Scoped + Handles Bug #12)
  // ====================================================================
  /// Inserts a contact ONLY if they don't exist yet.
  /// Used by the message sync path so we never overwrite names/labels the user
  /// has already set manually in the Marketing tab.
  Future<void> upsertContactIfAbsent(
    String restaurantId,
    Map<String, dynamic> contact,
  ) async {
    final db = await instance.database;
    final String phone = contact['phone']?.toString() ?? '';
    if (phone.isEmpty) return;

    final existing = await db.query(
      tableContacts,
      where: 'restaurant_id = ? AND customer_number = ?',
      whereArgs: [restaurantId, phone],
      limit: 1,
    );
    if (existing.isNotEmpty) return; // Already known — don't touch

    final String name = (contact['name']?.toString() ?? '').trim();
    // Use phone as the display name when the API returns no real name.
    // This means the inbox and Marketing tab show the number, not "WhatsApp User".
    final String displayName = name.isNotEmpty && name != 'WhatsApp User'
        ? name
        : phone;
    await db.insert(tableContacts, {
      'restaurant_id': restaurantId,
      'customer_number': phone,
      'name': displayName,
      'status': 'Active',
      'labels_json': '[]',
      'sync_status': 'synced',
      'read_at': DateTime.now()
          .toUtc()
          .toIso8601String(), // treat all existing msgs as read on first insert
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> upsertContact(
    String restaurantId,
    Map<String, dynamic> contact,
  ) async {
    final db = await instance.database;
    final String phone = contact['phone']?.toString() ?? '';
    final String rawName = contact['name']?.toString() ?? '';
    final String displayName = rawName.isNotEmpty && rawName != 'WhatsApp User'
        ? rawName
        : phone;
    final map = {
      'restaurant_id': restaurantId,
      'customer_number': phone,
      'name': displayName,
      'status': contact['status']?.toString() ?? 'Active',
      'labels_json': jsonEncode(contact['labels'] ?? []),
      'sync_status': 'synced',
    };
    if (map['customer_number'].toString().isEmpty) return;
    await db.insert(
      tableContacts,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllContacts(String restaurantId) async {
    final db = await instance.database;
    final result = await db.query(
      tableContacts,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'name ASC',
    );
    return result
        .map(
          (row) => {
            'phone': row['customer_number'],
            'name': row['name'],
            'status': row['status'],
            'labels': jsonDecode(row['labels_json'].toString()),
            'syncStatus': row['sync_status'],
          },
        )
        .toList();
  }

  Future<void> upsertLabel(
    String restaurantId,
    Map<String, dynamic> label,
  ) async {
    final db = await instance.database;
    if (label['is_automated'] != 1) {
      final existing = await db.query(
        tableLabels,
        where: 'restaurant_id = ? AND label_id = ?',
        whereArgs: [restaurantId, label['id'] ?? label['name']],
      );
      if (existing.isNotEmpty && existing.first['is_automated'] == 1)
        return; // Block overwrite!
    }
    final map = {
      'restaurant_id': restaurantId,
      'label_id': label['id'] ?? label['name'],
      'name': label['name'],
      'description': label['description'] ?? '',
      'contact_count': label['count'] ?? 0,
      'is_automated': label['is_automated'] ?? 0,
      'created_at': label['date'] ?? DateTime.now().toIso8601String(),
    };
    await db.insert(
      tableLabels,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllLabels(String restaurantId) async {
    final db = await instance.database;
    final result = await db.query(
      tableLabels,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC',
    );
    return result
        .map(
          (row) => {
            'id': row['label_id'],
            'name': row['name'],
            'description': row['description'],
            'count': row['contact_count'],
            'is_automated': row['is_automated'] ?? 0,
            'date': row['created_at'],
          },
        )
        .toList();
  }

  Future<void> deleteLabel(String restaurantId, String labelId) async {
    final db = await instance.database;

    // 1. Find the label's name before deleting it (we need the name to strip from contacts)
    final labelRows = await db.query(
      tableLabels,
      where: 'restaurant_id = ? AND label_id = ? AND is_automated = 0',
      whereArgs: [restaurantId, labelId],
    );
    if (labelRows.isEmpty) return; // Already gone or is automated

    final String labelName = labelRows.first['name']?.toString() ?? '';

    // 2. Delete the label row
    await db.delete(
      tableLabels,
      where: 'restaurant_id = ? AND label_id = ? AND is_automated = 0',
      whereArgs: [restaurantId, labelId],
    );

    // 3. Strip this label name from every contact that has it
    if (labelName.isNotEmpty) {
      final contacts = await db.query(
        tableContacts,
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
      );

      for (var row in contacts) {
        List<dynamic> labels = jsonDecode(
          row['labels_json']?.toString() ?? '[]',
        );
        if (labels.contains(labelName)) {
          labels.remove(labelName);
          await db.update(
            tableContacts,
            {'labels_json': jsonEncode(labels)},
            where: 'restaurant_id = ? AND customer_number = ?',
            whereArgs: [restaurantId, row['customer_number']],
          );
        }
      }
    }
  }

  Future<void> insertCampaign(
    String restaurantId,
    Map<String, dynamic> campaign,
  ) async {
    final db = await instance.database;
    final map = {
      'restaurant_id': restaurantId,
      'campaign_id':
          campaign['id'] ?? 'camp_${DateTime.now().millisecondsSinceEpoch}',
      'name': campaign['name'],
      'template_name': campaign['template_name'] ?? '',
      'audience_type': campaign['audience_type'] ?? 'All',
      'recipients_count': campaign['recipients'] ?? 0,
      'status': campaign['status'] ?? 'Completed',
      'created_at': campaign['date'] ?? DateTime.now().toIso8601String(),
    };
    await db.insert(
      tableCampaigns,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCampaigns(
    String restaurantId,
  ) async {
    final db = await instance.database;
    final result = await db.query(
      tableCampaigns,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
      orderBy: 'created_at DESC',
    );
    return result
        .map(
          (row) => {
            'id': row['campaign_id'],
            'name': row['name'],
            'template_name': row['template_name'],
            'audience_type': row['audience_type'],
            'recipients': row['recipients_count'],
            'status': row['status'],
            'date': row['created_at'],
          },
        )
        .toList();
  }

  // ====================================================================
  // 🧠 SMART CRM ENGINE (Tenant-Scoped FIX for Bug #12)
  // ====================================================================
  Future<void> runSmartCRMAutomation(String restaurantId) async {
    final db = await instance.database;
    print("🧠 Starting Smart CRM Sweep for Restaurant: $restaurantId...");

    final autoLabels = [
      {
        'id': 'auto_vip',
        'name': '🌟 VIP (5+ Orders)',
        'desc': 'Highly frequent customers',
        'is_automated': 1,
      },
      {
        'id': 'auto_high_roller',
        'name': '💰 High Spender (₹2000+)',
        'desc': 'High lifetime value',
        'is_automated': 1,
      },
      {
        'id': 'auto_lapsing',
        'name': '⚠️ Lapsing (30+ Days)',
        'desc': 'No orders in a month',
        'is_automated': 1,
      },
    ];

    for (var label in autoLabels) {
      await db.insert(tableLabels, {
        'restaurant_id': restaurantId,
        'label_id': label['id'],
        'name': label['name'],
        'description': label['desc'],
        'is_automated': label['is_automated'],
        'contact_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 🚀 FIX: Added WHERE clause to prevent cross-restaurant data aggregation
    final List<Map<String, dynamic>> orderStats = await db.rawQuery(
      '''
      SELECT 
        customer_number, 
        COUNT(order_id) as total_orders, 
        SUM(total_amount) as total_spent, 
        MAX(created_at) as last_order_date
      FROM $tableOrders 
      WHERE restaurant_id = ? AND customer_number != '' 
      GROUP BY customer_number
    ''',
      [restaurantId],
    );

    for (var stat in orderStats) {
      String phone = stat['customer_number'].toString();
      int orderCount = int.tryParse(stat['total_orders'].toString()) ?? 0;
      double totalSpent =
          double.tryParse(stat['total_spent'].toString()) ?? 0.0;

      DateTime? lastOrder;
      try {
        lastOrder = DateTime.parse(stat['last_order_date'].toString());
      } catch (e) {}

      List<String> newSmartTags = [];

      if (orderCount >= 5) newSmartTags.add('🌟 VIP (5+ Orders)');
      if (totalSpent >= 2000) newSmartTags.add('💰 High Spender (₹2000+)');
      if (lastOrder != null &&
          DateTime.now().difference(lastOrder).inDays >= 30) {
        newSmartTags.add('⚠️ Lapsing (30+ Days)');
      }

      if (newSmartTags.isEmpty) continue;

      final existingContact = await db.query(
        tableContacts,
        where: 'restaurant_id = ? AND customer_number = ?',
        whereArgs: [restaurantId, phone],
      );

      List<String> currentLabels = [];
      String contactName = "WhatsApp User";

      if (existingContact.isNotEmpty) {
        contactName =
            existingContact.first['name']?.toString() ?? "WhatsApp User";
        try {
          currentLabels = List<String>.from(
            jsonDecode(
              existingContact.first['labels_json']?.toString() ?? '[]',
            ),
          );
        } catch (e) {}
      }

      currentLabels.removeWhere(
        (l) => l.startsWith('🌟') || l.startsWith('💰') || l.startsWith('⚠️'),
      );
      currentLabels.addAll(newSmartTags);

      await upsertContact(restaurantId, {
        'phone': phone,
        'name': contactName,
        'status': 'Active',
        'labels': currentLabels.toSet().toList(),
      });
    }

    print("🧠 Smart CRM Sweep Complete for $restaurantId!");
  }

  // In DatabaseHelper — add this method
  Future<void> backfillContactsFromMessages(String restaurantId) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT DISTINCT customer_number 
    FROM $tableMessages 
    WHERE restaurant_id = ?
  ''',
      [restaurantId],
    );

    int count = 0;
    for (var row in rows) {
      final phone = row['customer_number']?.toString() ?? '';
      if (phone.isEmpty) continue;
      await upsertContactIfAbsent(restaurantId, {'phone': phone, 'name': ''});
      count++;
    }
    print("✅ Backfill done: $count contacts synced from messages table.");
  }

  /// Recalculates contact_count for every label by scanning labels_json of all contacts.
  /// Call this after any label assignment or removal.
  Future<void> recalculateLabelCounts(String restaurantId) async {
    final db = await instance.database;

    // Tally up how many contacts carry each label name
    final contacts = await db.query(
      tableContacts,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );

    final Map<String, int> counts = {};
    for (var row in contacts) {
      final List<dynamic> labels = jsonDecode(
        row['labels_json']?.toString() ?? '[]',
      );
      for (var label in labels) {
        final name = label.toString();
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }

    // Fetch all labels and update their count
    final labelRows = await db.query(
      tableLabels,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );

    for (var labelRow in labelRows) {
      final String name = labelRow['name']?.toString() ?? '';
      final int newCount = counts[name] ?? 0;
      await db.update(
        tableLabels,
        {'contact_count': newCount},
        where: 'restaurant_id = ? AND label_id = ?',
        whereArgs: [restaurantId, labelRow['label_id']],
      );
    }
  }

  /// Removes any label names from contacts that no longer exist in the labels table.
  /// Runs on every tab load to auto-clean orphaned labels left by older deleteLabel bugs.
  Future<void> cleanupOrphanedLabels(String restaurantId) async {
    final db = await instance.database;

    // 1. Get all valid label names that currently exist for this restaurant
    final labelRows = await db.query(
      tableLabels,
      columns: ['name'],
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );
    final Set<String> validLabelNames = labelRows
        .map((r) => r['name'].toString())
        .toSet();

    // 2. Scan every contact and strip any label NOT in the valid set
    final contacts = await db.query(
      tableContacts,
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );

    for (var row in contacts) {
      List<dynamic> labels = jsonDecode(row['labels_json']?.toString() ?? '[]');
      List<dynamic> cleanedLabels = labels
          .where((l) => validLabelNames.contains(l.toString()))
          .toList();

      // Only write back if something was actually removed
      if (cleanedLabels.length != labels.length) {
        await db.update(
          tableContacts,
          {'labels_json': jsonEncode(cleanedLabels)},
          where: 'restaurant_id = ? AND customer_number = ?',
          whereArgs: [restaurantId, row['customer_number']],
        );
      }
    }
    print("✅ Orphaned label cleanup done for $restaurantId");
  }

  /// Stores the timestamp of the message the user last read for this contact.
  /// A contact is unread only if a newer message has arrived after this timestamp.
  Future<void> markContactAsRead(
    String restaurantId,
    String customerNumber,
    String msgId,
  ) async {
    final db = await instance.database;
    // Use current time — any inbound message that arrived before right now is "read"
    final String readAt = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      '''
    UPDATE $tableContacts
    SET read_at = ?
    WHERE restaurant_id = ? AND customer_number = ?
  ''',
      [readAt, restaurantId, customerNumber],
    );
  }

  /// A contact is "read" if their last inbound message arrived BEFORE or AT
  /// the time the user last opened that chat.
  Future<Set<String>> getReadContactNumbers(String restaurantId) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT c.customer_number
      FROM $tableContacts c
      INNER JOIN (
        SELECT customer_number, MAX(created_at) AS last_msg_time
        FROM $tableMessages
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

  static String _resolveTimestamp(Map<String, dynamic> msg) {
    // Priority 1: top-level ISO timestamp fields
    final candidates = [msg['timestamp'], msg['createdAt'], msg['created_at']];

    for (final raw in candidates) {
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isEmpty) continue;

      // If it looks like a Unix epoch (all digits, 10 chars = seconds, 13 = ms)
      final epoch = int.tryParse(s);
      if (epoch != null) {
        // Convert epoch seconds to ISO
        final ms = s.length >= 13 ? epoch : epoch * 1000;
        return DateTime.fromMillisecondsSinceEpoch(
          ms,
          isUtc: true,
        ).toIso8601String();
      }

      // Try parsing as ISO string
      try {
        return DateTime.parse(s).toUtc().toIso8601String();
      } catch (_) {}
    }

    return DateTime.now().toUtc().toIso8601String();
  }
  // Add near your other settings methods

  Future<String?> getSessionRestaurantId() async {
    final db = await database;
    final result = await db.query(
      tableSettings,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (result.isEmpty) return null;
    final id = result.first['restaurant_id'] as String?;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  Future<void> saveSessionRestaurantId(String restaurantId) async {
    final db = await database;
    final existing = await db.query(
      tableSettings,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (existing.isEmpty) {
      await db.insert(tableSettings, {'id': 1, 'restaurant_id': restaurantId});
    } else {
      await db.update(
        tableSettings,
        {'restaurant_id': restaurantId},
        where: 'id = ?',
        whereArgs: [1],
      );
    }
  }

  Future<void> clearSession() async {
    final db = await database;
    await db.update(
      tableSettings,
      {'restaurant_id': null},
      where: 'id = ?',
      whereArgs: [1],
    );
  }
}
