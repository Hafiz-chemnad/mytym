import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';
import 'crm_db.dart';

class CampaignApi {
  static final CampaignApi instance = CampaignApi._init();
  CampaignApi._init();

  /// 🚀 FIX: now accepts and sends mediaId/mediaUrl/buttonUrlParam so the
  /// backend can persist them on the campaign record — needed so a later
  /// Resume can reuse the original media instead of forcing a re-upload.
  Future<String?> startCampaign({
    required String restaurantId,
    required String name,
    required String templateName,
    required String audienceType,
    String? labelId,
    required List<String> recipientPhones,
    String? mediaId,
    String? mediaUrl,
    String? buttonUrlParam,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/campaigns'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({
          "name": name,
          "template_name": templateName,
          "audience_type": audienceType,
          "label_id": labelId,
          "recipients": recipientPhones.map((p) => {"phone": p}).toList(),
          "media_id": mediaId,
          "media_url": mediaUrl,
          "button_url_param": buttonUrlParam,
        }),
      );

      if (response.statusCode != 200) return null;

      final saved = jsonDecode(response.body);
      await CrmDbService.instance.upsertCampaign(restaurantId, saved);
      return saved['campaign_id']?.toString();
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> reportProgress({
    required String restaurantId,
    required String campaignId,
    required String phone,
    required String outcome,
    String? error,
    String? wamid,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/campaigns/$campaignId/progress'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({
          "phone": phone,
          "outcome": outcome,
          if (error != null) "error": error,
          "wamid": wamid,
        }),
      );

      if (response.statusCode != 200) return null;

      final saved = jsonDecode(response.body);
      await CrmDbService.instance.upsertCampaign(restaurantId, saved);
      return saved as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<bool> cancelCampaign(String restaurantId, String campaignId) async {
    try {
      final response = await http.patch(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/campaigns/$campaignId/cancel'),
        headers: CrmApiClient.defaultHeaders,
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await CrmDbService.instance.upsertCampaign(restaurantId, saved);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> refreshCampaigns(String restaurantId) async {
    try {
      int currentPage = 1;
      int totalPages = 1;

      while (currentPage <= totalPages) {
        final url = Uri.parse(
          '${CrmApiClient.baseUrl}/api/$restaurantId/campaigns?limit=50&page=$currentPage',
        );
        final response = await http.get(url);
        if (response.statusCode != 200) break;

        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        totalPages = int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;

        for (var item in items) {
          await CrmDbService.instance.upsertCampaign(restaurantId, item);
        }
        currentPage++;
      }
    } catch (e) {
      // Offline / backend down — local cache is used as-is.
    }
  }

  /// 🚀 FIX: getCampaignDetail() and getCampaignDetails() were two
  /// near-duplicate functions hitting the same endpoint. This is now the
  /// single source of truth — getCampaignDetail() delegates to it, kept
  /// only so existing call sites don't need to change.
  Future<Map<String, dynamic>?> getCampaignDetails(String restaurantId, String campaignId) async {
    try {
      final response = await http.get(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/campaigns/$campaignId'),
        headers: CrmApiClient.defaultHeaders,
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await CrmDbService.instance.upsertCampaign(restaurantId, saved);
        return saved as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCampaignDetail(String restaurantId, String campaignId) =>
      getCampaignDetails(restaurantId, campaignId);

  Future<String> deleteCampaign(String restaurantId, String campaignId) async {
    try {
      final response = await http.delete(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/campaigns/$campaignId'),
      );
      if (response.statusCode == 200) {
        await CrmDbService.instance.deleteCampaignLocal(restaurantId, campaignId);
        return 'ok';
      }
      if (response.statusCode == 403) return 'forbidden';
      return 'error';
    } catch (e) {
      return 'error';
    }
  }

  Future<bool> setCampaignResuming(String restaurantId, String campaignId) async {
    try {
      final response = await http.patch(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/campaigns/$campaignId/resume'),
        headers: CrmApiClient.defaultHeaders,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}