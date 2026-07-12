import 'dart:convert';
import 'package:http/http.dart' as http;

class CatalogSyncService {
  static final CatalogSyncService instance = CatalogSyncService._init();
  CatalogSyncService._init();

  Future<bool> updateStockInMeta(String retailerId, bool isAvailable, String catalogId, String accessToken) async {
    if (catalogId.isEmpty || accessToken.isEmpty) return false;

    final String url = 'https://graph.facebook.com/v19.0/$catalogId/items_batch';
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
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteItemInMeta(String retailerId, String catalogId, String accessToken) async {
    if (catalogId.isEmpty || accessToken.isEmpty || retailerId.isEmpty) return false;

    final String url = 'https://graph.facebook.com/v19.0/$catalogId/items_batch';
    final payload = {
      "item_type": "PRODUCT_ITEM",
      "requests": [
        {
          "method": "DELETE",
          "id": retailerId,
          "retailer_id": retailerId,
          "data": {"id": retailerId},
        },
      ],
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateItemDetailsInMeta(String retailerId, String title, double price, String productLink, String catalogId, String accessToken) async {
    if (catalogId.isEmpty || accessToken.isEmpty || retailerId.isEmpty) return false;

    final String url = 'https://graph.facebook.com/v19.0/$catalogId/items_batch';
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
            "link": productLink.isNotEmpty ? productLink : "https://wa.me",
          },
        },
      ],
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> addItemToMeta({required String retailerId, required String title, required double price, required String description, required String imageUrl, required String productLink, required String catalogId, required String accessToken}) async {
    if (catalogId.isEmpty || accessToken.isEmpty || retailerId.isEmpty) return false;

    final String url = 'https://graph.facebook.com/v19.0/$catalogId/items_batch';
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
            "image_link": imageUrl.isNotEmpty ? imageUrl : "https://placehold.co/600x600/096A56/FFFFFF.png",
            "link": productLink.isNotEmpty ? productLink : "https://wa.me",
            "brand": "TYM",
          },
        },
      ],
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<dynamic>> fetchCatalogFromMeta(String catalogId, String accessToken) async {
    if (catalogId.isEmpty || accessToken.isEmpty) return [];

    List<dynamic> allItems = [];
    String? nextUrl = 'https://graph.facebook.com/v19.0/$catalogId/products?fields=id,retailer_id,name,description,price,image_url,availability&limit=1000';

    try {
      while (nextUrl != null) {
        final response = await http.get(
          Uri.parse(nextUrl),
          headers: {'Authorization': 'Bearer $accessToken'},
        );

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final items = decoded['data'] ?? [];
          allItems.addAll(items);

          if (decoded['paging'] != null && decoded['paging']['cursors'] != null && decoded['paging']['cursors']['after'] != null) {
            nextUrl = decoded['paging']['next'];
          } else {
            nextUrl = null; 
          }
        } else {
          break; 
        }
      }
      return allItems;
    } catch (e) {
      return allItems;
    }
  }
}