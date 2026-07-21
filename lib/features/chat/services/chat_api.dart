import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';
import '../../marketing/services/crm_db.dart';
import '../../marketing/services/contact_api.dart';
import 'chat_db.dart';

class ChatApi {
  static final ChatApi instance = ChatApi._init();
  ChatApi._init();

  // 🚀 Sync Guards to prevent SQLite File Locks
  static final Map<String, bool> _isSyncingMessages = {};
  static final Map<String, bool> _initialSyncDoneByRestaurant = {};
  static const int _maxInitialSyncPages = 3;   // 🚀 ADDED — cap cold-start sync depth

Future<List<dynamic>> fetchChatThread(
  String restaurantId,
  String customerNumber, {
  int page = 1,          // 🚀 ADDED — lets callers page backward through history
  int limit = 50,        // 🚀 CHANGED from hardcoded 500 — smaller, faster fetches
}) async {
  try {
    final url = Uri.parse('${ApiClient.baseUrl}/api/restaurant-messages/thread?restaurantId=$restaurantId&customerNumber=$customerNumber&limit=$limit&page=$page');
    final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body is Map) {
          return body['thread'] ?? body['data'] ?? body['messages'] ?? [];
        } else if (body is List) {
          return body;
        }
      }
    } catch (e) {
      print("Error fetching thread: $e");
    }
    return [];
  }

  Future<bool> sendMessage({
    required String to,
    required String text,
    required String restaurantId,
    required String phoneNumberId,
  }) async {
    try {
      final sendUrl = Uri.parse('${ApiClient.baseUrl}/api/sendTextMessage');
      final sendResponse = await http.post(
        sendUrl,
        headers: ApiClient.defaultHeaders,
        body: jsonEncode({
          "restaurantId": restaurantId,
          "customerNumber": to,
          "customerId": to,
          "phoneNumberId": phoneNumberId,
          "messageText": text,
        }),
      );

      if (sendResponse.statusCode == 200 || sendResponse.statusCode == 201) {
        try {
          final decoded = jsonDecode(sendResponse.body);
          if (decoded['success'] == false || decoded['status'] == 'failed' || decoded['error'] != null) {
            return false;
          }
        } catch (e) {
          // Response wasn't JSON, ignore
        }

        final storeUrl = Uri.parse('${ApiClient.baseUrl}/api/restaurant-messages/store');
        await http.post(
          storeUrl,
          headers: ApiClient.defaultHeaders,
          body: jsonEncode({
            "restaurantId": restaurantId,
            "customerNumber": to,
            "phoneNumberId": phoneNumberId,
            "messageType": "text",
            "messageContent": text,
            "customerId": to,
          }),
        );

        String tempId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
        
        // 🚀 Use the new Modular Chat DB Service
        await ChatDbService.instance.upsertMessage(restaurantId, {
          'id': tempId,
          'customerNumber': to,
          'direction': 'outbound',
          'isOutgoing': true,
          'messageType': 'text',
          'messageContent': {'text': {'body': text}},
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        });

        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ====================================================================
  // 🔄 BACKGROUND SYNC WORKER (MESSAGES)
  // ====================================================================
  Future<void> syncMessagesBackground(String restaurantId) async {
    if (_isSyncingMessages[restaurantId] == true) return;
    _isSyncingMessages[restaurantId] = true;

    try {
      int currentPage = 1;
      int totalPages = 1;

      do {
        final url = Uri.parse(
          '${ApiClient.baseUrl}/api/restaurant-messages/restaurant/$restaurantId?direction=inbound&limit=50&page=$currentPage',
        );

        final response = await http.get(url).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          print("❌ Message sync error on page $currentPage: ${response.statusCode}");
          break;
        }

        final dynamic decoded = jsonDecode(response.body);
        List<dynamic> msgs = [];
        if (decoded is Map) {
          msgs = decoded['messages'] ?? decoded['data'] ?? [];
          totalPages = int.tryParse(decoded['totalPages']?.toString() ?? '1') ?? 1;
        } else if (decoded is List) {
          msgs = decoded;
        }

for (var msg in msgs) {
  final content = msg['messageContent'] ?? msg['content'];
  final type = (msg['messageType']?.toString() ?? msg['type']?.toString() ?? '').toLowerCase();
  final String phone = msg['customerNumber']?.toString() ?? msg['customer_number']?.toString() ?? '';

  final blockedTypes = {'reaction', 'system', 'status', 'unsupported', 'unknown'};
  final isReactionContent = content is Map && content.containsKey('reaction');
  final hasRealContent = content != null && !(content is Map && content.isEmpty);

  if (phone.isEmpty || !hasRealContent || blockedTypes.contains(type) || isReactionContent) {
    continue; // skip malformed / no-customer / junk events
  }

  


          await ChatDbService.instance.upsertMessage(restaurantId, msg);

          // ✅ Register every customer into contacts
          
          if (phone.isNotEmpty) {
            final String inboundName = msg['customerName']?.toString() ?? '';
            final bool isNewContact = await CrmDbService.instance.upsertContactIfAbsent(restaurantId, {
              'phone': phone,
              'name': inboundName,
            });

            // Only push to the FastAPI/Mongo backend when this was an
            // actual new local insert — no point re-pushing a contact
            // that already exists both locally and remotely on every
            // 3-second poll cycle. Fire-and-forget (no await, own
            // try/catch inside ContactApi.addContact) so a slow or
            // offline backend can never stall message sync, which runs
            // this loop every 3 seconds for every active dashboard.
if (isNewContact) {
  // ignore: unawaited_futures
  ContactApi.instance.addContact(restaurantId, inboundName, phone, source: 'whatsapp');  // 🚀 CHANGED
}
          }
        }

        if (msgs.isNotEmpty) {
          print("📥 Message sync page $currentPage/$totalPages: ${msgs.length} messages.");
        }

        // Only paginate on first run; after DB is populated, page 1 is enough
// Only paginate on first run; after DB is populated, page 1 is enough.
        // 🚀 Cap the initial pull too — full history now loads lazily per-chat
        // via fetchChatThread() when the user scrolls up, not eagerly here.
        if (_initialSyncDoneByRestaurant[restaurantId] != true && currentPage < _maxInitialSyncPages) {
          currentPage++;
        } else {
          break;
        }
      } while (currentPage <= totalPages);

      _initialSyncDoneByRestaurant[restaurantId] = true;
    } catch (e) {
      print("❌ Message sync exception: $e");
    } finally {
      _isSyncingMessages[restaurantId] = false;
    }
    await CrmDbService.instance.backfillContactsFromMessages(restaurantId).then((newlyInserted) {
      // Fire-and-forget push for anything backfillContactsFromMessages
      // just discovered — same reasoning as the inline push above: don't
      // await, so a slow/offline backend can't stall this 3-second loop.
for (final phone in newlyInserted) {
  // ignore: unawaited_futures
  ContactApi.instance.addContact(restaurantId, '', phone, source: 'whatsapp');  // 🚀 CHANGED
}
    });
    _initialSyncDoneByRestaurant[restaurantId] = true;
  }
}