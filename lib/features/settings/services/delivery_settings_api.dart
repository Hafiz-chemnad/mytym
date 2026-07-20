import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';

class DeliverySettingsApi {
  static final DeliverySettingsApi instance = DeliverySettingsApi._init();
  DeliverySettingsApi._init();

 Future<Map<String, dynamic>?> getSettings(String restaurantId) async {
  try {
    final response = await http.get(
      Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/delivery-settings'),
      headers: CrmApiClient.defaultHeaders,
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return {
        'sendPickup': decoded['send_pickup_message'] ?? false,
        'sendDelivered': decoded['send_delivered_message'] ?? true,
        'deliveryCharge': double.tryParse(decoded['delivery_charge']?.toString() ?? '0') ?? 0.0,
      };
    }
    return null;
  } catch (e) {
    return null;
  }
}

Future<bool> updateSettings(String restaurantId, {bool? sendPickup, bool? sendDelivered, double? deliveryCharge}) async {
  try {
    final body = <String, dynamic>{};
    if (sendPickup != null) body['send_pickup_message'] = sendPickup;
    if (sendDelivered != null) body['send_delivered_message'] = sendDelivered;
    if (deliveryCharge != null) body['delivery_charge'] = deliveryCharge;   // ADD THIS

    final response = await http.put(
      Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/delivery-settings'),
      headers: CrmApiClient.defaultHeaders,
      body: jsonEncode(body),
    );
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}
}