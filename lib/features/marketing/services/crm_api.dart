import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:whatsapp_erp/core/network/api_client.dart';
import 'package:whatsapp_erp/core/network/crm_api_client.dart';
import 'dart:typed_data'; // 🚀 ADDED THIS


class CrmApi {
  static final CrmApi instance = CrmApi._init();
  CrmApi._init();

  Future<bool> sendTemplateMessage({
    required String restaurantId,
    required String customerNumber,
    required String templateName,
    List<String> templateParams = const [],
  }) async {
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/api/sendTemplateMessage');
      final response = await http.post(
        url,
        headers: ApiClient.defaultHeaders,
        body: jsonEncode({
          "restaurantId": restaurantId,
          "customerNumber": customerNumber,
          "templateName": templateName,
          "templateParams": templateParams,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }

      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData.containsKey('success') && responseData['success'] == false) return false;
        if (responseData.containsKey('error') || 
           (responseData.containsKey('message') && responseData['message'].toString().toLowerCase().contains('fail'))) {
          return false;
        }
      } catch (e) {
        // Ignored
      }

      return true; 
    } catch (e) {
      return false;
    }
  }
Future<String?> sendMediaTemplateBypass({
    required String restaurantId,
    required String phoneNumberId, 
    required String accessToken,
    required String customerNumber,
    required String templateName,
    required String languageCode, // 🚀 1. ADD THIS REQUIRED FIELD
    required List<String> templateParams,
    String headerType = "NONE",
    String? mediaUrl,
    String? mediaId, 
    String? buttonUrlParam,// 🚀 ADDED THIS
  }) async {
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates/send-message');
      
      final response = await http.post(
        url,
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({
          "phone_number_id": phoneNumberId,
          "access_token": accessToken,
          "to_phone": customerNumber,
          "template_name": templateName,
          "language_code": languageCode, // 🚀 2. USE THE DYNAMIC VARIABLE HERE
          "body_params": templateParams,
          "header_type": headerType,
          "media_url": mediaUrl,
          "media_id": mediaId,
          "button_url_param": buttonUrlParam, // 🚀 ADDED THIS
        }),
      );

     // 🚀 THE FIX: Return the WAMID string on success, and null on failure
// 🚀 THE FIX: Parse the JSON and extract the real WAMID
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['wamid']?.toString(); 
      }
      return null;
      
    } catch (e) {
      return null;
    }
  }

  // 🚀 NEW: Securely upload the physical file to the Python Backend
  Future<String?> uploadMediaToBackend({
    required String restaurantId,
    required String phoneNumberId,
    required String accessToken,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates/upload-media')
      );

      request.fields['phone_number_id'] = phoneNumberId;
      request.fields['access_token'] = accessToken;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        )
      );

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseData);
        return decoded['media_id']; // Success! We got the Meta Media ID
      } else {
        print("Upload Failed: $responseData");
        return null;
      }
    } catch (e) {
      print("Upload Crashed: $e");
      return null;
    }
  }
}