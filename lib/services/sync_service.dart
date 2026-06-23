import 'dart:convert';
import 'package:http/http.dart' as http;

class SyncService {

  
  // 🚀 The function now requires the dynamic catalogId and accessToken
  Future<bool> updateStockInMeta(String retailerId, bool isAvailable, String catalogId, String accessToken) async {
    
    // Safety check: Don't try to sync if tokens are missing
    if (catalogId.isEmpty || accessToken.isEmpty) {
      print("❌ Missing Catalog ID or Meta Token in restaurant profile.");
      return false;
    }

    final String url = 'https://graph.facebook.com/v19.0/$catalogId/items_batch';
    final String newStatus = isAvailable ? 'in stock' : 'out of stock';

    final payload = {
      "item_type": "PRODUCT_ITEM",
      "requests": [
        {
          "method": "UPDATE",
          "retailer_id": retailerId,
          "data": { "availability": newStatus }
        }
      ]
    };

    try {
      print("Sending instant Meta stock update for $retailerId to: $newStatus...");
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );
      
      if (response.statusCode == 200) {
        print("✅ Meta Catalog updated successfully!");
        return true;
      } else {
        print("❌ Meta Update Failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Meta Update Exception: $e");
      return false;
    }
  }
}