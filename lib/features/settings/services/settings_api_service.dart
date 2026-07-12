import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';

class SettingsApiService {
  static final SettingsApiService instance = SettingsApiService._init();
  SettingsApiService._init();

  Future<Map<String, dynamic>?> fetchRestaurantProfile(
    String restaurantId, {
    int retries = 1,
  }) async {
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/api/restaurants');
      final response = await http.get(url).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> restaurants = jsonDecode(response.body);
        final profile = restaurants.firstWhere(
          (r) => r['_id'] == restaurantId || r['id'] == restaurantId,
          orElse: () => null,
        );
        return profile;
      }
    } catch (e) {
      if (retries > 0) {
        return fetchRestaurantProfile(restaurantId, retries: retries - 1);
      }
    }
    return null;
  }

  Future<bool> updateRestaurantSettings(
    String restaurantId,
    Map<String, dynamic> updatedData,
  ) async {
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/api/restaurants/$restaurantId');
      final response = await http.put(
        url,
        headers: ApiClient.defaultHeaders,
        body: jsonEncode(updatedData),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }
}