import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:whatsapp_erp/features/settings/services/settings_db_service.dart';
import '../../services/crm_api.dart';
import '../../services/crm_db.dart';
import '../../services/campaign_api.dart';
import '../../services/template_db.dart';
import 'campaign_engine.dart'; // Connects to your new Engine!
import '../../services/template_api.dart'; // 🚀 ADD THIS
import 'whatsapp_preview_widget.dart';

class CreateCampaignDialog extends StatefulWidget {
  final String restaurantId;
  final List<Map<String, dynamic>> allContacts;
  final List<Map<String, dynamic>> labels;
  final List<Map<String, dynamic>> approvedTemplates;
  
  final String? resumeCampaignId;
  final String? resumeName;
  final String? resumeTemplate;
  final List<String>? pendingPhones;

  const CreateCampaignDialog({
    super.key,
    required this.restaurantId,
    required this.allContacts,
    required this.labels,
    required this.approvedTemplates,
    this.resumeCampaignId,
    this.resumeName,
    this.resumeTemplate,
    this.pendingPhones,
  });

  @override
  State<CreateCampaignDialog> createState() => _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends State<CreateCampaignDialog> {
  late TextEditingController nameCtrl;
  TextEditingController mediaUrlCtrl = TextEditingController(); 
  TextEditingController buttonUrlParamCtrl = TextEditingController();

  String? selectedMediaUrl; 
  PlatformFile? selectedMediaFile;
  String? selectedTemplateName;
  Map<String, dynamic>? selectedTemplateData;
  Map<int, Map<String, dynamic>> variableMappings = {};

  bool isSending = false;
  String selectedAudienceType = 'All';
  String? selectedLabelName;

  final Color primaryTeal = const Color(0xFF096A56);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.resumeName ?? '');
    
