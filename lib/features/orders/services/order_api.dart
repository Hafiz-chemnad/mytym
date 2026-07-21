import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';
import 'order_db.dart';

class OrderApi {
  static final OrderApi instance = OrderApi._init();
  OrderApi._init();

  // 🚀 Sync Guards to prevent SQLite File Locks
  static final Map<String, bool> _isSyncingOrders = {};  
  static final Map<String, bool> _initialOrderSyncDoneByRestaurant = {};

  // 🚀 Live Orders എടുക്കാൻ
  Future<List<dynamic>> fetchLiveOrders(String restaurantId) async {
    try {
      final url = Uri.parse(
        '${ApiClient.baseUrl}/api/orders/restaurant/$restaurantId?limit=50&page=1',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
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
        '${ApiClient.baseUrl}/api/orders/restaurant/$restaurantId/stats',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Fetch Stats Error: $e");
    }
    return {};
  }

  // 🚀 Combined Status Update
  Future<bool> updateOrderStatus({
    required String restaurantId,
    required String orderId,
    required String status,
    required String notes,
  }) async {
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/api/orders/$orderId/status');
      final response = await http.put(
        url,
        headers: ApiClient.defaultHeaders,
        body: jsonEncode({"paymentStatus": status, "additionalNotes": notes}),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ====================================================================
  // 🔄 BACKGROUND SYNC WORKER (ORDERS)
  // ====================================================================
  Future<void> syncOrdersBackground(String restaurantId) async {
    if (_isSyncingOrders[restaurantId] == true) return; // 🚀 Block overlapping timers!
    _isSyncingOrders[restaurantId] = true;

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
          '${ApiClient.baseUrl}/api/orders/restaurant/$restaurantId?limit=50&page=$currentPage',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final body = json.decode(response.body);
          List<dynamic> orders = body['orders'] ?? [];

          // Safety break if the server returns an empty list unexpectedly
          if (orders.isEmpty) break;

          // Save this page's orders to SQLite
          for (var order in orders) {
            await OrderDbService.instance.upsertOrder(restaurantId, order);
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
      }
      _initialOrderSyncDoneByRestaurant[restaurantId] = true;
    } catch (e) {
      print("❌ Background Order Sync Exception: $e");
    } finally {
      _isSyncingOrders[restaurantId] = false; // 🚀 Release the lock
    }
  }
}