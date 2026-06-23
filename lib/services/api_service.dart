import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl = "https://tym-whatsapp-backend.onrender.com";

  // 🚀 Thread API: ഒരു കസ്റ്റമറുടെ ഫുൾ ചാറ്റ് എടുക്കാൻ
 // 🚀 Thread API: ഒരു കസ്റ്റമറുടെ ഫുൾ ചാറ്റ് എടുക്കാൻ
  // 🚀 Thread API: ഒരു കസ്റ്റമറുടെ ഫുൾ ചാറ്റ് എടുക്കാൻ
  Future<List<dynamic>> fetchChatThread(String restaurantId, String customerNumber) async {
    try {
      // 🚀 മാറ്റം: limit=500 ആക്കി! പഴയ മെസ്സേജുകൾ എല്ലാം വരാൻ
      final url = Uri.parse('$baseUrl/api/restaurant-messages/thread?restaurantId=$restaurantId&customerNumber=$customerNumber&limit=500&page=1');
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

  // 🚀 General Send & Store API: phoneNumberId ഇപ്പോൾ ഡൈനാമിക് ആണ്
  Future<bool> sendMessage({
    required String to, 
    required String text, 
    required String restaurantId, 
    required String phoneNumberId, // 👈 ജനറൽ ആക്കാൻ ഇത് പാരാമീറ്റർ ആയി മാറ്റി
  }) async {
    try {
      // A. WhatsApp വഴി മെസ്സേജ് അയക്കുന്നു
      final sendUrl = Uri.parse('$baseUrl/api/sendTextMessage');
      final sendResponse = await http.post(
        sendUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "restaurantId": restaurantId,
          "customerNumber": to,
          "messageText": text
        }),
      );

      // B. ഡാറ്റാബേസിൽ സ്റ്റോർ ചെയ്യുന്നു
      if (sendResponse.statusCode == 200 || sendResponse.statusCode == 201) {
        final storeUrl = Uri.parse('$baseUrl/api/restaurant-messages/store');
        await http.post(
          storeUrl,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "restaurantId": restaurantId,
            "customerNumber": to,
            "phoneNumberId": phoneNumberId, // 👈 ഇവിടെ റെസ്റ്റോറന്റിന്റെ സ്വന്തം ID വരുന്നു
            "messageType": "text", 
            "messageContent": text,
            "customerId": to
          }),
        );
        return true;
      }
      return false;
    } catch (e) {
      print("Error in sendMessage: $e");
      return false;
    }
  }
  // 🚀 Live Orders എടുക്കാൻ
  Future<List<dynamic>> fetchLiveOrders(String restaurantId) async {
    try {
      final url = Uri.parse('$baseUrl/api/orders/restaurant/$restaurantId?limit=50&page=1');
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
      final url = Uri.parse('$baseUrl/api/orders/restaurant/$restaurantId/stats');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body); 
      }
    } catch (e) {
      print("Fetch Stats Error: $e");
    }
    return {};
  }

  // 🚀 Payment Status & Notes അപ്ഡേറ്റ് ചെയ്യാൻ (യഥാർത്ഥ PUT API പ്രകാരം)
  Future<bool> updateOrderStatus({
    required String orderId, 
    required String paymentStatus, 
    required String notes
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/orders/$orderId/status');
      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "paymentStatus": paymentStatus, // paid അല്ലെങ്കിൽ pending
          "additionalNotes": notes        // ചീഫ് നോട്സ്
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Update Status Error: $e");
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
  Future<List<dynamic>> fetchMenu(String restaurantId) async {
    try {
      print("🔍 Fetching catalog items for ID: $restaurantId"); 
      
      // STEP 1: Try the proper GET endpoint
      final getUrl = Uri.parse('$baseUrl/api/catalog/$restaurantId/items');
      final getResponse = await http.get(getUrl);
      
      if (getResponse.statusCode == 200) {
        final decoded = jsonDecode(getResponse.body);
        List<dynamic> fetchedItems = [];

        if (decoded is List) fetchedItems = decoded;
        else if (decoded is Map && decoded.containsKey('items')) fetchedItems = decoded['items'];
        else if (decoded is Map && decoded.containsKey('data')) fetchedItems = decoded['data'];

        // If the database actually has items, return them!
        if (fetchedItems.isNotEmpty) {
          return fetchedItems;
        }
      }

      // STEP 2: BACKEND BUG WORKAROUND 
      // If GET returns 0 items, force a Sync to grab the 89 items directly from the Google Sheet
      print("⚠️ Database returned 0 items. Triggering Fallback Sync...");
      
      final syncUrl = Uri.parse('$baseUrl/api/catalog/sync-sheet');
      final syncResponse = await http.post(
        syncUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"restaurantId": restaurantId}),
      );

      if (syncResponse.statusCode == 200) {
        final syncDecoded = jsonDecode(syncResponse.body);
        if (syncDecoded is Map && syncDecoded.containsKey('items')) {
          print("✅ Fallback Sync Successful! Loaded items directly from Sheet.");
          return syncDecoded['items']; // Returns the 89 items directly!
        }
      }
      
      return [];
    } catch (e) {
      print("❌ Fetch Catalog Error: $e");
      return [];
    }
  }
  // 2. പുതിയ വിഭവം ചേർക്കാൻ (POST)
  Future<bool> addMenuItem(String restaurantId, Map<String, dynamic> itemData) async {
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
  Future<bool> updateMenuItem(String restaurantId, int catIndex, int itemIndex, Map<String, dynamic> updateData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/restaurant/$restaurantId/menu/$catIndex/$itemIndex'),
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
  Future<bool> deleteMenuItem(String restaurantId, int catIndex, int itemIndex) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/restaurant/$restaurantId/menu/$catIndex/$itemIndex'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Delete Menu Error: $e");
      return false;
    }
  }
  // ⚙️ റെസ്റ്റോറന്റ് പ്രൊഫൈൽ ഡാറ്റ എടുക്കാൻ (GET)
  Future<Map<String, dynamic>?> fetchRestaurantProfile(String restaurantId) async {
    try {
      final url = Uri.parse('$baseUrl/api/restaurants');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final List<dynamic> restaurants = jsonDecode(response.body);
        // ലിസ്റ്റിൽ നിന്ന് ലോഗിൻ ചെയ്ത റെസ്റ്റോറന്റിനെ മാത്രം ഫിൽറ്റർ ചെയ്ത് എടുക്കുന്നു
        final profile = restaurants.firstWhere(
          (r) => r['_id'] == restaurantId || r['id'] == restaurantId, 
          orElse: () => null
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
 Future<bool> updateRestaurantSettings(String restaurantId, Map<String, dynamic> updatedData) async {
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
          "templateParams": templateParams
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
        if (responseData.containsKey('success') && responseData['success'] == false) {
          print("Meta Validation Failed: ${response.body}");
          return false;
        }
        
        // If your backend lead returns an "error" or "message" key when it fails
        if (responseData.containsKey('error') || (responseData.containsKey('message') && responseData['message'].toString().toLowerCase().contains('fail'))) {
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
}