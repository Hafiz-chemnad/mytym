import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';
import 'delivery_boy_db.dart';

class DeliveryBoyApi {
  static final DeliveryBoyApi instance = DeliveryBoyApi._init();
  DeliveryBoyApi._init();

  /// On-demand fetch — no background polling. Delivery boys change rarely,
  /// so we just pull fresh data whenever the dialog opens, and immediately
  /// after any add/edit/delete. Pulls all pages, then re-seeds the local
  /// SQLite cache so getAllDeliveryBoys() stays the single read source
  /// the UI already uses.
  Future<void> refreshDeliveryBoys(String restaurantId) async {
    try {
      int currentPage = 1;
      int totalPages = 1;

      while (currentPage <= totalPages) {
        final url = Uri.parse(
          '${CrmApiClient.baseUrl}/api/$restaurantId/delivery-boys?limit=50&page=$currentPage',
        );
        final response = await http.get(url);

        if (response.statusCode != 200) break;

        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        totalPages = int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;

        for (var item in items) {
          await DeliveryBoyDbService.instance.upsertDeliveryBoyLocal(restaurantId, {
            'name': item['name'],
            'phone': item['phone'],
          });
        }

        currentPage++;
      }
    } catch (e) {
      // Offline / backend down — local SQLite cache is used as-is, no crash.
    }
  }

  Future<bool> addDeliveryBoy(String restaurantId, String name, String phone) async {
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/delivery-boys'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"name": name, "phone": phone}),
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await DeliveryBoyDbService.instance.upsertDeliveryBoyLocal(restaurantId, {
          'name': saved['name'],
          'phone': saved['phone'],
        });
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateDeliveryBoyName(String restaurantId, String phone, String newName) async {
    try {
      final response = await http.put(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/delivery-boys/$phone'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"name": newName}),
      );
      if (response.statusCode == 200) {
        await DeliveryBoyDbService.instance.updateDeliveryBoyNameLocal(restaurantId, phone, newName);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteDeliveryBoy(String restaurantId, String phone) async {
    try {
      final response = await http.delete(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/delivery-boys/$phone'),
      );
      if (response.statusCode == 200) {
        await DeliveryBoyDbService.instance.deleteDeliveryBoyLocal(restaurantId, phone);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}