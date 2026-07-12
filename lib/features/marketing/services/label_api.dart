import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';
import 'crm_db.dart';

class LabelApi {
  static final LabelApi instance = LabelApi._init();
  LabelApi._init();

  /// On-demand refresh — pulls Mongo's label docs (the new source of truth
  /// for label_id/name/description/is_automated) down into local SQLite.
  /// Note: contact_count from the backend is NOT written locally here —
  /// local counts still come from the transitional name-based sweep
  /// (CrmDbService.recalculateLabelCounts) until the Contacts module also
  /// migrates to label_ids. Once that ships, this can take over counts too.
  Future<void> refreshLabels(String restaurantId) async {
    try {
      int currentPage = 1;
      int totalPages = 1;

      while (currentPage <= totalPages) {
        final url = Uri.parse(
          '${CrmApiClient.baseUrl}/api/$restaurantId/labels?limit=50&page=$currentPage',
        );
        final response = await http.get(url);
        if (response.statusCode != 200) break;

        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        totalPages = int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;

        for (var item in items) {
          await CrmDbService.instance.upsertLabel(restaurantId, {
            'id': item['label_id'] ?? item['id'],
            'name': item['name'],
            'description': item['description'],
            'is_automated': (item['is_automated'] == true) ? 1 : 0,
            // 'count' intentionally omitted — see note above
            'date': item['date'],
          });
        }
        currentPage++;
      }
    } catch (e) {
      // Offline / backend down — local cache is used as-is.
    }
  }

  Future<bool> createLabel(String restaurantId, String labelId, String name, String description) async {
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/labels'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({
          "label_id": labelId,
          "name": name,
          "description": description,
          "is_automated": false,
        }),
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await CrmDbService.instance.upsertLabel(restaurantId, {
          'id': saved['label_id'] ?? saved['id'],
          'name': saved['name'],
          'description': saved['description'],
          'is_automated': 0,
          'count': saved['count'] ?? 0,
          'date': saved['date'],
        });
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Returns 'ok', 'forbidden' (automated label), or 'error' — labels_tab.dart
  /// needs to distinguish these to show the right message.
  Future<String> updateLabel(String restaurantId, String labelId, String name, String description) async {
    try {
      final response = await http.put(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/labels/$labelId'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"name": name, "description": description}),
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await CrmDbService.instance.upsertLabel(restaurantId, {
          'id': saved['label_id'] ?? saved['id'],
          'name': saved['name'],
          'description': saved['description'],
          'is_automated': (saved['is_automated'] == true) ? 1 : 0,
          'count': saved['count'] ?? 0,
          'date': saved['date'],
        });
        return 'ok';
      }
      if (response.statusCode == 403) return 'forbidden';
      return 'error';
    } catch (e) {
      return 'error';
    }
  }

  Future<String> deleteLabel(String restaurantId, String labelId) async {
    try {
      final response = await http.delete(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/labels/$labelId'),
      );
      if (response.statusCode == 200) {
        await CrmDbService.instance.deleteLabel(restaurantId, labelId);
        return 'ok';
      }
      if (response.statusCode == 403) return 'forbidden';
      return 'error';
    } catch (e) {
      return 'error';
    }
  }
}