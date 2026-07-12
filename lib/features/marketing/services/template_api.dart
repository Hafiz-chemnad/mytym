import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';
import 'template_db.dart';

class TemplateApi {
  static final TemplateApi instance = TemplateApi._init();
  TemplateApi._init();

  Future<void> refreshTemplates(String restaurantId) async {
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        for (var item in items) {
          await TemplateDbService.instance.upsertTemplate(restaurantId, item);
        }
      }
    } catch (e) {
      // Offline/backend down — local cache is used as-is.
    }
  }

  Future<bool> refreshTemplateStatus(String restaurantId, String wabaId, String accessToken) async {
    if (wabaId.isEmpty || accessToken.isEmpty) return false;
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates/refresh-status');
      final response = await http.post(
        url,
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"waba_id": wabaId, "access_token": accessToken}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        for (var item in items) {
          await TemplateDbService.instance.upsertTemplate(restaurantId, item);
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> createTemplate(
    String restaurantId, {
    required String wabaId,
    required String accessToken,
    required String name,
    required String category,
    required String language,
    required String bodyText,
    String headerType = "NONE",
    String? headerText,
    List<Map<String, dynamic>>? buttons,
  }) async {
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates');
      final response = await http.post(
        url,
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({
          "waba_id": wabaId,
          "access_token": accessToken,
          "name": name,
          "category": category,
          "language": language,
          "body_text": bodyText,
          "header_type": headerType,
          "header_text": headerText,
          "buttons": buttons,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await TemplateDbService.instance.upsertTemplate(restaurantId, saved);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 🚀 NEW: pushes the owner's variable-mapping choices (e.g. blank #1 =
  /// Contact Name) to the backend so they're remembered across devices /
  /// reinstalls, not just in local SQLite. Called alongside the existing
  /// local-only TemplateDbService.updateVariableMapping() — that one
  /// stays for instant local reads, this one is the actual persistence.
  Future<bool> saveVariableMapping(
    String restaurantId,
    String templateName,
    Map<String, dynamic> mapping,
  ) async {
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates/$templateName/mapping');
      final response = await http.patch(
        url,
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"variable_mapping": mapping}),
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteTemplate(String restaurantId, String name, String wabaId, String accessToken) async {
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/templates/$name');
      final response = await http.delete(
        url,
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"waba_id": wabaId, "access_token": accessToken}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await TemplateDbService.instance.deleteTemplateLocal(restaurantId, name);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}