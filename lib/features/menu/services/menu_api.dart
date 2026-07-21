import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';
import '../../../core/network/crm_api_client.dart';
import 'menu_db.dart';

class MenuApi {
  static final MenuApi instance = MenuApi._init();
  MenuApi._init();

  // 🚀 Sync guards for the new FastAPI menu sync (separate from the
  // existing Meta/Google-Sheet catalog cache below)
  static final Map<String, bool> _isSyncingMenu = {};
  static final Map<String, bool> _initialMenuSyncDoneByRestaurant = {};

  static final Map<String, List<dynamic>> _menuCacheByRestaurant = {};

  static List<dynamic> _cacheFor(String restaurantId) {
    return _menuCacheByRestaurant.putIfAbsent(restaurantId, () => []);
  }

  static String _identityOf(dynamic item) {
    if (item is! Map) return '';
    return (item['id'] ?? item['retailerId'] ?? item['retailer_id'] ?? item['retailerid'] ?? '').toString();
  }

  static void _mergeIntoCache(List<dynamic> cache, List<dynamic> incoming) {
    final Set<String> incomingIds = {};

    for (final incomingItem in incoming) {
      final id = _identityOf(incomingItem);
      if (id.isEmpty) {
        cache.add(incomingItem);
        continue;
      }

      incomingIds.add(id);

      final existingIndex = cache.indexWhere((e) => _identityOf(e) == id);
      if (existingIndex == -1) {
        cache.add(incomingItem);
      } else {
        final existing = cache[existingIndex];
        if (existing is Map && incomingItem is Map && !incomingItem.containsKey('isAvailable')) {
          incomingItem['isAvailable'] = existing['isAvailable'];
          incomingItem['availability'] = existing['availability'];
        }
        cache[existingIndex] = incomingItem;
      }
    }

    cache.removeWhere((cacheItem) {
      final id = _identityOf(cacheItem);
      return id.isNotEmpty && !incomingIds.contains(id);
    });
  }

  Future<List<dynamic>> fetchMenu(String restaurantId) async {
    final cache = _cacheFor(restaurantId);

    try {
      final getUrl = Uri.parse('${ApiClient.baseUrl}/api/catalog/$restaurantId/items');
      final getResponse = await http.get(getUrl);

      if (getResponse.statusCode == 200) {
        final decoded = jsonDecode(getResponse.body);
        List<dynamic> fetchedItems = [];

        if (decoded is List) fetchedItems = decoded;
        else if (decoded is Map && decoded.containsKey('items')) fetchedItems = decoded['items'];
        else if (decoded is Map && decoded.containsKey('data')) fetchedItems = decoded['data'];

        if (fetchedItems.isNotEmpty) {
          _mergeIntoCache(cache, fetchedItems);
          return List<dynamic>.from(cache);
        }
      }

      if (cache.isNotEmpty) {
        return List<dynamic>.from(cache);
      }

      final syncUrl = Uri.parse('${ApiClient.baseUrl}/api/catalog/sync-sheet');
      final syncResponse = await http.post(
        syncUrl,
        headers: ApiClient.defaultHeaders,
        body: jsonEncode({"restaurantId": restaurantId}),
      );

      if (syncResponse.statusCode == 200) {
        final syncDecoded = jsonDecode(syncResponse.body);
        if (syncDecoded is Map && syncDecoded.containsKey('items')) {
          _mergeIntoCache(cache, syncDecoded['items'] as List<dynamic>);
          return List<dynamic>.from(cache);
        }
      }

      return List<dynamic>.from(cache);
    } catch (e) {
      return List<dynamic>.from(cache);
    }
  }

