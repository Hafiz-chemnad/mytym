import 'package:sqflite/sqflite.dart';
import '../../../core/database/db_connection.dart';
import '../../auth/services/auth_db_service.dart';

class SettingsDbService {
  static final SettingsDbService instance = SettingsDbService._init();
  SettingsDbService._init();

  Future<Database> get _db async => await DbConnection.instance.database;

  Future<void> saveSettings(Map<String, dynamic> rawData) async {
    final database = await _db;

    String extractString(dynamic val) {
      if (val == null) return '';
      if (val is Map) return val['\$oid']?.toString() ?? '';
      if (val is List) return ''; 
      return val.toString();
    }

    final cleanSettings = {
      'restaurant_id': extractString(rawData['_id'] ?? rawData['id']),
      'name': extractString(rawData['name']),
      'waba_id': extractString(rawData['wabaId']),
      'phone_number_id': extractString(rawData['phoneNumberId']),
      'wa_token': extractString(rawData['waToken']),
      'catalog_id': extractString(rawData['catalogId']),
      'address': extractString(rawData['address']),
      'latitude': double.tryParse(rawData['latitude']?.toString() ?? '0') ?? 0.0,
      'longitude': double.tryParse(rawData['longitude']?.toString() ?? '0') ?? 0.0,
      'service_type': extractString(rawData['serviceType']),
      'payment_availability': extractString(rawData['paymentAvailability']),
      'primary_flow': extractString(rawData['primaryFlowType']),
      'delivery_flow': extractString(rawData['deliveryFlowType']),
      'delivery_radius': double.tryParse(rawData['deliveryRadius']?.toString() ?? '0') ?? 0.0,
      'welcome_video_url': extractString(rawData['welcomeVideoUrl']),
      'welcome_video_id': extractString(rawData['welcomeVideoMediaId']),
      'rzp_key': extractString(rawData['razorpayKeyId']),
      'rzp_secret': extractString(rawData['razorpayKeySecret']),
      'sheet_url': extractString(rawData['googleSheetUrl']),
      'sheet_id': extractString(rawData['googleSheetId']),
    };

    await database.insert(
      DbConnection.tableSettings,
      cleanSettings,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSettings() async {
    final database = await _db;
    final activeRestaurantId = await AuthDbService.instance.getSessionRestaurantId();
    if (activeRestaurantId == null || activeRestaurantId.isEmpty) return null;
    
    final result = await database.query(
      DbConnection.tableSettings,
      where: 'restaurant_id = ?',
      whereArgs: [activeRestaurantId],
    );

    if (result.isNotEmpty) {
      final row = result.first;
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
}