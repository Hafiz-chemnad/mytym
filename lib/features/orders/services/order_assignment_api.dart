import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';
import '../models/order_assignment.dart';

class OrderAssignmentApi {
  static final OrderAssignmentApi instance = OrderAssignmentApi._init();
  OrderAssignmentApi._init();

  /// Fetches all assignments for the restaurant. Called alongside
  /// _fetchOrdersAndStats() so live_orders_screen can join by order_id.
  /// Fails silently (empty list) — status just won't show until next poll.
  Future<List<OrderAssignment>> getAssignments(String restaurantId) async {
    try {
      final response = await http.get(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/assignments'),
        headers: CrmApiClient.defaultHeaders,
      );
      if (response.statusCode == 200) {
        final List<dynamic> decoded = jsonDecode(response.body);
        return decoded.map((json) => OrderAssignment.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}