  void updateCacheItemAvailability(String restaurantId, String id, bool isAvailable) {
    final cache = _cacheFor(restaurantId);
    for (var item in cache) {
      if (_identityOf(item) == id) {
        item['isAvailable'] = isAvailable;
        item['availability'] = isAvailable ? 'in stock' : 'out of stock';
        return;
      }
    }
  }

  
  // ====================================================================
  // 🔄 BACKGROUND SYNC WORKER (MENU) — new FastAPI/Mongo backend
  // ====================================================================
  Future<void> syncMenuBackground(String restaurantId) async {
    if (_isSyncingMenu[restaurantId] == true) return;
    _isSyncingMenu[restaurantId] = true;

    try {
      int currentPage = 1;
      int totalPages = 1;
      int totalSaved = 0;

      while (true) {
        if (_initialMenuSyncDoneByRestaurant[restaurantId] == true && currentPage > 1) {
          break;
        }

        final url = Uri.parse(
          '${CrmApiClient.baseUrl}/api/$restaurantId/menu?limit=50&page=$currentPage',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          print("❌ Menu sync error on page $currentPage: ${response.statusCode}");
          break;
        }

        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        totalPages = int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;

        if (items.isEmpty) break;

        for (var item in items) {
          await MenuDbService.instance.upsertMenuItem(restaurantId, item);
        }
        totalSaved += items.length;

        if (currentPage >= totalPages) break;
        currentPage++;
      }

      if (totalSaved > 0) {
        print("📥 Menu sync: saved $totalSaved items across $currentPage pages.");
      }
      _initialMenuSyncDoneByRestaurant[restaurantId] = true;
    } catch (e) {
      print("❌ Menu sync exception: $e");
    } finally {
      _isSyncingMenu[restaurantId] = false;
    }
  }
  // ====================================================================
// ✏️ WRITE PATH — new FastAPI/Mongo backend (source of truth for menu)
// ====================================================================
Future<bool> createOrUpdateItemOnErpBackend(
  String restaurantId,
  Map<String, dynamic> item, {
  String? catalogId,
  String? accessToken,
}) async {
  try {
    final response = await http.post(
      Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/menu'),
      headers: CrmApiClient.defaultHeaders,
      body: jsonEncode({
        "retailer_id": item['retailerId'] ?? item['id'],
        "name": item['name'],
        "price": item['price'],
        "category": item['category'] ?? "Menu Item",
        "image_url": item['imageUrl'] ?? '',
        "is_available": item['isAvailable'] ?? true,
        "is_veg": item['isVeg'] ?? false,
        if (catalogId != null && catalogId.isNotEmpty) "catalog_id": catalogId,
        if (accessToken != null && accessToken.isNotEmpty) "access_token": accessToken,
      }),
    );
    if (response.statusCode == 200) {
      final saved = jsonDecode(response.body);
      await MenuDbService.instance.upsertMenuItem(restaurantId, saved);
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

Future<bool> deleteItemOnErpBackend(
  String restaurantId,
  String retailerId, {
  String? catalogId,
  String? accessToken,
}) async {
  try {
    final response = await http.delete(
      Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/menu/$retailerId'),
      headers: CrmApiClient.defaultHeaders,
      body: jsonEncode({
        if (catalogId != null && catalogId.isNotEmpty) "catalog_id": catalogId,
        if (accessToken != null && accessToken.isNotEmpty) "access_token": accessToken,
      }),
    );
    if (response.statusCode == 200) {
      await MenuDbService.instance.deleteMenuItemLocally(restaurantId, retailerId);
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

  /// Partial update — used for the availability toggle (and any other
  /// single/few-field edit) without re-sending the whole item.
  Future<bool> updateFieldsOnErpBackend(
    String restaurantId,
    String retailerId,
    Map<String, dynamic> fields, {
    String? catalogId,
    String? accessToken,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/menu/$retailerId'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({
          "fields": fields,
          if (catalogId != null && catalogId.isNotEmpty) "catalog_id": catalogId,
          if (accessToken != null && accessToken.isNotEmpty) "access_token": accessToken,
        }),
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await MenuDbService.instance.upsertMenuItem(restaurantId, saved);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Triggers the backend's Meta -> Mongo pull (the ONLY place Meta is
  /// ever read from now). Returns the number of items synced, or null on failure.
  Future<int?> triggerMetaSync(
    String restaurantId,
    String catalogId,
    String accessToken,
  ) async {
    if (catalogId.isEmpty || accessToken.isEmpty) return null;
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/menu/sync-meta'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"catalog_id": catalogId, "access_token": accessToken}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return int.tryParse(decoded['synced_count']?.toString() ?? '0');
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}