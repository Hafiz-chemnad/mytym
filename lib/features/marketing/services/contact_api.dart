import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/crm_api_client.dart';
import 'crm_db.dart';
import 'label_api.dart';

class ContactApi {
  static final ContactApi instance = ContactApi._init();
  ContactApi._init();

  /// Pulls all contacts down from Mongo into local SQLite. Backend contacts
  /// carry label_ids; local storage still keeps label NAMES (unchanged,
  /// to not disturb runSmartCRMAutomation's name-based logic) — so each
  /// label_id is resolved to a name here, at the sync boundary, via the
  /// label lookup helpers added to crm_db.dart.
  ///
  /// IMPORTANT: this calls LabelApi.refreshLabels() itself first, rather
  /// than assuming LabelsTab has already populated the local labels table.
  /// marketing_screen.dart mounts all three tabs at once via IndexedStack,
  /// so ContactsTab and LabelsTab's initState() run with no ordering
  /// guarantee — without this, a fresh install or a lucky race could hit
  /// an empty local labels table and silently drop every label from every
  /// contact for that load cycle.
  Future<void> refreshContacts(String restaurantId) async {
    try {
      await LabelApi.instance.refreshLabels(restaurantId);

      int currentPage = 1;
      int totalPages = 1;

      while (currentPage <= totalPages) {
        final url = Uri.parse(
          '${CrmApiClient.baseUrl}/api/$restaurantId/contacts?limit=50&page=$currentPage',
        );
        final response = await http.get(url);
        if (response.statusCode != 200) break;

        final decoded = jsonDecode(response.body);
        final List<dynamic> items = decoded['items'] ?? [];
        totalPages = int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;

        for (var item in items) {
          final List<dynamic> labelIds = item['label_ids'] ?? [];
          final List<String> labelNames = [];
          for (var id in labelIds) {
            final name = await CrmDbService.instance.getLabelNameById(restaurantId, id.toString());
            if (name != null) labelNames.add(name);
          }

          await CrmDbService.instance.upsertContact(restaurantId, {
            'phone': item['phone'],
            'name': item['name'],
            'status': item['status'] ?? 'Active',
            'labels': labelNames,
            'source': item['source'],         // 🚀 ADD THIS
            'created_at': item['created_at'],
          });
        }
        currentPage++;
      }
    } catch (e) {
      // Offline / backend down — local cache is used as-is.
    }
  }

  /// Add a single contact. Returns 'ok' or 'error'. Note: this does NOT
  /// distinguish a brand-new phone from a re-add of an existing one — the
  /// backend enriches (fills in a real name) silently either way, and the
  /// UI shows the same "Contact added successfully!" message for both.
  /// If you later want the UI to say "this number already existed", the
  /// backend would need to signal that explicitly (e.g. whether it found
  /// an existing doc before the enrichment upsert) — it doesn't today.
  Future<String> addContact(String restaurantId, String name, String phone,{String source = 'manual'}) async {
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/contacts'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"phone": phone, "name": name, "status": "Active","source": source}),
      );
      if (response.statusCode == 200) {
        final saved = jsonDecode(response.body);
        await CrmDbService.instance.upsertContact(restaurantId, {
          'phone': saved['phone'],
          'name': saved['name'],
          'status': saved['status'] ?? 'Active',
          'labels': <String>[], 
          'source': saved['source'],           // 🚀 ADD THIS (the accuracy fix from before)
          'created_at': saved['created_at'], // fresh add always starts with no labels
        });
        return 'ok';
      }
      return 'error';
    } catch (e) {
      return 'error';
    }
  }

  /// Bulk CSV import. `rows` is a list of {name, phone} maps already parsed
  /// from the CSV by contacts_tab.dart. Returns the backend's counts
  /// directly — these are now authoritative (checked against live Mongo
  /// state), replacing the old local in-memory duplicate check. Follows up
  /// with a refreshContacts() so the newly-added rows show up locally.
  Future<Map<String, int>> bulkImport(String restaurantId, List<Map<String, String>> rows) async {
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/contacts/bulk'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"rows": rows}),
      );
      if (response.statusCode != 200) {
        return {'added': 0, 'enriched': 0, 'duplicate': 0, 'invalid': rows.length};
      }
      final result = jsonDecode(response.body);
      await refreshContacts(restaurantId);
      return {
        'added': result['added'] ?? 0,
        'enriched': result['enriched'] ?? 0,
        'duplicate': result['duplicate'] ?? 0,
        'invalid': result['invalid'] ?? 0,
      };
    } catch (e) {
      return {'added': 0, 'enriched': 0, 'duplicate': 0, 'invalid': rows.length};
    }
  }

  /// Full-replace a contact's labels. Takes the desired NAME list (what the
  /// UI works with), resolves each to a label_id locally, and sends the
  /// id list to the backend. Names with no known label_id (shouldn't
  /// normally happen since labels are created before being applied) are
  /// dropped rather than sent as garbage ids.
  Future<bool> updateContactLabels(String restaurantId, String phone, List<String> labelNames) async {
    try {
      final List<String> labelIds = [];
      for (var name in labelNames) {
        final id = await CrmDbService.instance.getLabelIdByName(restaurantId, name);
        if (id != null) labelIds.add(id);
      }

      final response = await http.put(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/contacts/$phone/labels'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"label_ids": labelIds}),
      );
      if (response.statusCode == 200) {
        // Labels-only local write — does NOT touch name/status, so a
        // contact's real name is never overwritten by a label change.
        await CrmDbService.instance.updateLocalContactLabels(restaurantId, phone, labelNames);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  // 🚀 NEW: Update Contact Status
  Future<bool> updateContactStatus(String restaurantId, String phone, String name, String newStatus) async {
    try {
      final response = await http.post(
        Uri.parse('${CrmApiClient.baseUrl}/api/$restaurantId/contacts'),
        headers: CrmApiClient.defaultHeaders,
        body: jsonEncode({"phone": phone, "name": name, "status": newStatus}),
      );
      if (response.statusCode == 200) {
        // Instantly update SQLite so the UI feels fast
        await CrmDbService.instance.updateLocalContactStatus(restaurantId, phone, newStatus);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}