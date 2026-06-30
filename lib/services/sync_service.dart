import 'dart:convert';
import 'package:http/http.dart' as http;

class SyncService {
  // 🟢 1. Toggle Stock Status
  Future<bool> updateStockInMeta(
    String retailerId,
    bool isAvailable,
    String catalogId,
    String accessToken,
  ) async {
    if (catalogId.isEmpty || accessToken.isEmpty) {
      print("❌ Missing Catalog ID or Meta Token.");
      return false;
    }

    final String url =
        'https://graph.facebook.com/v19.0/$catalogId/items_batch';
    final String newStatus = isAvailable ? 'in stock' : 'out of stock';

    final payload = {
      "item_type": "PRODUCT_ITEM",
      "requests": [
        {
          "method": "UPDATE",
          "id": retailerId,
          "retailer_id": retailerId,
          "data": {"id": retailerId, "availability": newStatus},
        },
      ],
    };

    try {
      print(
        "Sending instant Meta stock update for $retailerId to: $newStatus...",
      );
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      print("📡 Meta Status Code: ${response.statusCode}");
      print("🔍 RAW META RESPONSE: ${response.body}");

      return response.statusCode == 200;
    } catch (e) {
      print("❌ Meta Update Exception: $e");
      return false;
    }
  }

  // 🔴 2. DELETE an item entirely from Meta
  // 🔴 2. DELETE an item entirely from Meta
  Future<bool> deleteItemInMeta(
    String retailerId,
    String catalogId,
    String accessToken,
  ) async {
    if (catalogId.isEmpty || accessToken.isEmpty || retailerId.isEmpty)
      return false;

    final String url =
        'https://graph.facebook.com/v19.0/$catalogId/items_batch';
    final payload = {
      "item_type": "PRODUCT_ITEM",
      "requests": [
        {
          "method": "DELETE",
          "id": retailerId, // 🚀 What Meta specifically asked for
          "retailer_id": retailerId, // 🚀 Standard Meta identifier
          "data": {
            "id": retailerId, // 🚀 Sometimes Meta looks for it inside 'data'
          },
        },
      ],
    };

    try {
      print("🗑️ Deleting $retailerId from Meta Catalog...");
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      print("📡 Meta Status Code: ${response.statusCode}");
      print("🔍 RAW META RESPONSE (DELETE): ${response.body}");

      return response.statusCode == 200;
    } catch (e) {
      print("❌ Meta Delete Exception: $e");
      return false;
    }
  }

  // 📝 3. UPDATE Item Details (Name & Price) in Meta
  // 📝 3. UPDATE Item Details (Name, Price & Link) in Meta
  Future<bool> updateItemDetailsInMeta(
    String retailerId,
    String title,
    double price,
    String productLink,
    String catalogId,
    String accessToken,
  ) async {
    if (catalogId.isEmpty || accessToken.isEmpty || retailerId.isEmpty)
      return false;

    final String url =
        'https://graph.facebook.com/v19.0/$catalogId/items_batch';
    final payload = {
      "item_type": "PRODUCT_ITEM",
      "requests": [
        {
          "method": "UPDATE",
          "retailer_id": retailerId,
          "data": {
            "id": retailerId,
            "title": title,
            "price": "${price.toStringAsFixed(2)} INR",
            "link": productLink.isNotEmpty
                ? productLink
                : "https://wa.me", // 🚀 FIX: Dynamic Link Support
          },
        },
      ],
    };

    try {
      print("📝 Updating details for $retailerId in Meta Catalog...");
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      print("📡 Meta Status Code: ${response.statusCode}");
      print("🔍 RAW META RESPONSE (UPDATE): ${response.body}");

      return response.statusCode == 200;
    } catch (e) {
      print("❌ Meta Edit Exception: $e");
      return false;
    }
  }

  // ➕ 4. CREATE a brand new item in Meta
  Future<bool> addItemToMeta({
    required String retailerId,
    required String title,
    required double price,
    required String description,
    required String imageUrl,
    required String productLink, // 🚀 NEW: Required Parameter
    required String catalogId,
    required String accessToken,
  }) async {
    if (catalogId.isEmpty || accessToken.isEmpty || retailerId.isEmpty)
      return false;

    final String url =
        'https://graph.facebook.com/v19.0/$catalogId/items_batch';
    final payload = {
      "item_type": "PRODUCT_ITEM",
      "requests": [
        {
          "method": "CREATE",
          "data": {
            "id": retailerId,
            "title": title,
            "description": description.isNotEmpty ? description : "Menu Item",
            "availability": "in stock",
            "condition": "new",
            "price": "${price.toStringAsFixed(2)} INR",
            "image_link": imageUrl.isNotEmpty
                ? imageUrl
                : "https://placehold.co/600x600/096A56/FFFFFF.png",
            "link": productLink.isNotEmpty
                ? productLink
                : "https://wa.me", // 🚀 FIX: Dynamic Link Support
            "brand": "TYM",
          },
        },
      ],
    };

    try {
      print("➕ Creating $retailerId in Meta Catalog...");
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      print("📡 Meta Status Code: ${response.statusCode}");
      print("🔍 RAW META RESPONSE (CREATE): ${response.body}");

      return response.statusCode == 200;
    } catch (e) {
      print("❌ Meta Create Exception: $e");
      return false;
    }
  }

  // 📥 5. FETCH Entire Catalog from Meta (For First-Time Seed)
  // 📥 5. FETCH Entire Catalog from Meta (For First-Time Seed)
  Future<List<dynamic>> fetchCatalogFromMeta(
    String catalogId,
    String accessToken,
  ) async {
    if (catalogId.isEmpty || accessToken.isEmpty) return [];

    List<dynamic> allItems = [];
    // 🚀 BUG #13 FIX: Start with the first page URL
    String? nextUrl =
        'https://graph.facebook.com/v19.0/$catalogId/products?fields=id,retailer_id,name,description,price,image_url,availability&limit=1000';

    try {
      print("📥 Seeding from Meta Catalog $catalogId...");

      // 🚀 Loop until there are no more pages
      while (nextUrl != null) {
        final response = await http.get(
          Uri.parse(nextUrl),
          headers: {'Authorization': 'Bearer $accessToken'},
        );

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final items = decoded['data'] ?? [];
          allItems.addAll(items); // Add this page's items to our master list

          // Check if Meta provided a link to the "next" page
          if (decoded['paging'] != null &&
              decoded['paging']['cursors'] != null &&
              decoded['paging']['cursors']['after'] != null) {
            nextUrl = decoded['paging']['next'];
          } else {
            nextUrl = null; // No more pages, exit loop
          }
        } else {
          print("❌ Meta Fetch Failed: ${response.body}");
          break; // Stop looping on error
        }
      }

      print("✅ Meta Fetch Success! Found ${allItems.length} total items.");
      return allItems;
    } catch (e) {
      print("❌ Meta Fetch Exception: $e");
    }
    return allItems;
  }
}
