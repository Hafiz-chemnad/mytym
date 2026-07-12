import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';

class AuthApi {
  static final AuthApi instance = AuthApi._init();
  AuthApi._init();

  Future<bool> verifyRestaurantId(String enteredId) async {
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/api/restaurants');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> restaurants = jsonDecode(response.body);
        return restaurants.any((r) => r['_id'] == enteredId || r['id'] == enteredId);
      }
      return false;
    } catch (e) {
      throw Exception("Network Error");
    }
  }

  Future<String?> registerRestaurant(Map<String, dynamic> payload) async {
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/api/restaurants');
      final response = await http.post(
        url,
        headers: ApiClient.defaultHeaders,
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        if (responseData.containsKey('restaurant') && responseData['restaurant'] != null) {
          return responseData['restaurant']['_id'] ?? "ID_NOT_FOUND";
        }
        return "ID_NOT_FOUND";
      }
      return null;
    } catch (e) {
      throw Exception("Network Error");
    }
  }
}