    if (widget.resumeTemplate != null) {
      selectedTemplateName = widget.resumeTemplate;
      try {
        selectedTemplateData = widget.approvedTemplates.firstWhere((t) => t['name'] == widget.resumeTemplate);
        _initializeMappings();
      } catch (e) {}
    }
  }

  void _initializeMappings() {
    int vCount = selectedTemplateData?['variable_count'] ?? 0;
    Map<String, dynamic> defaults = selectedTemplateData?['default_mappings'] ?? {};
    variableMappings.clear();
    for (int i = 1; i <= vCount; i++) {
      variableMappings[i] = defaults[i.toString()] != null 
        ? Map<String, dynamic>.from(defaults[i.toString()]) 
        : {'type': 'custom', 'value': ''};
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> activeContacts = widget.allContacts.where((c) => (c['status']?.toString() ?? 'Active') == 'Active').toList();

    List<String> targetPhones = [];
    if (selectedAudienceType == 'All') {
      targetPhones = activeContacts.map((c) => c['phone'].toString()).toList();
    } else if (selectedAudienceType == 'Label' && selectedLabelName != null) {
      targetPhones = activeContacts.where((c) {
        List<String> lbls = (c['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        return lbls.contains(selectedLabelName);
      }).map((c) => c['phone'].toString()).toList();
    }
    
    List<String> finalTargets = widget.pendingPhones ?? targetPhones;

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
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.resumeCampaignId != null ? "Resume Campaign" : "Create New Campaign", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 4), Text("Configure your template and audience.", style: TextStyle(fontSize: 13, color: textMuted))]),
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
                          TextField(controller: nameCtrl, enabled: !isSending && widget.resumeCampaignId == null, decoration: InputDecoration(labelText: "Campaign Name (e.g., Summer Sale)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)))),
                          
                          const SizedBox(height: 24),
                          Text("Meta Template", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 16),
                          
                          DropdownButtonFormField<String>(
                            value: selectedTemplateName,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)),
                              prefixIcon: const Icon(Icons.forum_outlined),
                            ),
                            hint: widget.approvedTemplates.isEmpty ? const Text("No approved templates found") : const Text("Select a template..."),
                            items: widget.approvedTemplates.map((t) {
                              return DropdownMenuItem<String>(
                                value: t['name'].toString(),
                                child: Text("${t['name']}  [${t['category']}]", style: const TextStyle(fontWeight: FontWeight.w500)),
                              );
                            }).toList(),
                            onChanged: isSending || widget.approvedTemplates.isEmpty || widget.resumeCampaignId != null ? null : (val) {
                              setState(() {
                                selectedTemplateName = val;
                                selectedTemplateData = widget.approvedTemplates.firstWhere((t) => t['name'] == val);
                                mediaUrlCtrl.clear();
                                selectedMediaUrl = null;
                                buttonUrlParamCtrl.clear();
                                _initializeMappings();
                              });
                            },
                          ),

                          if (selectedTemplateData != null && ['IMAGE', 'VIDEO', 'DOCUMENT'].contains(selectedTemplateData!['header_type'])) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Media Asset Required (${selectedTemplateData!['header_type']})", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: mediaUrlCtrl,
                                    enabled: !isSending && selectedMediaFile == null,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: selectedMediaFile != null ? Colors.grey.shade200 : Colors.white,
                                      labelText: "Option A: Paste Public URL",
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      prefixIcon: const Icon(Icons.link_rounded),
                                    ),
                                    onChanged: (val) => setState(() => selectedMediaUrl = val.trim()),
                                  ),
                                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: Text("— OR —", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: selectedMediaFile != null ? Colors.green.shade600 : Colors.blue.shade600, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16)),
                                      onPressed: isSending ? null : () async {
                                        if (selectedMediaFile != null) {
                                          setState(() => selectedMediaFile = null);
                                          return;
                                        }
                                        FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
                                        if (result != null && result.files.single.bytes != null) {
                                          setState(() {
                                            selectedMediaFile = result.files.single;
                                            mediaUrlCtrl.clear();
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
                                              isExpanded: true, isDense: true,
                                              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                              value: variableMappings[vIndex]?['type'] ?? 'custom',
                                              items: const [
                                                DropdownMenuItem(value: 'name', child: Text("Contact's First Name")),
                                                DropdownMenuItem(value: 'phone', child: Text("Contact's Phone")),
                                                DropdownMenuItem(value: 'custom', child: Text("Custom Fixed Text")),
                                              ],
                                              onChanged: isSending ? null : (val) => setState(() => variableMappings[vIndex]?['type'] = val),
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

                          if (selectedTemplateData != null && (selectedTemplateData!['buttons'] as List?)?.any((b) => b['type'] == 'URL' && (b['url']?.toString().contains('{{1}}') ?? false)) == true) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.purple.shade50, border: Border.all(color: Colors.purple.shade200), borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Dynamic Button Link Value", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
                                  const SizedBox(height: 8),
                                  TextFormField(controller: buttonUrlParamCtrl, enabled: !isSending, decoration: InputDecoration(labelText: "Value for {{1}} in button URL", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),
                          Text("Target Audience", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)), const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder), color: const Color(0xFFF8FAFC)),
                            child: widget.pendingPhones != null 
                              ? Row(children: [const Icon(Icons.play_circle_fill, color: Colors.orange), const SizedBox(width: 8), Text("Resuming Campaign: ${widget.pendingPhones!.length} pending contacts", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800, fontSize: 14))])
                              : Column(
                                  children: [
                                    RadioListTile<String>(title: Text("All Active Contacts (${activeContacts.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), value: 'All', groupValue: selectedAudienceType, activeColor: primaryTeal, onChanged: isSending ? null : (val) => setState(() => selectedAudienceType = val!)),
                                    if (widget.labels.isNotEmpty) RadioListTile<String>(title: const Text("By Specific Label", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), value: 'Label', groupValue: selectedAudienceType, activeColor: primaryTeal, onChanged: isSending ? null : (val) { setState(() { selectedAudienceType = val!; selectedLabelName = widget.labels.first['name']; }); }),
                                    if (selectedAudienceType == 'Label')
                                      Padding(
                                        padding: const EdgeInsets.only(left: 48, right: 16, bottom: 8),
                                        child: DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()), value: selectedLabelName,
                                          items: widget.labels.map((l) => DropdownMenuItem<String>(value: l['name'], child: Text("${l['name']} (${l['count']} contacts)", style: const TextStyle(fontSize: 12)))).toList(),
                                          onChanged: isSending ? null : (val) => setState(() => selectedLabelName = val),
                                        ),
                                      ),
                                  ],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text("Total Recipients: ${finalTargets.length}", style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: cardBorder),
                  Expanded(
                    flex: 4,
                    child: WhatsappPreviewWidget(
                      templateData: selectedTemplateData,
                      variableMappings: variableMappings,
                      mediaUrl: mediaUrlCtrl.text,
                      mediaFile: selectedMediaFile,
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
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: isSending || finalTargets.isEmpty || selectedTemplateName == null
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Campaign Name is required!")));
                              return;
                            }

                            bool requiresMedia = ['IMAGE', 'VIDEO', 'DOCUMENT'].contains(selectedTemplateData!['header_type']);
                            if (requiresMedia && selectedMediaFile == null && mediaUrlCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide Media URL OR File!")));
                              return;
                            }

                            setState(() { isSending = true; }); 

                            final settings = await SettingsDbService.instance.getSettings();
                            final activePhoneNumberId = settings?['phoneNumberId']?.toString() ?? '';
                            final activeWaToken = settings?['waToken']?.toString() ?? '';

                            if (activePhoneNumberId.isEmpty || activeWaToken.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Missing Meta Credentials!")));
                                setState(() { isSending = false; });
                                return;
                            }

                            String? finalMediaId;
                            String? finalMediaUrl = mediaUrlCtrl.text.trim().isEmpty ? null : mediaUrlCtrl.text.trim();

                            if (selectedMediaFile != null) {
                              finalMediaId = await CrmApi.instance.uploadMediaToBackend(
                                restaurantId: widget.restaurantId, phoneNumberId: activePhoneNumberId, accessToken: activeWaToken, fileBytes: selectedMediaFile!.bytes!, fileName: selectedMediaFile!.name,
                              );
                              if (finalMediaId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to upload media.")));
                                setState(() { isSending = false; });
                                return;
                              }
                              await Future.delayed(const Duration(seconds: 3));
                              finalMediaUrl = null; 
                            } 

                            Map<String, dynamic> mapToSave = {};
                            variableMappings.forEach((k, v) => mapToSave[k.toString()] = v);
                            await TemplateDbService.instance.updateVariableMapping(widget.restaurantId, selectedTemplateName!, mapToSave);
                            await TemplateApi.instance.saveVariableMapping(widget.restaurantId, selectedTemplateName!, mapToSave);

                            String? currentCampaignId = widget.resumeCampaignId;

if (widget.resumeCampaignId == null) {
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
                                // 🚀 ADD THESE 3 LINES: Pass the media to Python!
                                mediaId: finalMediaId,
                                mediaUrl: finalMediaUrl,
                                buttonUrlParam: buttonUrlParamCtrl.text.trim().isEmpty ? null : buttonUrlParamCtrl.text.trim(),
                              );
                            } else {
                              await CampaignApi.instance.setCampaignResuming(widget.restaurantId, widget.resumeCampaignId!);
                            }

                            if (currentCampaignId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't start campaign — check connection.")));
                              setState(() { isSending = false; });
                              return;
                            }

                            // 🚀 THE MAGIC: START THE BACKGROUND ENGINE AND CLOSE THE DIALOG INSTANTLY!
                            CampaignEngine.instance.startBackgroundLoop(
                              restaurantId: widget.restaurantId,
                              campaignId: currentCampaignId,
                              targetPhones: finalTargets,
                              activeContacts: activeContacts,
                              templateName: selectedTemplateName!,
                              templateData: selectedTemplateData!,
                              variableMappings: variableMappings,
                              phoneNumberId: activePhoneNumberId,
                              waToken: activeWaToken,
                              mediaUrl: finalMediaUrl,
                              mediaId: finalMediaId,
                              buttonUrlParam: buttonUrlParamCtrl.text.trim().isEmpty ? null : buttonUrlParamCtrl.text.trim(),
                            );

                            if (mounted) {
                              Navigator.pop(context); // CLOSE IT!
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Campaign launched in the background! Watch the table update live."), backgroundColor: primaryTeal));
                            }
                          },
                    icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 16),
                    label: Text(isSending ? "Uploading & Starting..." : "Launch Campaign", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}