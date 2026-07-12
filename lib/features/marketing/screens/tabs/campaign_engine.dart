import 'package:flutter/foundation.dart';
import '../../services/crm_api.dart';
import '../../services/campaign_api.dart';
import '../../services/crm_db.dart';

class CampaignEngine extends ChangeNotifier {
  static final CampaignEngine instance = CampaignEngine._init();
  CampaignEngine._init();

  final Map<String, bool> _activeLoops = {};

  bool isRunning(String campaignId) => _activeLoops[campaignId] ?? false;

  void stopCampaign(String campaignId) {
    _activeLoops[campaignId] = false;
    notifyListeners(); // Tells the UI to change the Stop button back to Play
  }

  Future<void> startBackgroundLoop({
    required String restaurantId,
    required String campaignId,
    required List<String> targetPhones,
    required List<Map<String, dynamic>> activeContacts,
    required String templateName,
    required Map<String, dynamic> templateData,
    required Map<int, Map<String, dynamic>> variableMappings,
    required String phoneNumberId,
    required String waToken,
    String? mediaUrl,
    String? mediaId,
    String? buttonUrlParam,
  }) async {
    // 1. Mark as running and wake up the UI table
    _activeLoops[campaignId] = true;
    notifyListeners(); 

    int consecutiveErrors = 0;
    Map<String, String> phoneToNameMap = {};
    for (var c in activeContacts) {
      phoneToNameMap[c['phone'].toString()] = c['name']?.toString() ?? '';
    }

    int vCount = templateData['variable_count'] ?? 0;

    // 2. THE BACKGROUND LOOP
    for (String phone in targetPhones) {
      // 🛑 If the user clicked STOP on the table, break the loop!
      if (_activeLoops[campaignId] != true) break; 

      String rawName = phoneToNameMap[phone] ?? phone;
      String finalName = (rawName.isEmpty || rawName == phone || rawName == 'WhatsApp User') ? 'there' : rawName.split(' ').first;

      List<String> paramsList = [];
      for(int i = 1; i <= vCount; i++) {
        var rule = variableMappings[i];
        if (rule?['type'] == 'name') {
          paramsList.add(finalName);
        } else if (rule?['type'] == 'phone') {
          paramsList.add(phone);
        } else {
          paramsList.add(rule?['value']?.toString() ?? '');
        }
      }

      String currentLang = templateData['language']?.toString() ?? 'en_US';

      String? wamid = await CrmApi.instance.sendMediaTemplateBypass(
        restaurantId: restaurantId,
        phoneNumberId: phoneNumberId,
        accessToken: waToken,
        customerNumber: phone,
        templateName: templateName,
        languageCode: currentLang,
        templateParams: paramsList,
        headerType: templateData['header_type'] ?? 'NONE',
        mediaUrl: mediaUrl,
        mediaId: mediaId,
        buttonUrlParam: buttonUrlParam,
      );

      bool success = wamid != null;

      final progress = await CampaignApi.instance.reportProgress(
        restaurantId: restaurantId,
        campaignId: campaignId,
        phone: phone,
        outcome: success ? "pending" : "failed",
        wamid: wamid,
      );

      if (progress != null) {
        consecutiveErrors = 0;
        // 🚀 LIVE UI UPDATE: Save the new counts to SQLite, then tell the table to redraw!
        await CrmDbService.instance.upsertCampaign(restaurantId, progress);
        notifyListeners(); 
      } else {
        consecutiveErrors++;
        if (consecutiveErrors >= 3) {
          _activeLoops[campaignId] = false;
          break; // Network dropped, kill the loop safely!
        }
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    // 3. CLEANUP WHEN FINISHED OR STOPPED
    if (_activeLoops[campaignId] == false) {
      await CampaignApi.instance.cancelCampaign(restaurantId, campaignId);
    }

    _activeLoops.remove(campaignId);
    
    // Fetch final state from Python to ensure perfection
    try {
       final finalData = await CampaignApi.instance.getCampaignDetails(restaurantId, campaignId);
       if (finalData != null) await CrmDbService.instance.upsertCampaign(restaurantId, finalData);
    } catch(e){}
    
    notifyListeners(); 
  }
}