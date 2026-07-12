import 'package:flutter/material.dart';
import 'package:whatsapp_erp/features/marketing/screens/tabs/campaign_details_dialog.dart';
import 'package:whatsapp_erp/features/settings/services/settings_db_service.dart';
import '../../services/crm_api.dart';
import '../../services/crm_db.dart';
import '../../services/campaign_api.dart';
import '../../services/template_db.dart'; // 🚀 ADDED
import 'package:file_picker/file_picker.dart'; // 🚀 ADDED THIS


class CampaignsTab extends StatefulWidget {
  final String restaurantId;
  const CampaignsTab({super.key, required this.restaurantId});

  @override
  State<CampaignsTab> createState() => CampaignsTabState();
}

class CampaignsTabState extends State<CampaignsTab> {
  bool _isLoading = false;

  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _allContacts = [];
  List<Map<String, dynamic>> _labels = [];
  List<Map<String, dynamic>> _approvedTemplates = []; // 🚀 ADDED

  final Color primaryTeal = const Color(0xFF096A56);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);
  final Color successBg = const Color(0xFFE6F4EA);
  final Color successText = const Color(0xFF14804A);

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    await CrmDbService.instance.cleanupOrphanedLabels(widget.restaurantId);
    final cachedCampaigns = await CrmDbService.instance.getAllCampaigns(widget.restaurantId);
    final cachedContacts = await CrmDbService.instance.getAllContacts(widget.restaurantId);
    final cachedLabels = await CrmDbService.instance.getAllLabels(widget.restaurantId);
    final cachedTemplates = await TemplateDbService.instance.getApprovedTemplates(widget.restaurantId); // 🚀 ADDED

    if (mounted) {
      setState(() {
        _campaigns = cachedCampaigns;
        _allContacts = cachedContacts;
        _labels = cachedLabels;
        _approvedTemplates = cachedTemplates; // 🚀 ADDED
        _isLoading = false;
      });
    }

    try {
      await CampaignApi.instance.refreshCampaigns(widget.restaurantId);
      final freshCampaigns = await CrmDbService.instance.getAllCampaigns(widget.restaurantId);
      if (mounted) setState(() => _campaigns = freshCampaigns);
    } catch (e) {
      // offline/backend down
    }
  }

  Future<void> _reloadFromCache() async {
    final campaigns = await CrmDbService.instance.getAllCampaigns(widget.restaurantId);
    if (mounted) setState(() => _campaigns = campaigns);
  }

  void _confirmDeleteCampaign(Map<String, dynamic> camp) {
    if (camp['status'] == 'sending') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This campaign is still sending — it can't be deleted right now.")));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Campaign?"),
        content: Text("Remove '${camp['name']}' from your campaign history? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final result = await CampaignApi.instance.deleteCampaign(widget.restaurantId, camp['id'].toString());
              if (mounted) Navigator.pop(ctx);
              if (result == 'forbidden') {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This campaign is still sending — cancel it first.")));
                return;
              }
              if (result == 'error') {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete — check connection.")));
                return;
              }
              await _reloadFromCache();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

 void _showCreateCampaignDialog({

    
    String? resumeCampaignId, 
    String? resumeName, 
    String? resumeTemplate, 
    List<String>? pendingPhones
  }) {
    TextEditingController nameCtrl = TextEditingController();
    
    // 🚀 NEW STATE VARIABLES FOR MEDIA HANDLING
    TextEditingController mediaUrlCtrl = TextEditingController(); 
    String? selectedMediaUrl; 
    PlatformFile? selectedMediaFile;
    String? selectedTemplateName;
    Map<String, dynamic>? selectedTemplateData;
    Map<int, Map<String, dynamic>> variableMappings = {};
    TextEditingController buttonUrlParamCtrl = TextEditingController(); // 🚀 ADDED

    bool isSending = false;
    bool isCancelled = false;
    int sentCount = 0;
    int failCount = 0;
    String? activeCampaignId;

    String selectedAudienceType = 'All';
    String? selectedLabelName;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<Map<String, dynamic>> activeContacts = _allContacts.where((c) => (c['status']?.toString() ?? 'Active') == 'Active').toList();

            List<String> targetPhones = [];
            if (selectedAudienceType == 'All') {
              targetPhones = activeContacts.map((c) => c['phone'].toString()).toList();
            } else if (selectedAudienceType == 'Label' && selectedLabelName != null) {
              targetPhones = activeContacts.where((c) {
                List<String> lbls = (c['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                return lbls.contains(selectedLabelName);
              }).map((c) => c['phone'].toString()).toList();
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 950, height: 650, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Create New Campaign", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 4), Text("Configure your template and audience.", style: TextStyle(fontSize: 13, color: textMuted))]),
                          if (!isSending) IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cardBorder),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Campaign Details", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 16),
                                  TextField(controller: nameCtrl, enabled: !isSending, decoration: InputDecoration(labelText: "Campaign Name (e.g., Summer Sale)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)))),
                                  
                                  const SizedBox(height: 24),
                                  Text("Meta Template", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 16),
                                  
                                  DropdownButtonFormField<String>(
                                    value: selectedTemplateName,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)),
                                      prefixIcon: const Icon(Icons.forum_outlined),
                                    ),
                                    hint: _approvedTemplates.isEmpty ? const Text("No approved templates found") : const Text("Select a template..."),
                                    items: _approvedTemplates.map((t) {
                                      return DropdownMenuItem<String>(
                                        value: t['name'].toString(),
                                        child: Text("${t['name']}  [${t['category']}]", style: const TextStyle(fontWeight: FontWeight.w500)),
                                      );
                                    }).toList(),
                                    onChanged: isSending || _approvedTemplates.isEmpty ? null : (val) {
                                      setModalState(() {
                                        selectedTemplateName = val;
                                        selectedTemplateData = _approvedTemplates.firstWhere((t) => t['name'] == val);
                                        
                                        // Reset media tracking on template change
                                        mediaUrlCtrl.clear();
                                        selectedMediaUrl = null;
                                        buttonUrlParamCtrl.clear();

                                        // Initialize the variables from defaults
                                        int vCount = selectedTemplateData?['variable_count'] ?? 0;
                                        Map<String, dynamic> defaults = selectedTemplateData?['default_mappings'] ?? {};
                                        variableMappings.clear();
                                        
                                        for (int i = 1; i <= vCount; i++) {
                                          variableMappings[i] = defaults[i.toString()] != null 
                                            ? Map<String, dynamic>.from(defaults[i.toString()]) 
                                            : {'type': 'custom', 'value': ''};
                                        }
                                      });
                                    },
                                  ),

                                  if (selectedTemplateData != null && selectedTemplateData!['category'] != 'MARKETING')
                                    Container(
                                      margin: const EdgeInsets.only(top: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text("This is a ${selectedTemplateData!['category']} template. Meta expects these to relate to a specific user transaction. Mass broadcasting these carries a risk of account restrictions.", style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.w500))),
                                        ],
                                      ),
                                    ),

                                  // 🚀 THE HYBRID MEDIA UI (URL + File Picker)
                                  if (selectedTemplateData != null && 
                                      ['IMAGE', 'VIDEO', 'DOCUMENT'].contains(selectedTemplateData!['header_type'])) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Media Asset Required (${selectedTemplateData!['header_type']})", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                          const SizedBox(height: 12),
                                          
                                          // OPTION 1: Paste URL
                                          TextFormField(
                                            controller: mediaUrlCtrl,
                                            enabled: !isSending && selectedMediaFile == null, // Disable if they picked a file
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: selectedMediaFile != null ? Colors.grey.shade200 : Colors.white,
                                              labelText: "Option A: Paste Public URL",
                                              hintText: "https://yourrestaurant.com/file.png",
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              prefixIcon: const Icon(Icons.link_rounded),
                                            ),
                                            onChanged: (val) => setModalState(() => selectedMediaUrl = val.trim()),
                                          ),
                                          
                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 12),
                                            child: Center(child: Text("— OR —", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                                          ),

                                          // OPTION 2: Upload File
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(backgroundColor: selectedMediaFile != null ? Colors.green.shade600 : Colors.blue.shade600, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16)),
                                              onPressed: isSending ? null : () async {
                                                if (selectedMediaFile != null) {
                                                  // Allow them to clear the file
                                                  setModalState(() => selectedMediaFile = null);
                                                  return;
                                                }
                                                FilePickerResult? result = await FilePicker.platform.pickFiles(
                                                  withData: true,
                                                  type: FileType.any,
                                                );
                                                if (result != null && result.files.single.bytes != null) {
                                                  setModalState(() {
                                                    selectedMediaFile = result.files.single;
                                                    mediaUrlCtrl.clear(); // Clear text if they pick a file
                                                    selectedMediaUrl = null;
                                                  });
                                                }
                                              },
                                              icon: Icon(selectedMediaFile != null ? Icons.close : Icons.upload_file),
                                              label: Text(selectedMediaFile != null ? "Clear File Selection" : "Option B: Upload File from Device"),
                                            ),
                                          ),
                                          if (selectedMediaFile != null) ...[
                                            const SizedBox(height: 12),
                                            Text("✅ Selected: ${selectedMediaFile!.name}", style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                                            Text("Size: ${(selectedMediaFile!.size / 1024 / 1024).toStringAsFixed(2)} MB", style: TextStyle(color: Colors.green.shade900, fontSize: 12)),
                                          ]
                                        ]
                                      )
                                    )
                                  ],

                                  if (selectedTemplateData != null && (selectedTemplateData!['variable_count'] ?? 0) > 0) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(8)),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Template Variables", style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal, fontSize: 13)),
                                          const SizedBox(height: 12),
                                          ...List.generate(selectedTemplateData!['variable_count'], (index) {
                                            int vIndex = index + 1;
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 12),
                                              child: Row(
                                                children: [
                                                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(6)), child: Text("{{$vIndex}}", style: TextStyle(fontWeight: FontWeight.bold, color: textMuted))),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    flex: 2,
                                                    child: DropdownButtonFormField<String>(
                                                      isExpanded: true, 
                                                      isDense: true,
                                                      decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                                      value: variableMappings[vIndex]?['type'] ?? 'custom',
                                                      items: const [
                                                        DropdownMenuItem(value: 'name', child: Text("Contact's First Name", overflow: TextOverflow.ellipsis)),
                                                        DropdownMenuItem(value: 'phone', child: Text("Contact's Phone", overflow: TextOverflow.ellipsis)),
                                                        DropdownMenuItem(value: 'custom', child: Text("Custom Fixed Text", overflow: TextOverflow.ellipsis)),
                                                      ],
                                                      onChanged: isSending ? null : (val) => setModalState(() => variableMappings[vIndex]?['type'] = val),
                                                    ),
                                                  ),
                                                  if (variableMappings[vIndex]?['type'] == 'custom') ...[
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      flex: 3,
                                                      child: TextFormField(
                                                        initialValue: variableMappings[vIndex]?['value']?.toString() ?? '',
                                                        enabled: !isSending,
                                                        decoration: InputDecoration(hintText: "Type value...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                                        onChanged: (val) => variableMappings[vIndex]?['value'] = val,
                                                      ),
                                                    ),
                                                  ]
                                                ],
                                              ),
                                            );
                                          })
                                        ],
                                      ),
                                    )
                                  ],
                                  if (selectedTemplateData != null &&
    (selectedTemplateData!['buttons'] as List?)?.any((b) =>
      b['type'] == 'URL' && (b['url']?.toString().contains('{{1}}') ?? false)) == true) ...[
  const SizedBox(height: 16),
  Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.purple.shade50, border: Border.all(color: Colors.purple.shade200), borderRadius: BorderRadius.circular(8)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Dynamic Button Link Value", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
        const SizedBox(height: 8),
        TextFormField(
          controller: buttonUrlParamCtrl,
          enabled: !isSending,
          decoration: InputDecoration(
            labelText: "Value for {{1}} in button URL",
            hintText: "e.g. order-12345",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    ),
  ),
],

                                  const SizedBox(height: 24),
                                  Text("Target Audience", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder), color: const Color(0xFFF8FAFC)),
                                    child: pendingPhones != null 
                                      ? Row(
                                          children: [
                                            const Icon(Icons.play_circle_fill, color: Colors.orange),
                                            const SizedBox(width: 8),
                                            Text("Resuming Campaign: ${pendingPhones.length} pending contacts", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800, fontSize: 14)),
                                          ],
                                        )
                                      : Column(
                                      children: [
                                        RadioListTile<String>(title: Text("All Active Contacts (${activeContacts.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), value: 'All', groupValue: selectedAudienceType, activeColor: primaryTeal, onChanged: isSending ? null : (val) => setModalState(() => selectedAudienceType = val!)),
                                        if (_labels.isNotEmpty) RadioListTile<String>(title: const Text("By Specific Label", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), value: 'Label', groupValue: selectedAudienceType, activeColor: primaryTeal, onChanged: isSending ? null : (val) { setModalState(() { selectedAudienceType = val!; selectedLabelName = _labels.first['name']; }); }),
                                        if (selectedAudienceType == 'Label')
                                          Padding(
                                            padding: const EdgeInsets.only(left: 48, right: 16, bottom: 8),
                                            child: DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()), value: selectedLabelName,
                                              items: _labels.map((l) => DropdownMenuItem<String>(value: l['name'], child: Text("${l['name']} (${l['count']} contacts)", style: const TextStyle(fontSize: 12)))).toList(),
                                              onChanged: isSending ? null : (val) => setModalState(() => selectedLabelName = val),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Total Recipients for this campaign: ${targetPhones.length}", style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)),
                                  if (isSending) ...[
                                    const SizedBox(height: 16),
                                    LinearProgressIndicator(
                                      value: targetPhones.isEmpty ? 0 : (sentCount + failCount) / targetPhones.length,
                                      backgroundColor: cardBorder,
                                      color: primaryTeal,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Sent: $sentCount   Failed: $failCount   Remaining: ${targetPhones.length - sentCount - failCount}",
                                      style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Container(width: 1, color: cardBorder),
                          Expanded(
                            flex: 4,
                            child: Container(
                              color: const Color(0xFFF3F4F6),
                              child: Center(
                                child: Container(
                                  width: 320, height: 450, decoration: BoxDecoration(color: const Color(0xFFE5DDD5), borderRadius: BorderRadius.circular(16), image: const DecorationImage(image: NetworkImage("https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png"), fit: BoxFit.cover, opacity: 0.4)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // 🚀 NEW SMART PREVIEW HEADER
                                              if (selectedTemplateData != null && selectedTemplateData!['header_type'] != null && selectedTemplateData!['header_type'] != 'NONE') ...[
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade200,
                                                    borderRadius: const BorderRadius.only(topRight: Radius.circular(12)),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        selectedTemplateData!['header_type'] == 'TEXT' ? Icons.title : Icons.perm_media_outlined, 
                                                        size: 16, color: textMuted
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          selectedTemplateData!['header_type'] == 'TEXT' 
                                                              ? (selectedTemplateData!['header_text'] ?? 'Header Title')
                                                              : "[ Attached ${selectedTemplateData!['header_type']} Document ]",
                                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textDark),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Divider(height: 1, color: Colors.grey.shade300),
                                              ],
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(selectedTemplateName == null ? "Select a template..." : "Template Preview:", style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600)),
                                                    const SizedBox(height: 4),
                                                    Text(selectedTemplateData != null ? selectedTemplateData!['body_text']?.toString() ?? '' : "...", style: TextStyle(fontSize: 14, color: textDark)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cardBorder),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!isSending) TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold))),
                          if (isSending)
                            TextButton(
                              onPressed: isCancelled ? null : () {
                                      setModalState(() => isCancelled = true);
                                      if (activeCampaignId != null) {
                                        // ignore: unawaited_futures
                                        CampaignApi.instance.cancelCampaign(widget.restaurantId, activeCampaignId!);
                                      }
                                    },
                              child: Text(isCancelled ? "Stopping..." : "Stop", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: isSending || targetPhones.isEmpty || selectedTemplateName == null
                                ? null
                                : () async {
                                    if (nameCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Campaign Name is required!")));
                                      return;
                                    }

                                   // 🚀 Ensure AT LEAST ONE media source is provided
                                    bool requiresMedia = ['IMAGE', 'VIDEO', 'DOCUMENT'].contains(selectedTemplateData!['header_type']);
                                    if (requiresMedia && selectedMediaFile == null && mediaUrlCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide either a Media URL OR select a file!")));
                                      return;
                                    }

                                    setModalState(() { isSending = true; }); 

                                    // Fetch fresh credentials from SQLite BEFORE uploading
                                    final settings = await SettingsDbService.instance.getSettings();
                                    final activePhoneNumberId = settings?['phoneNumberId']?.toString() ?? '';
                                    final activeWaToken = settings?['waToken']?.toString() ?? '';

                                    if (activePhoneNumberId.isEmpty || activeWaToken.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Missing Meta Credentials in Settings!")));
                                        setModalState(() { isSending = false; });
                                        return;
                                    }

                                    // 🚀 BULLETPROOF UPLOAD LOGIC
                                    String? finalMediaId;
                                    String? finalMediaUrl = mediaUrlCtrl.text.trim(); // Force read the text box directly!

                                    if (finalMediaUrl.isEmpty) {
                                      finalMediaUrl = null;
                                    }

                                    if (selectedMediaFile != null) {
                                      // If they picked a file, upload it!
                                      finalMediaId = await CrmApi.instance.uploadMediaToBackend(
                                        restaurantId: widget.restaurantId,
                                        phoneNumberId: activePhoneNumberId,
                                        accessToken: activeWaToken, // Will use path if Desktop/Web allows
                                        fileBytes: selectedMediaFile!.bytes!, // Fallback
                                        fileName: selectedMediaFile!.name,
                                      );

                                      if (finalMediaId == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to upload media to Meta. Check file format/size.")));
                                        setModalState(() { isSending = false; });
                                        return;
                                      }
                                      
                                      // 🚀 THE FIX: Wait 3 seconds to let Meta's antivirus scan the uploaded file!
                                      await Future.delayed(const Duration(seconds: 3));
                                      
                                      // Clear URL just in case, because we are using the secure ID
                                      finalMediaUrl = null; 
                                    } 

                                    // Save Variables
                                    Map<String, dynamic> mapToSave = {};
                                    variableMappings.forEach((k, v) => mapToSave[k.toString()] = v);
                                    await TemplateDbService.instance.updateVariableMapping(widget.restaurantId, selectedTemplateName!, mapToSave);
                                    // 🚀 ADD THIS: Push the mapping to the cloud so it saves forever!
// 🚀 STEP 3C: USE PENDING PHONES IF RESUMING
                                    List<String> finalTargets = pendingPhones ?? targetPhones;
                                    String? currentCampaignId = resumeCampaignId;

                                    if (resumeCampaignId == null) {
                                      // 1. START A BRAND NEW CAMPAIGN
                                      String? labelId;
                                      if (selectedAudienceType == 'Label' && selectedLabelName != null) {
                                        labelId = await CrmDbService.instance.getLabelIdByName(widget.restaurantId, selectedLabelName!);
                                      }
                                      currentCampaignId = await CampaignApi.instance.startCampaign(
                                        restaurantId: widget.restaurantId,
                                        name: nameCtrl.text.trim(),
                                        templateName: selectedTemplateName!,
                                        audienceType: selectedAudienceType,
                                        labelId: labelId,
                                        recipientPhones: finalTargets,
                                      );
                                    } else {
                                      // 2. TELL BACKEND WE ARE RESUMING THE OLD ONE
                                      await CampaignApi.instance.setCampaignResuming(widget.restaurantId, resumeCampaignId);
                                    }

                                    if (currentCampaignId == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't start/resume campaign — check your connection.")));
                                      setModalState(() { isSending = false; });
                                      return;
                                    }

                                    setModalState(() { sentCount = 0; failCount = 0; activeCampaignId = currentCampaignId; });

                                    Map<String, String> phoneToNameMap = {};
                                    for (var c in activeContacts) {
                                      phoneToNameMap[c['phone'].toString()] = c['name']?.toString() ?? '';
                                    }

                                    int vCount = selectedTemplateData?['variable_count'] ?? 0;
                                    
                                    // 🚀 THE NETWORK SAFETY SWITCH (Stop if wifi drops)
                                    int consecutiveErrors = 0;

                                    // 🚀 SENDING LOOP (Now uses finalTargets!)
                                    for (String phone in finalTargets) {
                                      if (isCancelled) break;

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

                                      String currentLang = selectedTemplateData!['language']?.toString() ?? 'en_US';

                                      String? wamid = await CrmApi.instance.sendMediaTemplateBypass(
                                        restaurantId: widget.restaurantId,
                                        phoneNumberId: activePhoneNumberId, 
                                        accessToken: activeWaToken,
                                        customerNumber: phone,
                                        templateName: selectedTemplateName!,
                                        languageCode: currentLang, 
                                        templateParams: paramsList,
                                        headerType: selectedTemplateData!['header_type'] ?? 'NONE',
                                        mediaUrl: finalMediaUrl,  
                                        mediaId: finalMediaId,   
                                        buttonUrlParam: buttonUrlParamCtrl.text.trim().isEmpty ? null : buttonUrlParamCtrl.text.trim(),
                                      );
                                      
                                      bool success = wamid != null;
                                      
                                      final progress = await CampaignApi.instance.reportProgress(
                                        restaurantId: widget.restaurantId,
                                        campaignId: currentCampaignId,
                                        phone: phone, 
                                        outcome: success ? "pending" : "failed",                                       
                                        wamid: wamid,
                                      );

                                      if (progress != null) {
                                        // Network is good! Reset error counter
                                        consecutiveErrors = 0;
                                        setModalState(() { sentCount = progress['sent_count'] ?? sentCount; failCount = progress['failed_count'] ?? failCount; });
                                      } else {
                                        // Network failed to reach Python backend!
                                        consecutiveErrors++;
                                        setModalState(() { if (success) sentCount++; else failCount++; });
                                        
                                        // 🚀 If 3 network failures in a row, kill the loop!
                                        if (consecutiveErrors >= 3) {
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Network lost! Campaign paused to prevent data loss."), backgroundColor: Colors.red));
                                          isCancelled = true;
                                          break; 
                                        }
                                      }

                                      await Future.delayed(const Duration(milliseconds: 250));
                                    }

                                    if (isCancelled && activeCampaignId != null) {
                                      await CampaignApi.instance.cancelCampaign(widget.restaurantId, activeCampaignId!);
                                    }

                                    if (mounted) {
                                      final messenger = ScaffoldMessenger.of(context);
                                      Navigator.pop(context);
                                      await loadData();
                                      if (isCancelled) {
                                        messenger.showSnackBar(SnackBar(content: Text("Campaign stopped. $sentCount sent, $failCount failed.", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.grey.shade700));
                                      } else if (failCount > 0) {
                                        messenger.showSnackBar(SnackBar(content: Text("Finished: $sentCount sent, $failCount failed.", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.orange));
                                      } else {
                                        messenger.showSnackBar(SnackBar(content: Text("Campaign '${nameCtrl.text}' completed perfectly! Sent to $sentCount users.", style: const TextStyle(color: Colors.white)), backgroundColor: primaryTeal));
                                      }
                                    }
                                  },
                            icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 16),
                            label: Text(isSending ? "Sending (${sentCount + failCount}/${targetPhones.length})..." : "Launch Campaign", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _statusDisplay(String? status) {
    switch (status) {
      case 'completed': return {'label': 'Completed', 'bg': successBg, 'text': successText};
      case 'partial': return {'label': 'Partial', 'bg': Colors.orange.shade50, 'text': Colors.orange.shade800};
      case 'failed': return {'label': 'Failed', 'bg': Colors.red.shade50, 'text': Colors.red};
      case 'cancelled': return {'label': 'Cancelled', 'bg': Colors.grey.shade200, 'text': Colors.grey.shade700};
      case 'sending': return {'label': 'Sending...', 'bg': Colors.blue.shade50, 'text': Colors.blue.shade800};
      default: return {'label': status ?? 'Pending', 'bg': Colors.grey.shade100, 'text': Colors.grey.shade700};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: primaryTeal));

    int totalDelivered = _campaigns.fold(0, (sum, c) => sum + (int.tryParse(c['sent_count']?.toString() ?? '0') ?? 0));
    int totalFailed = _campaigns.fold(0, (sum, c) => sum + (int.tryParse(c['failed_count']?.toString() ?? '0') ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSummaryCard("Total Campaigns", _campaigns.length.toString(), Icons.campaign_outlined)), const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Messages Delivered", totalDelivered.toString(), Icons.mark_chat_read_outlined, color: primaryTeal)), const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Failed Messages", totalFailed.toString(), Icons.error_outline, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [Icon(Icons.list_alt_rounded, color: textMuted, size: 20), const SizedBox(width: 8), Text("All Campaigns", style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 16))]),
                ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () => _showCreateCampaignDialog(), icon: const Icon(Icons.add, size: 18), label: const Text("Create Campaign", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_campaigns.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(60), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)), child: Column(children: [Icon(Icons.campaign_outlined, size: 50, color: cardBorder), const SizedBox(height: 16), Text("No campaigns yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark))]))
          else
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
              child: Column(
                children: [
                  // 🚀 THE TABLE HEADER (Matches your grey design)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC), // Light grey background
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text("No", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 3, child: Text("Campaigns", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text("Labels", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Recipients", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Sent", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Delivered", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Read", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Failed", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text("Actions", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  
                  // 🚀 THE TABLE ROWS
                  ListView.separated(
                    shrinkWrap: true, 
                    physics: const NeverScrollableScrollPhysics(), 
                    itemCount: _campaigns.length, 
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      var camp = _campaigns[index];
                      final display = _statusDisplay(camp['status']?.toString());
                      
                      // Format Date to look like "May 25, 6:09 AM"
                      String displayDate = 'Unknown date';
                      try {
                        DateTime? dt = DateTime.tryParse(camp['date']?.toString() ?? '');
                        if (dt != null) {
                          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          String month = months[dt.month - 1];
                          int hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
                          String amPm = dt.hour >= 12 ? 'PM' : 'AM';
                          String min = dt.minute.toString().padLeft(2, '0');
                          displayDate = "$month ${dt.day}, $hour:$min $amPm";
                        }
                      } catch (e) {}

                      // Safe Math for Percentages
                      int total = int.tryParse(camp['recipients']?.toString() ?? '0') ?? 0;
                      int sent = int.tryParse(camp['sent_count']?.toString() ?? '0') ?? 0;
                      int delivered = int.tryParse(camp['delivered_count']?.toString() ?? '0') ?? 0;
                      int read = int.tryParse(camp['read_count']?.toString() ?? '0') ?? 0;
                      int failed = int.tryParse(camp['failed_count']?.toString() ?? '0') ?? 0;

                      String sentPct = total > 0 ? (sent / total * 100).toStringAsFixed(0) : '0';
                      String delivPct = total > 0 ? (delivered / total * 100).toStringAsFixed(0) : '0';
                      String readPct = total > 0 ? (read / total * 100).toStringAsFixed(0) : '0';
                      String failPct = total > 0 ? (failed / total * 100).toStringAsFixed(0) : '0';

                      // Determine Label text & color
                      String displayLabel = 'All Contacts';
                      bool isCustomLabel = false;
                      if (camp['label_id'] != null) {
                        final found = _labels.where((l) => l['id'] == camp['label_id']).toList();
                        if (found.isNotEmpty) {
                          displayLabel = found.first['name'].toString();
                          isCustomLabel = true;
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Row(
                          children: [
                            SizedBox(width: 40, child: Text("${index + 1}", style: TextStyle(color: textMuted, fontSize: 13))),
                            
                            // 1. Name, Badge, Template, Date
                            Expanded(
                              flex: 3, 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, 
                                children: [
                                  Row(
                                    children: [
                                      Text(camp['name'] ?? 'Unnamed', style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 14)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: display['bg'], borderRadius: BorderRadius.circular(12)),
                                        child: Text(display['label'], style: TextStyle(color: display['text'], fontSize: 11, fontWeight: FontWeight.w600)),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(camp['template_name'] ?? '', style: TextStyle(fontSize: 13, color: textDark)),
                                  const SizedBox(height: 2),
                                  Text(displayDate, style: TextStyle(fontSize: 12, color: textMuted)),
                                ]
                              )
                            ),
                            
                            // 2. Purple Label Pill
                            Expanded(
                              flex: 2, 
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCustomLabel ? Colors.purple.shade50 : Colors.grey.shade100, 
                                    borderRadius: BorderRadius.circular(12)
                                  ),
                                  child: Text(
                                    displayLabel, 
                                    style: TextStyle(
                                      color: isCustomLabel ? Colors.purple.shade700 : Colors.grey.shade700, 
                                      fontSize: 12, 
                                      fontWeight: FontWeight.w500
                                    )
                                  ),
                                ),
                              )
                            ),
                            
                            // 3. Stats Columns formatted as "0% (0)"
                            Expanded(flex: 1, child: Text("$total", style: TextStyle(color: textDark, fontSize: 13))),
                            Expanded(flex: 1, child: Text("$sentPct% ($sent)", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 1, child: Text("$delivPct% ($delivered)", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 1, child: Text("$readPct% ($read)", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 1, child: Text("$failPct% ($failed)", style: TextStyle(color: Colors.red.shade400, fontSize: 13))),
                            
                            // 4. Square Outlined Actions
                            Expanded(
                              flex: 2,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 🚀 THE RESUME BUTTON
                                  if (camp['status'] == 'cancelled' || camp['status'] == 'partial') ...[
                                    Container(
                                      decoration: BoxDecoration(border: Border.all(color: Colors.orange.shade200), borderRadius: BorderRadius.circular(6), color: Colors.orange.shade50),
                                      child: IconButton(
                                        constraints: const BoxConstraints(), padding: const EdgeInsets.all(6),
                                        icon: Icon(Icons.play_arrow_rounded, color: Colors.orange.shade700, size: 18), 
                                        tooltip: "Resume Campaign",
                                        onPressed: () async {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fetching pending contacts...")));
                                          
                                          // 1. Fetch full details from Python
                                          final details = await CampaignApi.instance.getCampaignDetails(widget.restaurantId, camp['id'].toString());
                                          if (details == null) return;
                                          
                                          // 2. Filter for pending
                                          List<dynamic> recipients = details['recipients'] ?? [];
                                          List<String> pendingList = recipients
                                              .where((r) => r['status'] == 'pending')
                                              .map((r) => r['phone'].toString())
                                              .toList();
                                              
                                          if (pendingList.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No pending contacts left to send to!")));
                                            return;
                                          }

                                          // 3. Open Dialog pre-filled!
                                          _showCreateCampaignDialog(
                                            resumeCampaignId: camp['id'].toString(),
                                            resumeName: camp['name'],
                                            resumeTemplate: camp['template_name'],
                                            pendingPhones: pendingList,
                                          );
                                        }
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  // Eye Button
                                  Container(
                                    decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(6)),
                                    child: IconButton(
                                      constraints: const BoxConstraints(), padding: const EdgeInsets.all(6),
                                      icon: const Icon(Icons.remove_red_eye_outlined, color: Colors.black87, size: 18), 
                                      onPressed: () => showDialog(context: context, builder: (_) => CampaignDetailsDialog(restaurantId: widget.restaurantId, initialCampaign: camp))
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Download/Export Button
                                  Container(
                                    decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(6)),
                                    child: IconButton(
                                      constraints: const BoxConstraints(), padding: const EdgeInsets.all(6),
                                      icon: const Icon(Icons.download_outlined, color: Colors.black87, size: 18), 
                                      onPressed: () { 
                                        // TODO: Export CSV logic 
                                      }
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, {Color? color}) {
    Color effectiveColor = color ?? primaryTeal;
    return Container(
      padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(value, style: TextStyle(color: textDark, fontSize: 28, fontWeight: FontWeight.w900))]),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: effectiveColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: effectiveColor, size: 24)),
        ],
      ),
    );
  }
}