import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbConnection {
  static final DbConnection instance = DbConnection._init();
  static Database? _database;

  DbConnection._init();

  // 🚀 Table Names centralized here for the entire app to use
  static const String tableSettings = 'settings';
  static const String tableMenu = 'menu_items';
  static const String tableOrders = 'orders';
  static const String tableMessages = 'messages';
  static const String tableContacts = 'contacts';
  static const String tableLabels = 'labels';
  static const String tableCampaigns = 'campaigns';
  static const String tableDeliveryBoys = 'delivery_boys';
  static const String tableActiveSession = 'active_session';
  static const String tableTemplates = 'templates'; // 🚀 ADDED templates table constant

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('test2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

return await openDatabase(
      path,
      version: 13,   // 🚀 BUMPED to version 13 for Contacts metadata
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableSettings (
        restaurant_id TEXT PRIMARY KEY,
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

    await db.execute('''
      CREATE TABLE $tableActiveSession (
        id INTEGER PRIMARY KEY DEFAULT 1,
        restaurant_id TEXT
      )
    ''');

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

    await db.execute('''
      CREATE TABLE $tableContacts (
        restaurant_id TEXT,
        customer_number TEXT,
        name TEXT,
        status TEXT DEFAULT 'Active',
        labels_json TEXT DEFAULT '[]',
        sync_status TEXT DEFAULT 'synced',
        read_at TEXT,
        source TEXT DEFAULT 'manual',      // 🚀 ADD THIS
        created_at TEXT,                   // 🚀 ADD THIS
        PRIMARY KEY (restaurant_id, customer_number)
      )
    ''');

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

    await db.execute('''
      CREATE TABLE $tableCampaigns (
        restaurant_id TEXT,
        campaign_id TEXT,
        name TEXT,
        template_name TEXT,
        audience_type TEXT,
        label_id TEXT,
        recipients_count INTEGER,
        sent_count INTEGER DEFAULT 0,
        failed_count INTEGER DEFAULT 0,
        delivered_count INTEGER DEFAULT 0,
        read_count INTEGER DEFAULT 0,
        status TEXT,
        recipients_json TEXT DEFAULT '[]',
        created_at TEXT,
        PRIMARY KEY (restaurant_id, campaign_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableDeliveryBoys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        restaurant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        UNIQUE(restaurant_id, phone)
      )
    ''');

    await db.execute('''
  CREATE TABLE $tableTemplates (
    restaurant_id TEXT,
    template_id TEXT,
    name TEXT,
    category TEXT,
    language TEXT,
    body_text TEXT,
    variable_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'PENDING',
    rejected_reason TEXT,
    variable_mapping_json TEXT DEFAULT '{}',
    header_type TEXT DEFAULT 'NONE',
    header_text TEXT,
    buttons_json TEXT DEFAULT '[]',
    created_at TEXT,
    updated_at TEXT,
    PRIMARY KEY (restaurant_id, name)
  )
''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute('ALTER TABLE $tableOrders ADD COLUMN display_id TEXT'); } catch (e) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS $tableContacts (customer_number TEXT PRIMARY KEY, name TEXT, status TEXT DEFAULT "Active", labels_json TEXT DEFAULT "[]", sync_status TEXT DEFAULT "synced")');
        await db.execute('CREATE TABLE IF NOT EXISTS $tableLabels (label_id TEXT PRIMARY KEY, name TEXT, description TEXT, contact_count INTEGER DEFAULT 0, is_automated INTEGER DEFAULT 0, created_at TEXT)');
        await db.execute('CREATE TABLE IF NOT EXISTS $tableCampaigns (campaign_id TEXT PRIMARY KEY, name TEXT, template_name TEXT, audience_type TEXT, recipients_count INTEGER, status TEXT, created_at TEXT)');
      } catch (e) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('DROP TABLE IF EXISTS $tableMenu');
        await db.execute('DROP TABLE IF EXISTS $tableOrders');
        await db.execute('DROP TABLE IF EXISTS $tableMessages');
        await db.execute('DROP TABLE IF EXISTS $tableContacts');
        await db.execute('DROP TABLE IF EXISTS $tableLabels');
        await db.execute('DROP TABLE IF EXISTS $tableCampaigns');
        await _createDB(db, 4);
      } catch (e) {}
    }
    if (oldVersion < 5) {
      try { await db.execute('CREATE TABLE IF NOT EXISTS $tableDeliveryBoys (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL UNIQUE)'); } catch (e) {}
    }
    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE $tableMessages ADD COLUMN read_at TEXT'); } catch (e) {}
    }
    if (oldVersion < 7) {
      try { await db.execute('ALTER TABLE $tableContacts ADD COLUMN read_at TEXT'); } catch (e) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('DROP TABLE IF EXISTS $tableSettings');
        await db.execute('''
          CREATE TABLE $tableSettings (
            restaurant_id TEXT PRIMARY KEY, name TEXT, waba_id TEXT, phone_number_id TEXT, wa_token TEXT, catalog_id TEXT, address TEXT, latitude REAL, longitude REAL, service_type TEXT, payment_availability TEXT, primary_flow TEXT, delivery_flow TEXT, delivery_radius REAL, welcome_video_url TEXT, welcome_video_id TEXT, rzp_key TEXT, rzp_secret TEXT, sheet_url TEXT, sheet_id TEXT
          )
        ''');
        await db.execute('CREATE TABLE IF NOT EXISTS $tableActiveSession (id INTEGER PRIMARY KEY DEFAULT 1, restaurant_id TEXT)');
        await db.execute('DROP TABLE IF EXISTS $tableDeliveryBoys');
        await db.execute('CREATE TABLE $tableDeliveryBoys (id INTEGER PRIMARY KEY AUTOINCREMENT, restaurant_id TEXT NOT NULL, name TEXT NOT NULL, phone TEXT NOT NULL, UNIQUE(restaurant_id, phone))');
      } catch (e) {}
    }
    if (oldVersion < 9) {
      try { await db.execute('ALTER TABLE $tableCampaigns ADD COLUMN label_id TEXT'); } catch (e) {}
      try { await db.execute('ALTER TABLE $tableCampaigns ADD COLUMN sent_count INTEGER DEFAULT 0'); } catch (e) {}
      try { await db.execute('ALTER TABLE $tableCampaigns ADD COLUMN failed_count INTEGER DEFAULT 0'); } catch (e) {}
      try { await db.execute("ALTER TABLE $tableCampaigns ADD COLUMN recipients_json TEXT DEFAULT '[]'"); } catch (e) {}
    }
    // 🚀 ADDED Upgrade step for Templates
    if (oldVersion < 10) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableTemplates (
            restaurant_id TEXT,
            template_id TEXT,
            name TEXT,
            category TEXT,
            language TEXT,
            body_text TEXT,
            variable_count INTEGER DEFAULT 0,
            status TEXT DEFAULT 'PENDING',
            rejected_reason TEXT,
            variable_mapping_json TEXT DEFAULT '{}',
            header_type TEXT DEFAULT 'NONE',  -- 🚀 ADD THIS
            header_text TEXT,
            created_at TEXT,
            updated_at TEXT,
            PRIMARY KEY (restaurant_id, name)
          )
        ''');
      } catch (e) {
        print("Migration error v10: $e");
      }
    }
    if (oldVersion < 11) {
  try { await db.execute("ALTER TABLE $tableTemplates ADD COLUMN buttons_json TEXT DEFAULT '[]'"); } catch (e) {}
  try { await db.execute("ALTER TABLE $tableCampaigns ADD COLUMN button_url_param TEXT"); } catch (e) {}
}
if (oldVersion < 12) {
  try { await db.execute("ALTER TABLE $tableCampaigns ADD COLUMN delivered_count INTEGER DEFAULT 0"); } catch (e) {}
  try { await db.execute("ALTER TABLE $tableCampaigns ADD COLUMN read_count INTEGER DEFAULT 0"); } catch (e) {}
}
if (oldVersion < 13) {
      try { await db.execute("ALTER TABLE $tableContacts ADD COLUMN source TEXT DEFAULT 'manual'"); } catch (e) {}
      try { await db.execute("ALTER TABLE $tableContacts ADD COLUMN created_at TEXT"); } catch (e) {}
    }
  
  }
}