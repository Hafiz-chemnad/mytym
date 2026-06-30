import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/database_helper.dart';

class ApiService {
  final String baseUrl = "https://tym-whatsapp-backend.onrender.com";

  // 🚀 FIX: Cache is now keyed by restaurantId so multiple restaurants
  // never bleed into each other's menu state during one app session.
  // Lazily initialized to [] (never left null) so the helper methods
  // below can never silently no-op.
  static final Map<String, List<dynamic>> _menuCacheByRestaurant = {};
  // 🚀 FIX BUG #6: Sync Guards to prevent SQLite File Locks
  static bool _isSyncingMessages = false;
  static bool _isSyncingOrders = false;
  static final Map<String, bool> _initialOrderSyncDoneByRestaurant = {};
  // ✅ ADD THIS LINE right here:
  static final Map<String, bool> _initialSyncDoneByRestaurant = {};
  static List<dynamic> _cacheFor(String restaurantId) {
    return _menuCacheByRestaurant.putIfAbsent(restaurantId, () => []);
  }

  // 🚀 Thread API: ഒരു കസ്റ്റമറുടെ ഫുൾ ചാറ്റ് എടുക്കാൻ
  // 🚀 Thread API: ഒരു കസ്റ്റമറുടെ ഫുൾ ചാറ്റ് എടുക്കാൻ
  // 🚀 Thread API: ഒരു കസ്റ്റമറുടെ ഫുൾ ചാറ്റ് എടുക്കാൻ
  Future<List<dynamic>> fetchChatThread(
    String restaurantId,
    String customerNumber,
  ) async {
    try {
      // 🚀 മാറ്റം: limit=500 ആക്കി! പഴയ മെസ്സേജുകൾ എല്ലാം വരാൻ
      final url = Uri.parse(
        '$baseUrl/api/restaurant-messages/thread?restaurantId=$restaurantId&customerNumber=$customerNumber&limit=500&page=1',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body is Map) {
          return body['thread'] ?? body['data'] ?? body['messages'] ?? [];
        } else if (body is List) {
          return body;
        }
      }
    } catch (e) {
      print("Error fetching thread: $e");
    }
    return [];
  }

  // 🚀 General Send & Store API: Now fully Offline-First optimized!
  // 🚀 General Send & Store API: Now fully Offline-First optimized!
  Future<bool> sendMessage({
    required String to,
    required String text,
    required String restaurantId,
    required String phoneNumberId,
  }) async {
    try {
      print("🚀 ATTEMPTING TO SEND WHATSAPP MESSAGE:");
      print("➡️ To: $to");
      print("➡️ Restaurant ID: $restaurantId");

      // A. WhatsApp വഴി മെസ്സേജ് അയക്കുന്നു
      final sendUrl = Uri.parse('$baseUrl/api/sendTextMessage');
      final requestBody = {
        "restaurantId": restaurantId,
        "customerNumber": to,
        "customerId": to,
        "phoneNumberId": phoneNumberId,
        "messageText": text,
      };

      print(
        "📤 SENDING TO BACKEND: ${jsonEncode(requestBody)}",
      ); // 🧪 see exact payload

      final sendResponse = await http.post(
        sendUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "restaurantId": restaurantId,
          "customerNumber": to,
          "customerId": to,
          "phoneNumberId": phoneNumberId,
          "messageText": text,
        }),
      );

      // 🚀 DEBUG: Print exactly what the server says!
      print("📡 BACKEND STATUS: ${sendResponse.statusCode}");

      print("📡 BACKEND RESPONSE: ${sendResponse.body}");
      print("➡️ Phone Number ID: $phoneNumberId");
      // B. ഡാറ്റാബേസിൽ സ്റ്റോർ ചെയ്യുന്നു
      if (sendResponse.statusCode == 200 || sendResponse.statusCode == 201) {
        // 🚀 CRITICAL FIX: Sometimes Meta returns 200 OK but the JSON contains an error inside!
        try {
          final decoded = jsonDecode(sendResponse.body);
          if (decoded['success'] == false ||
              decoded['status'] == 'failed' ||
              decoded['error'] != null) {
            print("❌ META REJECTED THE MESSAGE: ${sendResponse.body}");
            return false;
          }
        } catch (e) {
          // Response wasn't JSON, ignore
        }

        final storeUrl = Uri.parse('$baseUrl/api/restaurant-messages/store');
        await http.post(
          storeUrl,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "restaurantId": restaurantId,
            "customerNumber": to,
            "phoneNumberId": phoneNumberId,
            "messageType": "text",
            "messageContent": text,
            "customerId": to,
          }),
        );

        String tempId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
        // 🚀 FIX: Pass restaurantId as the first argument
        await DatabaseHelper.instance.upsertMessage(restaurantId, {
          'id': tempId,
          'customerNumber': to,
          'direction': 'outbound',
          'isOutgoing': true,
          'messageType': 'text',
          'messageContent': {
            'text': {'body': text},
          },
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        });

        return true;
      } else {
        print("❌ BACKEND REJECTED THE REQUEST!");
        return false;
      }
    } catch (e) {
      print("❌ Error in sendMessage exception: $e");
      return false;
    }
  }

  // 🚀 Live Orders എടുക്കാൻ
  Future<List<dynamic>> fetchLiveOrders(String restaurantId) async {
    try {
      final url = Uri.parse(
        '$baseUrl/api/orders/restaurant/$restaurantId?limit=50&page=1',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['orders'] ?? [];
      }
    } catch (e) {
      print("Fetch Orders Error: $e");
    }
    return [];
  }

  // 📊 Order Stats എടുക്കാൻ
  Future<Map<String, dynamic>> fetchOrderStats(String restaurantId) async {
    try {
      final url = Uri.parse(
        '$baseUrl/api/orders/restaurant/$restaurantId/stats',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Fetch Stats Error: $e");
    }
    return {};
  }

  // 🚀 Combined Status Update: paymentStatus field carries BOTH payment method + order progress.
  // Piggybacking: "COD", "Online", "accepted", "preparing", "assigned", "completed", "rejected", "paid"
  // The backend only sees one field: paymentStatus.
  Future<bool> updateOrderStatus({
    required String restaurantId,
    required String orderId,
    required String status, // The ONE combined status string sent to backend
    required String notes,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/orders/$orderId/status');
      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"paymentStatus": status, "additionalNotes": notes}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  // ----------------------------------------------------
  // 🍔 MENU MANAGEMENT APIs
  // ----------------------------------------------------

  // 1. ഫുൾ മെനു എടുക്കാൻ (GET)
  // ----------------------------------------------------
  // 🍔 MENU / CATALOG APIs
  // ----------------------------------------------------

  // 1. Fetch unified Catalog Items (Replaces the old manual menu endpoint)
  // ----------------------------------------------------
  // 🍔 MENU / CATALOG APIs
  // ----------------------------------------------------

  // ----------------------------------------------------
  // 🍔 MENU / CATALOG APIs
  // ----------------------------------------------------

  // 1. Fetch unified Catalog Items (With Smart Fallback)
  // 1. Fetch unified Catalog Items (With Smart Fallback & Caching)
  Future<List<dynamic>> fetchMenu(String restaurantId) async {
    final cache = _cacheFor(restaurantId);

    try {
      print("🔍 Fetching catalog items for ID: $restaurantId");

      // STEP 1: Try the proper GET endpoint
      final getUrl = Uri.parse('$baseUrl/api/catalog/$restaurantId/items');
      final getResponse = await http.get(getUrl);

      if (getResponse.statusCode == 200) {
        final decoded = jsonDecode(getResponse.body);
        List<dynamic> fetchedItems = [];

        if (decoded is List)
          fetchedItems = decoded;
        else if (decoded is Map && decoded.containsKey('items'))
          fetchedItems = decoded['items'];
        else if (decoded is Map && decoded.containsKey('data'))
          fetchedItems = decoded['data'];

        if (fetchedItems.isNotEmpty) {
          // 🚀 FIX: We no longer treat the DB as the sole source of truth and
          // wipe the cache. Since adds/edits/deletes are written directly to
          // Meta (and the DB endpoint is known to not persist them), a DB
          // response is merged on top of whatever Meta-only changes we're
          // already holding, rather than overwriting them.
          _mergeIntoCache(cache, fetchedItems);
          print(
            "✅ DB returned ${fetchedItems.length} item(s); merged into cache.",
          );
          return List<dynamic>.from(cache);
        }
      }

      // STEP 2: CACHE CHECK (Prevents UI from resetting!)
      print("⚠️ Database returned 0 items. Checking local RAM cache...");
      if (cache.isNotEmpty) {
        print("✅ Serving menu directly from Local Memory Cache!");
        return List<dynamic>.from(cache);
      }

      // STEP 3: BACKEND BUG WORKAROUND (Only runs if Cache is empty)
      print("⚠️ Cache empty. Triggering Fallback Sync directly from Sheet...");

      final syncUrl = Uri.parse('$baseUrl/api/catalog/sync-sheet');
      final syncResponse = await http.post(
        syncUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"restaurantId": restaurantId}),
      );

      if (syncResponse.statusCode == 200) {
        final syncDecoded = jsonDecode(syncResponse.body);
        if (syncDecoded is Map && syncDecoded.containsKey('items')) {
          print("✅ Fallback Sync Successful! Saving to local cache.");
          // 🚀 FIX: merge rather than replace — if cache already held
          // Meta-only items (shouldn't happen here since cache was empty,
          // but kept for safety/consistency with the other call sites).
          _mergeIntoCache(cache, syncDecoded['items'] as List<dynamic>);
          return List<dynamic>.from(cache);
        }
      }

      return List<dynamic>.from(cache);
    } catch (e) {
      print("❌ Fetch Catalog Error: $e");
      return List<dynamic>.from(cache); // Return cache if network fails
    }
  }

  // 🚀 Shared identity resolver — every cache helper and fetchMenu use this
  // exact same key order so an item created via one path is always
  // findable via any other path.
  static String _identityOf(dynamic item) {
    if (item is! Map) return '';
    return (item['id'] ??
            item['retailerId'] ??
            item['retailer_id'] ??
            item['retailerid'] ??
            '')
        .toString();
  }

  // 🚀 Merges incoming items and CLEARS deleted ghost items
  static void _mergeIntoCache(List<dynamic> cache, List<dynamic> incoming) {
    // 1. Keep a record of all IDs that are currently "alive" in the incoming data
    final Set<String> incomingIds = {};

    for (final incomingItem in incoming) {
      final id = _identityOf(incomingItem);

      if (id.isEmpty) {
        cache.add(incomingItem);
        continue;
      }

      incomingIds.add(id); // Mark this ID as alive

      final existingIndex = cache.indexWhere((e) => _identityOf(e) == id);
      if (existingIndex == -1) {
        // Item is new, add it
        cache.add(incomingItem);
      } else {
        // Item exists, update it but preserve local availability state
        final existing = cache[existingIndex];
        if (existing is Map &&
            incomingItem is Map &&
            !incomingItem.containsKey('isAvailable')) {
          incomingItem['isAvailable'] = existing['isAvailable'];
          incomingItem['availability'] = existing['availability'];
        }
        cache[existingIndex] = incomingItem;
      }
    }

    // 🚀 2. THE FIX: The Garbage Collector
    // Sweep through the RAM cache. If an item has an ID, but that ID was NOT
    // in the incoming list, it means it was deleted from Meta/SQLite. Remove it from RAM!
    cache.removeWhere((cacheItem) {
      final id = _identityOf(cacheItem);
      return id.isNotEmpty && !incomingIds.contains(id);
    });
  }

  // 🚀 Updates the local cache instantly when a switch is toggled.
  // No more null-guard — cache is always a real list, so this can never
  // silently no-op.
  void updateCacheItemAvailability(
    String restaurantId,
    String id,
    bool isAvailable,
  ) {
    final cache = ApiService._cacheFor(restaurantId);
    for (var item in cache) {
      if (ApiService._identityOf(item) == id) {
        item['isAvailable'] = isAvailable;
        item['availability'] = isAvailable ? 'in stock' : 'out of stock';
        print("💾 Updated RAM Cache for item $id to $isAvailable");
        return;
      }
    }
    print("⚠️ Tried to update availability for $id but it wasn't in cache.");
  }

  // 2. പുതിയ വിഭവം ചേർക്കാൻ (POST)
  Future<bool> addMenuItem(
    String restaurantId,
    Map<String, dynamic> itemData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/restaurant/$restaurantId/menu'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(itemData),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Add Menu Error: $e");
      return false;
    }
  }

  // 3. നിലവിലുള്ള വിഭവത്തിന്റെ വില/പേര് മാറ്റാൻ (PUT)
  Future<bool> updateMenuItem(
    String restaurantId,
    int catIndex,
    int itemIndex,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final response = await http.put(
        Uri.parse(
          '$baseUrl/api/restaurant/$restaurantId/menu/$catIndex/$itemIndex',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(updateData),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Update Menu Error: $e");
      return false;
    }
  }

  // 4. വിഭവം ഡിലീറ്റ് ചെയ്യാൻ (DELETE)
  Future<bool> deleteMenuItem(
    String restaurantId,
    int catIndex,
    int itemIndex,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse(
          '$baseUrl/api/restaurant/$restaurantId/menu/$catIndex/$itemIndex',
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Delete Menu Error: $e");
      return false;
    }
  }

  // ⚙️ റെസ്റ്റോറന്റ് പ്രൊഫൈൽ ഡാറ്റ എടുക്കാൻ (GET)
  Future<Map<String, dynamic>?> fetchRestaurantProfile(
    String restaurantId,
  ) async {
    try {
      final url = Uri.parse('$baseUrl/api/restaurants');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> restaurants = jsonDecode(response.body);
        // ലിസ്റ്റിൽ നിന്ന് ലോഗിൻ ചെയ്ത റെസ്റ്റോറന്റിനെ മാത്രം ഫിൽറ്റർ ചെയ്ത് എടുക്കുന്നു
        final profile = restaurants.firstWhere(
          (r) => r['_id'] == restaurantId || r['id'] == restaurantId,
          orElse: () => null,
        );
        return profile;
      }
    } catch (e) {
      print("Profile Fetch Error: $e");
    }
    return null;
  }

  // ⚙️ റെസ്റ്റോറന്റ് Razorpay / WABA കീകൾ അപ്ഡേറ്റ് ചെയ്യാൻ (PUT)
  // ⚙️ റെസ്റ്റോറന്റ് Razorpay / WABA കീകൾ അപ്ഡേറ്റ് ചെയ്യാൻ (PATCH പതിപ്പ്)
  Future<bool> updateRestaurantSettings(
    String restaurantId,
    Map<String, dynamic> updatedData,
  ) async {
    try {
      // Assuming your backend lead used PUT for full updates based on standard REST practices
      // Change to http.patch if they specifically require PATCH
      final url = Uri.parse('$baseUrl/api/restaurants/$restaurantId');
      print("🔍 Updating Restaurant URL: $url");

      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(updatedData),
      );

      print("📡 Update Response Status Code: ${response.statusCode}");
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print("❌ Update Failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Update Exception: $e");
      return false;
    }
  }

  // 📢 Marketing: Send Template Message (Broadcast)
  Future<bool> sendTemplateMessage({
    required String restaurantId,
    required String customerNumber,
    required String templateName,
    List<String> templateParams = const [],
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/sendTemplateMessage');
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "restaurantId": restaurantId,
          "customerNumber": customerNumber,
          "templateName": templateName,
          "templateParams": templateParams,
        }),
      );

      // 1. If the server throws a hard error (like 400 or 500)
      if (response.statusCode != 200 && response.statusCode != 201) {
        print("Backend Error: ${response.statusCode} - ${response.body}");
        return false;
      }

      // 2. If the server says 200 OK, let's double-check the JSON body just in case Meta rejected it
      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body);

        // If your backend lead uses a "success: false" flag
        if (responseData.containsKey('success') &&
            responseData['success'] == false) {
          print("Meta Validation Failed: ${response.body}");
          return false;
        }

        // If your backend lead returns an "error" or "message" key when it fails
        if (responseData.containsKey('error') ||
            (responseData.containsKey('message') &&
                responseData['message'].toString().toLowerCase().contains(
                  'fail',
                ))) {
          print("Meta Validation Failed: ${response.body}");
          return false;
        }
      } catch (e) {
        // If the response isn't JSON, but status is 200, assume it worked
      }

      return true; // Fully successful!
    } catch (e) {
      print("Template Send Error: $e");
      return false;
    }
  }
  // ----------------------------------------------------
  // 🔄 CATALOG SYNC APIs
  // ----------------------------------------------------

  // 1. Sync from WhatsApp/Meta Catalog
  Future<int> syncMetaCatalog(String restaurantId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/catalog/sync'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"restaurantId": restaurantId}),
      );
      return response.statusCode;
    } catch (e) {
      print("Meta Sync Error: $e");
      return 500;
    }
  }

  // 2. Sync from Google Sheets
  Future<int> syncGoogleSheet(String restaurantId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/catalog/sync-sheet'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"restaurantId": restaurantId}),
      );
      return response.statusCode;
    } catch (e) {
      print("Sheet Sync Error: $e");
      return 500;
    }
  }

  // ====================================================================
  // 🔄 BACKGROUND SYNC WORKER (MESSAGES)
  // ====================================================================
  // ====================================================================
  // 🔄 BACKGROUND SYNC WORKER (MESSAGES)
  // ====================================================================
  Future<void> syncMessagesBackground(String restaurantId) async {
    if (_isSyncingMessages) return;
    _isSyncingMessages = true;

    try {
      int currentPage = 1;
      int totalPages = 1;

      do {
        final url = Uri.parse(
          '$baseUrl/api/restaurant-messages/restaurant/$restaurantId?direction=inbound&limit=50&page=$currentPage',
        );

        final response = await http.get(url);

        if (response.statusCode != 200) {
          print(
            "❌ Message sync error on page $currentPage: ${response.statusCode}",
          );
          break;
        }

        final dynamic decoded = jsonDecode(response.body);
        List<dynamic> msgs = [];
        if (decoded is Map) {
          msgs = decoded['messages'] ?? decoded['data'] ?? [];
          // ✅ Read totalPages from the API response
          totalPages =
              int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;
        } else if (decoded is List) {
          msgs = decoded;
        }

        for (var msg in msgs) {
          await DatabaseHelper.instance.upsertMessage(restaurantId, msg);

          // ✅ Register every customer into contacts
          final String phone = msg['customerNumber']?.toString() ?? '';
          if (phone.isNotEmpty) {
            await DatabaseHelper.instance.upsertContactIfAbsent(restaurantId, {
              'phone': phone,
              'name': msg['customerName']?.toString() ?? '',
            });
          }
        }

        if (msgs.isNotEmpty) {
          print(
            "📥 Message sync page $currentPage/$totalPages: ${msgs.length} messages.",
          );
        }

        // ✅ Only paginate on first run; after DB is populated, page 1 is enough
        // To avoid hammering the API every poll tick, only do full scan once
        if (_initialSyncDoneByRestaurant[restaurantId] != true) {
          currentPage++;
        } else {
          break;
        }
      } while (currentPage <= totalPages);

      _initialSyncDoneByRestaurant[restaurantId] = true;
    } catch (e) {
      print("❌ Message sync exception: $e");
    } finally {
      _isSyncingMessages = false;
    }
    await DatabaseHelper.instance.backfillContactsFromMessages(restaurantId);
    _initialSyncDoneByRestaurant[restaurantId] = true;
  }

  Future<void> syncOrdersBackground(String restaurantId) async {
    if (_isSyncingOrders) return; // 🚀 Block overlapping timers!
    _isSyncingOrders = true;

    try {
      int currentPage = 1;
      int totalPages = 1;
      bool hasMorePages = true;
      int totalSavedThisSync = 0;

      while (hasMorePages) {
        // After initial full sync, only poll page 1 for new orders
        if (_initialOrderSyncDoneByRestaurant[restaurantId] == true &&
            currentPage > 1) {
          hasMorePages = false;
          break;
        }
        final url = Uri.parse(
          '$baseUrl/api/orders/restaurant/$restaurantId?limit=50&page=$currentPage',
        );
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final body = json.decode(response.body);
          List<dynamic> orders = body['orders'] ?? [];

          // Safety break if the server returns an empty list unexpectedly
          if (orders.isEmpty) break;

          // Save this page's orders to SQLite
          for (var order in orders) {
            await DatabaseHelper.instance.upsertOrder(restaurantId, order);
          }

          totalSavedThisSync += orders.length;

          // 🚀 Pagination Logic based on your Swagger Docs
          totalPages = body['totalPages'] ?? 1;

          if (currentPage >= totalPages) {
            hasMorePages = false; // We reached the end!
          } else {
            currentPage++; // Move to the next page for the next loop iteration
          }
        } else {
          print(
            "❌ Background Sync Error on page $currentPage: ${response.statusCode}",
          );
          break; // Stop looping if the server throws an error (e.g., 500)
        }
      }

      if (totalSavedThisSync > 0) {
        print(
          "📥 Background Sync: Saved $totalSavedThisSync orders to SQLite across $currentPage pages.",
        );
        // Tell the CRM engine which restaurant to calculate!
      }
      _initialOrderSyncDoneByRestaurant[restaurantId] = true;
    } catch (e) {
      print("❌ Background Order Sync Exception: $e");
    } finally {
      _isSyncingOrders = false; // 🚀 Release the lock
    }
  }
}
