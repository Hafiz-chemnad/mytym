import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../../services/crm_db.dart';
import '../../services/contact_api.dart';

class ContactsTab extends StatefulWidget {
  final String restaurantId;
  const ContactsTab({super.key, required this.restaurantId});

  @override
  State<ContactsTab> createState() => ContactsTabState();
}

class ContactsTabState extends State<ContactsTab> {
  final GlobalKey _applyLabelButtonKey = GlobalKey();
  bool _isLoading = false;

  List<Map<String, dynamic>> _allContacts = [];
  List<Map<String, dynamic>> _labels = [];
  List<String> _selectedContactPhones = [];
  
  // 🚀 NEW: Search Controller
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 🎨 POS Theme Colors
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    final cachedContacts = await CrmDbService.instance.getAllContacts(widget.restaurantId);
    final cachedLabels = await CrmDbService.instance.getAllLabels(widget.restaurantId);

    if (mounted) {
      setState(() {
        _allContacts = cachedContacts;
        _labels = cachedLabels;
        _isLoading = false;
      });
    }

    try {
      await ContactApi.instance.refreshContacts(widget.restaurantId);
      await CrmDbService.instance.cleanupOrphanedLabels(widget.restaurantId);
      await CrmDbService.instance.recalculateLabelCounts(widget.restaurantId);

      final freshContacts = await CrmDbService.instance.getAllContacts(widget.restaurantId);
      final freshLabels = await CrmDbService.instance.getAllLabels(widget.restaurantId);

      if (mounted) {
        setState(() {
          _allContacts = freshContacts;
          _labels = freshLabels;
        });
      }
    } catch (e) {}
  }

  Future<void> _reloadFromCache() async {
    final contacts = await CrmDbService.instance.getAllContacts(widget.restaurantId);
    final labels = await CrmDbService.instance.getAllLabels(widget.restaurantId);
    if (mounted) {
      setState(() {
        _allContacts = contacts;
        _labels = labels;
      });
    }
  }

  // 🚀 NEW: Dynamic Search Filter
  List<Map<String, dynamic>> get _filteredContacts {
    if (_searchQuery.isEmpty) return _allContacts;
    return _allContacts.where((c) {
      final name = c['name'].toString().toLowerCase();
      final phone = c['phone'].toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  void _selectBatch(int count) {
    setState(() {
      _selectedContactPhones.clear();
      final listToUse = _filteredContacts;
      int limit = count > listToUse.length ? listToUse.length : count;
      for (int i = 0; i < limit; i++) {
        _selectedContactPhones.add(listToUse[i]['phone']);
      }
    });
  }

 void _showApplyLabelDialog() {
  if (_labels.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please create a label in the Labels tab first.")));
    return;
  }

  // 🚀 Find the button's on-screen position so the menu opens right under it
  final RenderBox buttonBox = _applyLabelButtonKey.currentContext!.findRenderObject() as RenderBox;
  final Offset buttonPosition = buttonBox.localToGlobal(Offset.zero);
  final Size buttonSize = buttonBox.size;

  showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      buttonPosition.dx,
      buttonPosition.dy + buttonSize.height + 4,   // just below the button
      buttonPosition.dx + buttonSize.width,
      0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    color: Colors.white,
    elevation: 4,
    items: _labels.map((label) {
      return PopupMenuItem<String>(
        value: label['name'],
        height: 40,
        child: Row(
          children: [
            Icon(Icons.label, color: primaryTeal, size: 16),
            const SizedBox(width: 10),
            Text(label['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
    }).toList(),
  ).then((selectedLabelName) async {
    if (selectedLabelName == null) return;   // user tapped outside — cancelled

    final phones = List<String>.from(_selectedContactPhones);
    for (var phone in phones) {
      var contactIndex = _allContacts.indexWhere((c) => c['phone'] == phone);
      if (contactIndex != -1) {
        var contact = _allContacts[contactIndex];
        List<String> cLabels = (contact['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        if (!cLabels.contains(selectedLabelName)) {
          cLabels.add(selectedLabelName);
          await ContactApi.instance.updateContactLabels(widget.restaurantId, phone, cLabels);
        }
      }
    }

    setState(() => _selectedContactPhones.clear());
    await _reloadFromCache();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Labels applied successfully!")));
    }
  });
}
        
      
    
  

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("Add Contact", style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name", hintText: "e.g. John Doe", border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone (with country code)", hintText: "e.g. 919876543210", border: OutlineInputBorder())),
                if (errorText != null) ...[const SizedBox(height: 8), Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12))],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white),
              onPressed: () async {
                final String phone = phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                final String name = nameController.text.trim();

                if (phone.isEmpty || phone.length < 8) {
                  setDialogState(() => errorText = "Enter a valid phone number with country code.");
                  return;
                }

                final result = await ContactApi.instance.addContact(widget.restaurantId, name, phone);

                if (result == 'error') {
                  setDialogState(() => errorText = "Failed to save — check connection.");
                  return;
                }

                await _reloadFromCache();

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contact added successfully!")));
                }
              },
              child: const Text("Add Contact", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importContactsFromCsv() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
    if (result == null || result.files.single.bytes == null) return;

    final String content = String.fromCharCodes(result.files.single.bytes!);
    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(eol: '\n').convert(content, shouldParseNumbers: false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't read CSV file: $e")));
      return;
    }
    if (rows.isEmpty) return;

    final firstRowLower = rows.first.map((e) => e.toString().toLowerCase()).toList();
    final bool hasHeader = firstRowLower.contains('phone') || firstRowLower.contains('name');
    final dataRows = hasHeader ? rows.skip(1).toList() : rows;

final List<Map<String, String>> parsedRows = [];
    for (final row in dataRows) {
      if (row.isEmpty) continue;
      String name = '';
      String phoneRaw = '';
      String label = ''; // 🚀 NEW: Placeholder for the label

      if (row.length >= 3) {
        // 🚀 NEW: 3-column CSV [Name, Phone, Label]
        name = row[0].toString().trim();
        phoneRaw = row[1].toString().trim();
        label = row[2].toString().trim();
      } else if (row.length >= 2) {
        // Safe fallback for 2-column CSV [Name, Phone]
        name = row[0].toString().trim();
        phoneRaw = row[1].toString().trim();
      } else {
        // Safe fallback for 1-column CSV [Phone]
        phoneRaw = row[0].toString().trim();
      }
      
      // 🚀 Pass the label into the map (If blank, it's safely ignored by backend)
      parsedRows.add({'name': name, 'phone': phoneRaw, 'label': label}); 
    }
    bool isImporting = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (isImporting) {
            Future(() async {
              final counts = await ContactApi.instance.bulkImport(widget.restaurantId, parsedRows);
              final int added = counts['added'] ?? 0;
              final int enriched = counts['enriched'] ?? 0;
              final int skippedDuplicate = counts['duplicate'] ?? 0;
              final int skippedInvalid = counts['invalid'] ?? 0;

              await _reloadFromCache();
              isImporting = false;
              if (ctx.mounted) {
                Navigator.pop(ctx); 
                showDialog(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    title: Text("Import Complete", style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
                    content: Text("$added contact(s) added.\n$enriched existing contact(s) updated with a name.\n$skippedDuplicate duplicate(s) skipped.\n$skippedInvalid invalid row(s) skipped."),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text("OK"))],
                  ),
                );
              }
            });
          }
          return AlertDialog(content: Row(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: primaryTeal), const SizedBox(width: 16), const Text("Importing contacts...")]));
        },
      ),
    );
  }

  void _showRemoveLabelDialog(Map<String, dynamic> contact) {
    List<String> cLabels = (contact['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    if (cLabels.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove Label", style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Tap a label to remove it from ${contact['name']}:", style: TextStyle(color: textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: cLabels.map((label) => ActionChip(
                  label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  avatar: const Icon(Icons.close, size: 14, color: Colors.red),
                  backgroundColor: Colors.red.shade50, side: BorderSide(color: Colors.red.shade200),
                  onPressed: () async {
                    List<String> updatedLabels = List<String>.from(cLabels);
                    updatedLabels.remove(label);

                    await ContactApi.instance.updateContactLabels(widget.restaurantId, contact['phone'], updatedLabels);
                    await _reloadFromCache();

                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Removed '$label' from ${contact['name']}")));
                    }
                  },
                )).toList(),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: primaryTeal));

    final currentList = _filteredContacts;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSummaryCard("Total Contacts", _allContacts.length.toString(), Icons.people_outline)), const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Active Contacts", _allContacts.where((c) => c['status'] == 'Active').length.toString(), Icons.check_circle_outline, color: successText)), const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Blocked/Opt-out", _allContacts.where((c) => c['status'] != 'Active').length.toString(), Icons.block, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 32),
          
          // 🚀 HEADER ROW WITH SEARCH AND BUTTONS (REDESIGNED)
          Container(
            padding: const EdgeInsets.all(20), 
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
            child: Column(
              children: [
                // 1️⃣ TOP ROW: Search (Left) & Actions (Right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Search Bar
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: "Search name or phone...",
                          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal)),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                    // Primary Actions
                    Row(
                      children: [
                        OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: textDark, side: BorderSide(color: cardBorder), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () => _importContactsFromCsv(), icon: const Icon(Icons.upload_file, size: 18), label: const Text("Import CSV", style: TextStyle(fontWeight: FontWeight.bold))),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () => _showAddContactDialog(), icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text("Add Contact", style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ],
                ),
                
                // Subtle Divider
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: cardBorder),
                ),

                // 2️⃣ BOTTOM ROW: Batch Selection Tools
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.checklist, color: _selectedContactPhones.isNotEmpty ? primaryTeal : textMuted, size: 20), 
                        const SizedBox(width: 8), 
                        Text(_selectedContactPhones.isNotEmpty ? "${_selectedContactPhones.length} Contacts Selected" : "Batch Select:", style: TextStyle(fontWeight: FontWeight.bold, color: _selectedContactPhones.isNotEmpty ? primaryTeal : textDark)), 
                        const SizedBox(width: 16),
                        _buildBatchButton("All", () => _selectBatch(currentList.length)), 
                        const SizedBox(width: 8), 
                        _buildBatchButton("First 50", () => _selectBatch(50)), 
                        const SizedBox(width: 8),
                        if (_selectedContactPhones.isNotEmpty)
                          TextButton(onPressed: () => setState(() => _selectedContactPhones.clear()), child: const Text("Clear Selection", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    ElevatedButton.icon(
                      key: _applyLabelButtonKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedContactPhones.isNotEmpty ? primaryTeal : Colors.grey.shade200, 
                        foregroundColor: _selectedContactPhones.isNotEmpty ? Colors.white : Colors.grey.shade500, 
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                      ), 
                      onPressed: _selectedContactPhones.isEmpty ? null : () => _showApplyLabelDialog(), 
                      icon: const Icon(Icons.label_outline, size: 18), 
                      label: const Text("Apply Label", style: TextStyle(fontWeight: FontWeight.bold))
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          if (currentList.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(40), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)), child: Column(children: [Icon(Icons.contact_phone_outlined, size: 48, color: textMuted), const SizedBox(height: 16), Text("No contacts found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark))]))
          else
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
              child: Column(
                children: [
                  // 🚀 NEW: Table Header (Matching Campaigns Tab)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                    child: Row(
                      children: [
                        const SizedBox(width: 60), // Space for checkbox
                        Expanded(flex: 3, child: Text("Contacts", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text("Labels", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Status", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Source", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Created At", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 1, child: Text("Actions", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Table Body
                  ListView.separated(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: currentList.length, separatorBuilder: (context, index) => Divider(height: 1, color: cardBorder),
                    itemBuilder: (context, index) {
                      var contact = currentList[index];
                      bool isSelected = _selectedContactPhones.contains(contact['phone']);
                      List<String> cLabels = (contact['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

                      String displayDate = '-';
                      if (contact['created_at'] != null && contact['created_at'].toString().isNotEmpty) {
                        try {
                          displayDate = contact['created_at'].toString().split('T').first;
                        } catch(e){}
                      }

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) _selectedContactPhones.remove(contact['phone']); else _selectedContactPhones.add(contact['phone']);
                          });
                        },
                        child: Container(
                          color: isSelected ? primaryTeal.withOpacity(0.05) : Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              SizedBox(width: 60, child: Row(children: [Checkbox(value: isSelected, activeColor: primaryTeal, onChanged: (val) { setState(() { if (val == true) _selectedContactPhones.add(contact['phone']); else _selectedContactPhones.remove(contact['phone']); }); }), Text("${index + 1}", style: TextStyle(color: textMuted, fontSize: 12))])),
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    CircleAvatar(radius: 16, backgroundColor: primaryTeal, child: Text(contact['name'].toString().isNotEmpty ? contact['name'][0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))), const SizedBox(width: 12),
                                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(contact['name'], style: TextStyle(fontWeight: FontWeight.w600, color: textDark)), Text("+${contact['phone']}", style: TextStyle(fontSize: 12, color: textMuted))]),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: cLabels.isEmpty ? Text("No labels", style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 13))
                                    : Wrap(spacing: 4, runSpacing: 4, children: cLabels.map((l) => GestureDetector(onLongPress: () => _showRemoveLabelDialog(contact), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple.shade100)), child: Text(l, style: TextStyle(fontSize: 10, color: Colors.purple.shade700, fontWeight: FontWeight.bold))))).toList()),
                              ),
                              Expanded(flex: 1, child: Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: successBg, borderRadius: BorderRadius.circular(12)), child: Text(contact['status'], style: TextStyle(color: successText, fontSize: 12, fontWeight: FontWeight.bold))))),
                              Expanded(flex: 1, child: Text(_sourceLabel(contact['source']), style: TextStyle(color: textMuted, fontSize: 12))),                              Expanded(flex: 1, child: Text(displayDate, style: TextStyle(color: textMuted, fontSize: 12))),
 Expanded(
                                flex: 1, 
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(6)), 
                                    child: IconButton(
                                      constraints: const BoxConstraints(), 
                                      padding: const EdgeInsets.all(6), 
                                      tooltip: contact['status'] == 'Blocked' ? "Unblock Contact" : "Block from Campaigns", 
                                      icon: Icon(
                                        contact['status'] == 'Blocked' ? Icons.settings_backup_restore : Icons.block, 
                                        color: contact['status'] == 'Blocked' ? Colors.orange : Colors.red.shade300, 
                                        size: 18
                                      ), 
                                      onPressed: () async {
                                        String newStatus = contact['status'] == 'Blocked' ? 'Active' : 'Blocked';
                                        
                                        bool success = await ContactApi.instance.updateContactStatus(
                                          widget.restaurantId, 
                                          contact['phone'], 
                                          contact['name'], 
                                          newStatus
                                        );
                                        
                                        if (success) {
                                          await _reloadFromCache(); // Refreshes the table
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(newStatus == 'Blocked' ? "Contact Blocked. They will be skipped in future campaigns." : "Contact Unblocked!"))
                                            );
                                          }
                                        } else {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text("Network error. Could not update status."), backgroundColor: Colors.red)
                                            );
                                          }
                                        }
                                      }
                                    )
                                  ),
                                )
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildBatchButton(String title, VoidCallback onTap) {
    return OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: textDark, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), side: BorderSide(color: cardBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: onTap, child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)));
  }
 String _sourceLabel(dynamic source) {
  switch (source?.toString()) {
    case 'whatsapp': return 'WhatsApp';
    case 'csv_import': return 'CSV Import';
    case 'manual': return 'Manual';
    default: return 'Manual';
  }
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