import 'package:flutter/material.dart';
import 'package:whatsapp_erp/features/marketing/screens/tabs/campaign_details_dialog.dart';
import '../../services/crm_db.dart';
import '../../services/campaign_api.dart';
import '../../services/template_db.dart'; 

// 🚀 IMPORT YOUR TWO NEW FILES!
import 'campaign_engine.dart';
import 'create_campaign_dialog.dart';

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
  List<Map<String, dynamic>> _approvedTemplates = []; 

  final Color primaryTeal = const Color(0xFF096A56);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);
  final Color successBg = const Color(0xFFE6F4EA);
  final Color successText = const Color(0xFF14804A);

  @override
  void initState() {
    super.initState();
    // 🚀 LISTEN TO THE ENGINE FOR LIVE TICK UPDATES
    CampaignEngine.instance.addListener(_onEngineUpdate);
    loadData();
  }

  @override
  void dispose() {
    CampaignEngine.instance.removeListener(_onEngineUpdate);
    super.dispose();
  }

  void _onEngineUpdate() {
    // Whenever a message sends in the background, reload SQLite to update table!
    _reloadFromCache(); 
  }

  Future<void> loadData() async {
    await CrmDbService.instance.cleanupOrphanedLabels(widget.restaurantId);
    final cachedCampaigns = await CrmDbService.instance.getAllCampaigns(widget.restaurantId);
    final cachedContacts = await CrmDbService.instance.getAllContacts(widget.restaurantId);
    final cachedLabels = await CrmDbService.instance.getAllLabels(widget.restaurantId);
    final cachedTemplates = await TemplateDbService.instance.getApprovedTemplates(widget.restaurantId); 

    if (mounted) {
      setState(() {
        _campaigns = cachedCampaigns;
        _allContacts = cachedContacts;
        _labels = cachedLabels;
        _approvedTemplates = cachedTemplates; 
        _isLoading = false;
      });
    }

    try {
      await CampaignApi.instance.refreshCampaigns(widget.restaurantId);
      final freshCampaigns = await CrmDbService.instance.getAllCampaigns(widget.restaurantId);
      if (mounted) setState(() => _campaigns = freshCampaigns);
    } catch (e) {}
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
        content: Text("Remove '${camp['name']}' from your campaign history?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final result = await CampaignApi.instance.deleteCampaign(widget.restaurantId, camp['id'].toString());
              if (mounted) Navigator.pop(ctx);
              await _reloadFromCache();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
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
                  
                  // 🚀 NEW: Grouped Refresh and Create buttons!
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), side: BorderSide(color: cardBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Refreshing data..."), backgroundColor: primaryTeal, duration: const Duration(seconds: 1)));
                          loadData(); // Re-fetches from backend and SQLite!
                        },
                        icon: Icon(Icons.refresh_rounded, size: 18, color: textDark), 
                        label: Text("Refresh", style: TextStyle(fontWeight: FontWeight.bold, color: textDark))
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), 
                        onPressed: () {
                          showDialog(context: context, builder: (_) => CreateCampaignDialog(restaurantId: widget.restaurantId, allContacts: _allContacts, labels: _labels, approvedTemplates: _approvedTemplates))
                          .then((_) => loadData());
                        }, 
                        icon: const Icon(Icons.add, size: 18), label: const Text("Create Campaign", style: TextStyle(fontWeight: FontWeight.bold))
                      ),
                    ],
                  ),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
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
                  ListView.separated(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _campaigns.length, 
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      var camp = _campaigns[index];
                      final display = _statusDisplay(camp['status']?.toString());
                      
                      String displayDate = 'Unknown date';
                      try {
                        DateTime? dt = DateTime.tryParse(camp['date']?.toString() ?? '');
                        if (dt != null) {
                          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          displayDate = "${months[dt.month - 1]} ${dt.day}, ${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}";
                        }
                      } catch (e) {}

                      int total = int.tryParse(camp['recipients']?.toString() ?? '0') ?? 0;
                      int sent = int.tryParse(camp['sent_count']?.toString() ?? '0') ?? 0;
                      int delivered = int.tryParse(camp['delivered_count']?.toString() ?? '0') ?? 0;
                      int read = int.tryParse(camp['read_count']?.toString() ?? '0') ?? 0;
                      int failed = int.tryParse(camp['failed_count']?.toString() ?? '0') ?? 0;

                      String displayLabel = 'All Contacts';
                      bool isCustomLabel = false;
                      if (camp['label_id'] != null) {
                        final found = _labels.where((l) => l['id'] == camp['label_id']).toList();
                        if (found.isNotEmpty) { displayLabel = found.first['name'].toString(); isCustomLabel = true; }
                      }

                      // 🚀 CHECK IF THIS CAMPAIGN IS CURRENTLY RUNNING IN THE ENGINE!
                      bool isRunning = CampaignEngine.instance.isRunning(camp['id'].toString());

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Row(
                          children: [
                            SizedBox(width: 40, child: Text("${index + 1}", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(camp['name'] ?? 'Unnamed', style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 14)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: display['bg'], borderRadius: BorderRadius.circular(12)), child: Text(display['label'], style: TextStyle(color: display['text'], fontSize: 11, fontWeight: FontWeight.w600)))]), const SizedBox(height: 4), Text(camp['template_name'] ?? '', style: TextStyle(fontSize: 13, color: textDark)), const SizedBox(height: 2), Text(displayDate, style: TextStyle(fontSize: 12, color: textMuted))])),
                            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: isCustomLabel ? Colors.purple.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)), child: Text(displayLabel, style: TextStyle(color: isCustomLabel ? Colors.purple.shade700 : Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w500))))),
                            Expanded(flex: 1, child: Text("$total", style: TextStyle(color: textDark, fontSize: 13))),
                            Expanded(flex: 1, child: Text("${total > 0 ? (sent / total * 100).toStringAsFixed(0) : '0'}% ($sent)", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 1, child: Text("${total > 0 ? (delivered / total * 100).toStringAsFixed(0) : '0'}% ($delivered)", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 1, child: Text("${total > 0 ? (read / total * 100).toStringAsFixed(0) : '0'}% ($read)", style: TextStyle(color: textMuted, fontSize: 13))),
                            Expanded(flex: 1, child: Text("${total > 0 ? (failed / total * 100).toStringAsFixed(0) : '0'}% ($failed)", style: TextStyle(color: Colors.red.shade400, fontSize: 13))),
                            Expanded(
                              flex: 2,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 🚀 THE NEW LIVE ACTION BUTTONS (STOP or PLAY)
// 🚀 THE NEW LIVE ACTION BUTTONS (STOP or PLAY)
                                  if (camp['status'] == 'sending') ...[
                                    Container(
                                      decoration: BoxDecoration(border: Border.all(color: Colors.red.shade200), borderRadius: BorderRadius.circular(6), color: Colors.red.shade50),
                                      child: IconButton(constraints: const BoxConstraints(), padding: const EdgeInsets.all(6), icon: Icon(Icons.stop_rounded, color: Colors.red.shade700, size: 18), tooltip: "Stop Sending",
                                        onPressed: () async {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stopping campaign...")));
                                          // 1. Kill the local background loop if it's running
                                          CampaignEngine.instance.stopCampaign(camp['id'].toString());
                                          // 2. Tell the backend to cancel it
                                          await CampaignApi.instance.cancelCampaign(widget.restaurantId, camp['id'].toString());
                                          // 3. Refresh the table!
                                          await loadData();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ] else if (camp['status'] == 'cancelled' || camp['status'] == 'partial') ...[
                                    Container(
                                      decoration: BoxDecoration(border: Border.all(color: Colors.orange.shade200), borderRadius: BorderRadius.circular(6), color: Colors.orange.shade50),
                                      child: IconButton(
                                        constraints: const BoxConstraints(), padding: const EdgeInsets.all(6), icon: Icon(Icons.play_arrow_rounded, color: Colors.orange.shade700, size: 18), tooltip: "Resume Campaign",
                                        onPressed: () async {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fetching pending contacts...")));
                                          final details = await CampaignApi.instance.getCampaignDetails(widget.restaurantId, camp['id'].toString());
                                          if (details == null) return;
                                          List<dynamic> recipients = details['recipients'] ?? [];
                                          List<String> pendingList = recipients.where((r) => r['status'] == 'pending').map((r) => r['phone'].toString()).toList();
                                          if (pendingList.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No pending contacts left!"))); return; }
                                          showDialog(context: context, builder: (_) => CreateCampaignDialog(restaurantId: widget.restaurantId, allContacts: _allContacts, labels: _labels, approvedTemplates: _approvedTemplates, resumeCampaignId: camp['id'].toString(), resumeName: camp['name'], resumeTemplate: camp['template_name'], pendingPhones: pendingList))
                                          .then((_) => loadData());
                                        }
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Container(decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(6)), child: IconButton(constraints: const BoxConstraints(), padding: const EdgeInsets.all(6), icon: const Icon(Icons.remove_red_eye_outlined, color: Colors.black87, size: 18), onPressed: () => showDialog(context: context, builder: (_) => CampaignDetailsDialog(restaurantId: widget.restaurantId, initialCampaign: camp)))), const SizedBox(width: 8),
                                  Container(decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(6)), child: IconButton(constraints: const BoxConstraints(), padding: const EdgeInsets.all(6), icon: Icon(Icons.delete_outline, color: (camp['status'] == 'sending' || isRunning) ? Colors.grey.shade300 : Colors.red.shade300, size: 18), onPressed: () => _confirmDeleteCampaign(camp))),
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
    return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
     child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(value, style: TextStyle(color: textDark, fontSize: 28, fontWeight: FontWeight.w900))]), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: effectiveColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: effectiveColor, size: 24))]));
  }
}