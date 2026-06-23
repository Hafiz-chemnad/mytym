import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class MarketingScreen extends StatefulWidget {
  final String restaurantId;
  const MarketingScreen({super.key, required this.restaurantId});

  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // Tab Navigation State
  int _selectedTabIndex = 0; 

  // Real Data States
  List<Map<String, dynamic>> _allContacts = [];
  List<String> _selectedContactPhones = []; 
  
  // Local States (Until APIs are ready)
  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _labels = [];

  // 🎨 POS Theme Colors
  final Color primaryTeal = const Color(0xFF096A56);
  final Color bgLight = const Color(0xFFF2F7F4); 
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);
  final Color successBg = const Color(0xFFE6F4EA);
  final Color successText = const Color(0xFF14804A);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadAllContacts(),
      _fetchCampaigns(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  // 🚀 1. Fetch Contacts
  Future<void> _loadAllContacts() async {
    try {
      final waUrl = Uri.parse('https://tym-whatsapp-backend.onrender.com/api/messages');
      final waResponse = await http.get(waUrl);

      Map<String, Map<String, dynamic>> uniqueContacts = {};

      if (waResponse.statusCode == 200) {
        final dynamic decodedData = jsonDecode(waResponse.body);
        List<dynamic> allMessages = decodedData is Map ? (decodedData['data'] ?? decodedData['messages'] ?? []) : (decodedData is List ? decodedData : []);
        
        for (var m in allMessages) {
          String resId = m['restaurantId']?.toString() ?? m['restaurant_id']?.toString() ?? "";
          String phone = m['customerNumber']?.toString() ?? m['customer_number']?.toString() ?? "";
          String name = m['customerName']?.toString() ?? "WhatsApp User";
          
          if (resId == widget.restaurantId && phone.isNotEmpty && !uniqueContacts.containsKey(phone)) {
            uniqueContacts[phone] = {"name": name, "phone": phone, "source": "WhatsApp", "status": "Active", "labels": <String>[]};
          }
        }
      }
      _allContacts = uniqueContacts.values.toList();
    } catch (e) {
      print("Fetch Contacts Error: $e");
    }
  }

  // 🚀 2. Fetch Campaigns
  Future<void> _fetchCampaigns() async {
    try {
      final url = Uri.parse('https://tym-whatsapp-backend.onrender.com/api/campaigns/${widget.restaurantId}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        _campaigns = List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
    } catch (e) {
      // Keep local state intact if API fails
    }
  }

  void _selectBatch(int count) {
    setState(() {
      _selectedContactPhones.clear();
      int limit = count > _allContacts.length ? _allContacts.length : count;
      for (int i = 0; i < limit; i++) {
        _selectedContactPhones.add(_allContacts[i]['phone']);
      }
    });
  }

  // =====================================================================
  // MAIN BUILDER
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Marketing & CRM", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: textDark)),
                const SizedBox(height: 2),
                Text("Manage your WhatsApp contacts, labels, and broadcast campaigns.", style: TextStyle(color: textMuted, fontSize: 13)),
              ],
            ),
          ),
          Divider(height: 1, color: cardBorder),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cardBorder, width: 1)), color: Colors.white),
            child: Row(
              children: [
                _buildTab(0, "Contacts"),
                _buildTab(1, "Labels"),
                _buildTab(2, "Campaigns"),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? Center(child: CircularProgressIndicator(color: primaryTeal))
              : _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    if (_selectedTabIndex == 0) return _buildContactsTab();
    if (_selectedTabIndex == 1) return _buildLabelsTab();
    return _buildCampaignsTab();
  }

  Widget _buildTab(int index, String title) {
    bool isActive = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? primaryTeal : Colors.transparent, width: 3))),
        child: Text(title, style: TextStyle(color: isActive ? primaryTeal : textMuted, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }

  // =====================================================================
  // 👥 CONTACTS TAB & LABEL ASSIGNMENT
  // =====================================================================

  Widget _buildContactsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSummaryCard("Total Contacts", _allContacts.length.toString(), Icons.people_outline)),
              const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Active Contacts", _allContacts.where((c) => c['status'] == 'Active').length.toString(), Icons.check_circle_outline, color: successText)),
              const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Blocked/Opt-out", _allContacts.where((c) => c['status'] != 'Active').length.toString(), Icons.block, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist, color: textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text("Batch Select:", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
                    const SizedBox(width: 16),
                    _buildBatchButton("All", () => _selectBatch(_allContacts.length)),
                    const SizedBox(width: 8),
                    _buildBatchButton("First 50", () => _selectBatch(50)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selectedContactPhones.isEmpty ? null : () => setState(() => _selectedContactPhones.clear()), 
                      child: Text("Clear", style: TextStyle(color: _selectedContactPhones.isEmpty ? Colors.grey : Colors.redAccent, fontWeight: FontWeight.bold))
                    ),
                  ],
                ),
                // 🚀 FIX 1: APPLY LABEL BUTTON NOW WORKS
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _selectedContactPhones.isEmpty ? null : () => _showApplyLabelDialog(),
                  icon: const Icon(Icons.label_outline, size: 16),
                  label: Text("Apply Label (${_selectedContactPhones.length})", style: const TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_allContacts.isEmpty)
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(40),
               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
               child: Column(
                 children: [
                   Icon(Icons.contact_phone_outlined, size: 48, color: textMuted),
                   const SizedBox(height: 16),
                   Text("No contacts found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                 ],
               ),
             )
          else
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _allContacts.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: cardBorder),
                itemBuilder: (context, index) {
                  var contact = _allContacts[index];
                  bool isSelected = _selectedContactPhones.contains(contact['phone']);
                  List<String> cLabels = (contact['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) _selectedContactPhones.remove(contact['phone']);
                        else _selectedContactPhones.add(contact['phone']);
                      });
                    },
                    child: Container(
                      color: isSelected ? primaryTeal.withOpacity(0.05) : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isSelected, activeColor: primaryTeal,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) _selectedContactPhones.add(contact['phone']);
                                else _selectedContactPhones.remove(contact['phone']);
                              });
                            }
                          ),
                          SizedBox(width: 40, child: Text("${index + 1}", style: TextStyle(color: textMuted, fontSize: 13))),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                CircleAvatar(radius: 16, backgroundColor: primaryTeal, child: Text(contact['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(contact['name'], style: TextStyle(fontWeight: FontWeight.w600, color: textDark)),
                                    Text("+${contact['phone']}", style: TextStyle(fontSize: 12, color: textMuted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2, 
                            child: cLabels.isEmpty 
                              ? Text("No labels", style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 13))
                              : Wrap(
                                  spacing: 4,
                                  children: cLabels.map((l) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)),
                                    child: Text(l, style: TextStyle(fontSize: 10, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                                  )).toList(),
                                )
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: successBg, borderRadius: BorderRadius.circular(12)),
                                child: Text(contact['status'], style: TextStyle(color: successText, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
        ],
      ),
    );
  }

  void _showApplyLabelDialog() {
    if (_labels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please create a label in the Labels tab first.")));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Apply Label to ${_selectedContactPhones.length} contacts", style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _labels.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: Icon(Icons.label, color: primaryTeal),
                title: Text(_labels[index]['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  setState(() {
                    for (var phone in _selectedContactPhones) {
                      var contact = _allContacts.firstWhere((c) => c['phone'] == phone);
                      List<String> cLabels = (contact['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                      if (!cLabels.contains(_labels[index]['name'])) {
                        cLabels.add(_labels[index]['name']);
                        contact['labels'] = cLabels;
                        _labels[index]['count'] = (_labels[index]['count'] as int) + 1;
                      }
                    }
                    _selectedContactPhones.clear();
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Labels applied successfully!")));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        ],
      ),
    );
  }

  // =====================================================================
  // 🏷️ LABELS TAB UI
  // =====================================================================

  Widget _buildLabelsTab() {
    int labeledContacts = _labels.fold(0, (sum, item) => sum + (item['count'] as int));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSummaryCard("Total Labels", _labels.length.toString(), Icons.label_outline)),
              const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Contacts in Labels", labeledContacts.toString(), Icons.people_alt_outlined, color: primaryTeal)),
              const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Unlabeled Contacts", (_allContacts.length - labeledContacts).toString(), Icons.person_off_outlined, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_offer_outlined, color: textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text("Organize and manage your contact labels", style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () => _showCreateOrEditLabelDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Create Label", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_labels.isEmpty)
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(60),
               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
               child: Column(
                 children: [
                   Icon(Icons.label_off_outlined, size: 50, color: cardBorder),
                   const SizedBox(height: 16),
                   Text("No labels created yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                 ],
               ),
             )
          else
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _labels.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: cardBorder),
                itemBuilder: (context, index) {
                  var label = _labels[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text("${index + 1}", style: TextStyle(color: textMuted, fontSize: 13))),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label['name'], style: TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(label['description'], style: TextStyle(fontSize: 12, color: textMuted)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: successBg, borderRadius: BorderRadius.circular(12)),
                              child: Text("${label['count']} contacts", style: TextStyle(color: successText, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        Expanded(flex: 2, child: Text(label['date'], style: TextStyle(color: textDark, fontSize: 13))),
                        Row(
                          children: [
                            // 🚀 FIX 2: EDIT BUTTON NOW WORKS
                            IconButton(icon: Icon(Icons.edit_outlined, color: textMuted, size: 20), onPressed: () => _showCreateOrEditLabelDialog(index: index)),
                            // 🚀 FIX 3: DELETE NOW ASKS CONFIRMATION
                            IconButton(icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20), onPressed: () => _confirmDeleteLabel(index)),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            )
        ],
      ),
    );
  }

  void _showCreateOrEditLabelDialog({int? index}) {
    bool isEditing = index != null;
    TextEditingController nameCtrl = TextEditingController(text: isEditing ? _labels[index]['name'] : "");
    TextEditingController descCtrl = TextEditingController(text: isEditing ? _labels[index]['description'] : "");

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500, padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEditing ? "Edit Label" : "Create New Label", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                const SizedBox(height: 24),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: "Label Name",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty) return;
                        setState(() {
                          if (isEditing) {
                            _labels[index]['name'] = nameCtrl.text.trim();
                            _labels[index]['description'] = descCtrl.text.trim();
                          } else {
                            _labels.add({"name": nameCtrl.text.trim(), "description": descCtrl.text.trim().isEmpty ? "No description" : descCtrl.text.trim(), "count": 0, "date": "Today"});
                          }
                        });
                        Navigator.pop(context);
                      },
                      child: Text(isEditing ? "Update Label" : "Save Label", style: const TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteLabel(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Label?"),
        content: const Text("Are you sure you want to delete this label? Contacts will not be deleted, but the tag will be removed from them."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() => _labels.removeAt(index));
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // 📢 CAMPAIGNS TAB UI 
  // =====================================================================
  
  Widget _buildCampaignsTab() {
    int totalDelivered = _campaigns.where((c) => c['status'] == 'Completed').fold(0, (sum, c) => sum + (c['recipients'] as int));
    int totalFailed = _campaigns.where((c) => c['status'] == 'Failed').fold(0, (sum, c) => sum + (c['recipients'] as int));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSummaryCard("Total Campaigns", _campaigns.length.toString(), Icons.campaign_outlined)),
              const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Messages Delivered", totalDelivered.toString(), Icons.mark_chat_read_outlined, color: primaryTeal)),
              const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Failed Messages", totalFailed.toString(), Icons.error_outline, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.list_alt_rounded, color: textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text("All Campaigns", style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () => _showCreateCampaignDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Create Campaign", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_campaigns.isEmpty)
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(60),
               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
               child: Column(
                 children: [
                   Icon(Icons.campaign_outlined, size: 50, color: cardBorder),
                   const SizedBox(height: 16),
                   Text("No campaigns yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                 ],
               ),
             )
          else
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _campaigns.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: cardBorder),
                itemBuilder: (context, index) {
                  var camp = _campaigns[index];
                  bool isCompleted = camp['status'] == 'Completed';
                  bool isFailed = camp['status'] == 'Failed';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text("${index + 1}", style: TextStyle(color: textMuted, fontSize: 13))),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(camp['name'] ?? 'Unnamed', style: TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(camp['date'] ?? '', style: TextStyle(fontSize: 12, color: textMuted)),
                            ],
                          ),
                        ),
                        Expanded(flex: 2, child: Text("${camp['recipients'] ?? 0} Recipients", style: TextStyle(color: textDark, fontSize: 13))),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: isCompleted ? successBg : (isFailed ? Colors.red.shade50 : Colors.grey.shade100), borderRadius: BorderRadius.circular(12)),
                              child: Text(camp['status'] ?? 'Pending', style: TextStyle(color: isCompleted ? successText : (isFailed ? Colors.red : Colors.grey.shade700), fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20), onPressed: () => setState(() => _campaigns.removeAt(index))),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            )
        ],
      ),
    );
  }

  // 🚀 CREATE CAMPAIGN WIZARD (WITH ERROR HANDLING & UPDATED SAVING)
  void _showCreateCampaignDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController templateNameCtrl = TextEditingController();
    TextEditingController paramsCtrl = TextEditingController();

    bool isSending = false;
    int sentCount = 0;
    int failCount = 0;
    
    // 🚀 FIX 4: Audience Selection States
    String selectedAudienceType = 'All'; // 'All', 'Selected', or 'Label'
    String? selectedLabelId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            
            // Calculate who will actually receive it based on selection
            List<String> targetPhones = [];
            if (selectedAudienceType == 'All') {
              targetPhones = _allContacts.map((c) => c['phone'] as String).toList();
            } else if (selectedAudienceType == 'Selected') {
              targetPhones = List.from(_selectedContactPhones);
            } else if (selectedAudienceType == 'Label' && selectedLabelId != null) {
              targetPhones = _allContacts
                .where((c) {
                   List<String> lbls = (c['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                   return lbls.contains(selectedLabelId);
                })
                .map((c) => c['phone'] as String)
                .toList();
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 900, 
                height: 600,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Create New Campaign", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                              const SizedBox(height: 4),
                              Text("Configure your template and audience.", style: TextStyle(fontSize: 13, color: textMuted)),
                            ],
                          ),
                          if (!isSending) 
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cardBorder),
                    
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Campaign Details", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: nameCtrl,
                                    enabled: !isSending,
                                    decoration: InputDecoration(labelText: "Campaign Name (e.g., Summer Sale)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2))),
                                  ),
                                  const SizedBox(height: 24),
                                  
                                  Text("Meta Template", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: templateNameCtrl,
                                    enabled: !isSending,
                                    onChanged: (val) => setModalState((){}),
                                    decoration: InputDecoration(labelText: "Template Name", prefixIcon: const Icon(Icons.code), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2))),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: paramsCtrl,
                                    enabled: !isSending,
                                    onChanged: (val) => setModalState((){}),
                                    decoration: InputDecoration(labelText: "Parameters (Optional, comma separated)", hintText: "e.g. John, 20%", prefixIcon: const Icon(Icons.data_object), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2))),
                                  ),
                                  
                                  const SizedBox(height: 24),
                                  Text("Target Audience", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
                                  const SizedBox(height: 16),
                                  
                                  // 🚀 FIX 4: REAL AUDIENCE SELECTOR
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder), color: const Color(0xFFF8FAFC)),
                                    child: Column(
                                      children: [
                                        RadioListTile<String>(
                                          title: Text("All Contacts (${_allContacts.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          value: 'All', groupValue: selectedAudienceType, activeColor: primaryTeal,
                                          onChanged: (val) => setModalState(() => selectedAudienceType = val!),
                                        ),
                                        if (_selectedContactPhones.isNotEmpty)
                                          RadioListTile<String>(
                                            title: Text("Currently Checked Contacts (${_selectedContactPhones.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            value: 'Selected', groupValue: selectedAudienceType, activeColor: primaryTeal,
                                            onChanged: (val) => setModalState(() => selectedAudienceType = val!),
                                          ),
                                        if (_labels.isNotEmpty)
                                          RadioListTile<String>(
                                            title: const Text("By Specific Label", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            value: 'Label', groupValue: selectedAudienceType, activeColor: primaryTeal,
                                            onChanged: (val) {
                                              setModalState(() {
                                                selectedAudienceType = val!;
                                                selectedLabelId = _labels.first['name']; // default to first
                                              });
                                            },
                                          ),
                                        if (selectedAudienceType == 'Label')
                                          Padding(
                                            padding: const EdgeInsets.only(left: 48, right: 16, bottom: 8),
                                            child: DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                              value: selectedLabelId,
                                              items: _labels.map((l) => DropdownMenuItem<String>(value: l['name'], child: Text("${l['name']} (${l['count']} contacts)", style: const TextStyle(fontSize: 12)))).toList(),
                                              onChanged: (val) => setModalState(() => selectedLabelId = val),
                                            ),
                                          )
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Total Recipients for this campaign: ${targetPhones.length}", style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          
                          Container(width: 1, color: cardBorder),

                          // ➡️ RIGHT SIDE: Dynamic Preview
                          Expanded(
                            flex: 5,
                            child: Container(
                              color: const Color(0xFFF3F4F6), 
                              child: Center(
                                child: Container(
                                  width: 320,
                                  height: 450,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5DDD5), borderRadius: BorderRadius.circular(16),
                                    image: const DecorationImage(image: NetworkImage("https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png"), fit: BoxFit.cover, opacity: 0.4),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(templateNameCtrl.text.isEmpty ? "Enter a template name..." : "Sending template:\n👉 ${templateNameCtrl.text}", style: TextStyle(fontSize: 14, color: textDark, fontWeight: FontWeight.w600)),
                                              if (paramsCtrl.text.isNotEmpty) ...[
                                                const SizedBox(height: 8), Text("With Parameters:", style: TextStyle(fontSize: 12, color: textMuted)),
                                                Text("[${paramsCtrl.text}]", style: const TextStyle(fontSize: 13, color: Colors.blueAccent, fontWeight: FontWeight.w500)),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    
                    Divider(height: 1, color: cardBorder),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!isSending)
                            TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: isSending || targetPhones.isEmpty ? null : () async {
                              if (templateNameCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Campaign Name and Template Name are required!")));
                                return;
                              }

                              setModalState(() {
                                isSending = true;
                                sentCount = 0;
                                failCount = 0;
                              });

                              List<String> paramsList = paramsCtrl.text.isNotEmpty ? paramsCtrl.text.split(',').map((e) => e.trim()).toList() : [];

                              // 🚀 FIX 5: TRACKING FAILURES IF TEMPLATE IS BAD
                              for (String phone in targetPhones) {
                                bool success = await _apiService.sendTemplateMessage(
                                  restaurantId: widget.restaurantId,
                                  customerNumber: phone,
                                  templateName: templateNameCtrl.text.trim(),
                                  templateParams: paramsList,
                                );
                                if (success) {
                                  sentCount++;
                                } else {
                                  failCount++;
                                }
                                setModalState(() {});
                              }

                              Navigator.pop(context);
                              
                              // 🚀 FIX 6: SAVING CAMPAIGN TO THE TABLE LOCALLY
                              setState(() {
                                _campaigns.insert(0, {
                                  "name": nameCtrl.text.trim(),
                                  "date": "Just now",
                                  "recipients": targetPhones.length,
                                  // If all failed, mark as Failed. If some sent, Completed.
                                  "status": (failCount == targetPhones.length) ? "Failed" : "Completed" 
                                });
                              });

                              if (failCount > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Finished: $sentCount sent, $failCount failed (Check template name).", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.orange));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Campaign '${nameCtrl.text}' completed perfectly! Sent to $sentCount users.", style: const TextStyle(color: Colors.white)), backgroundColor: primaryTeal));
                              }
                            },
                            icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 16),
                            label: Text(isSending ? "Sending (${sentCount + failCount}/${targetPhones.length})..." : "Launch Campaign", style: const TextStyle(fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  // =====================================================================
  // HELPER WIDGETS
  // =====================================================================
  Widget _buildBatchButton(String title, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: textDark, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), side: BorderSide(color: cardBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      onPressed: onTap, child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, {Color? color}) {
    Color effectiveColor = color ?? primaryTeal;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: textDark, fontSize: 28, fontWeight: FontWeight.w900)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: effectiveColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: effectiveColor, size: 24),
          )
        ],
      ),
    );
  }
}