import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../../services/database_helper.dart';

class ContactsTab extends StatefulWidget {
  final String restaurantId;
  const ContactsTab({super.key, required this.restaurantId});

  @override
  State<ContactsTab> createState() => ContactsTabState();
}

class ContactsTabState extends State<ContactsTab> {
  bool _isLoading = true;

  List<Map<String, dynamic>> _allContacts = [];
  List<Map<String, dynamic>> _labels = [];
  List<String> _selectedContactPhones = [];

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

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      // 🔥 FIX 1: Cleanup orphaned labels FIRST (handles deleted labels still showing on contacts)
      await DatabaseHelper.instance.cleanupOrphanedLabels(widget.restaurantId);
      // 🔥 FIX 2: Recalculate counts AFTER cleanup so counts are always accurate
      await DatabaseHelper.instance.recalculateLabelCounts(widget.restaurantId);

      final contacts = await DatabaseHelper.instance.getAllContacts(
        widget.restaurantId,
      );
      final labels = await DatabaseHelper.instance.getAllLabels(
        widget.restaurantId,
      );

      if (mounted) {
        setState(() {
          _allContacts = contacts;
          _labels = labels;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading contacts: $e");
      if (mounted) setState(() => _isLoading = false);
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

  void _showApplyLabelDialog() {
    if (_labels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please create a label in the Labels tab first."),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "Apply Label to ${_selectedContactPhones.length} contacts",
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _labels.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: Icon(Icons.label, color: primaryTeal),
                title: Text(
                  _labels[index]['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  String labelName = _labels[index]['name'];

                  for (var phone in _selectedContactPhones) {
                    var contactIndex = _allContacts.indexWhere(
                      (c) => c['phone'] == phone,
                    );
                    if (contactIndex != -1) {
                      var contact = Map<String, dynamic>.from(
                        _allContacts[contactIndex],
                      );
                      List<String> cLabels =
                          (contact['labels'] as List<dynamic>?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          [];

                      if (!cLabels.contains(labelName)) {
                        cLabels.add(labelName);
                        contact['labels'] = cLabels;
                        await DatabaseHelper.instance.upsertContact(
                          widget.restaurantId,
                          contact,
                        );
                      }
                    }
                  }

                  // 🔥 FIX 3: Single _loadData() call — it already does cleanup
                  // + recalculate internally. No more triple calls.
                  setState(() => _selectedContactPhones.clear());
                  await loadData();

                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Labels applied successfully!"),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  // ➕ Add Contact dialog — lets users manually create a new WhatsApp contact
  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            "Add Contact",
            style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Name",
                    hintText: "e.g. John Doe",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone (with country code)",
                    hintText: "e.g. 919876543210",
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryTeal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final String phone = phoneController.text.trim().replaceAll(
                  RegExp(r'[^0-9]'),
                  '',
                );
                final String name = nameController.text.trim();

                if (phone.isEmpty || phone.length < 8) {
                  setDialogState(
                    () => errorText =
                        "Enter a valid phone number with country code.",
                  );
                  return;
                }

                final bool exists = _allContacts.any(
                  (c) => c['phone'].toString() == phone,
                );
                if (exists) {
                  setDialogState(
                    () => errorText =
                        "A contact with this number already exists.",
                  );
                  return;
                }

                await DatabaseHelper.instance
                    .upsertContact(widget.restaurantId, {
                      'phone': phone,
                      'name': name.isNotEmpty ? name : phone,
                      'status': 'Active',
                      'labels': <String>[],
                    });

                await loadData();

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Contact added successfully!"),
                    ),
                  );
                }
              },
              child: const Text(
                "Add Contact",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📥 Bulk Import — lets users upload a CSV (name,phone) to add many contacts at once
  Future<void> _importContactsFromCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    final String content = String.fromCharCodes(result.files.single.bytes!);
    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(
        eol: '\n',
      ).convert(content, shouldParseNumbers: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Couldn't read CSV file: $e")));
      }
      return;
    }
    if (rows.isEmpty) return;

    // Detect & skip a header row like "name,phone"
    final firstRowLower = rows.first
        .map((e) => e.toString().toLowerCase())
        .toList();
    final bool hasHeader =
        firstRowLower.contains('phone') || firstRowLower.contains('name');
    final dataRows = hasHeader ? rows.skip(1).toList() : rows;

    int added = 0;
    int skippedDuplicate = 0;
    int skippedInvalid = 0;
    final Set<String> seenInFile = {};

    // Show a progress dialog while importing (can be many rows)
    bool isImporting = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (isImporting) {
            // Kick off the import once the dialog is showing
            Future(() async {
              for (final row in dataRows) {
                if (row.isEmpty) continue;

                String name = '';
                String phoneRaw = '';
                if (row.length >= 2) {
                  name = row[0].toString().trim();
                  phoneRaw = row[1].toString().trim();
                } else {
                  phoneRaw = row[0].toString().trim();
                }
                final String phone = phoneRaw.replaceAll(RegExp(r'[^0-9]'), '');

                if (phone.isEmpty || phone.length < 8) {
                  skippedInvalid++;
                  continue;
                }
                final bool existsAlready = _allContacts.any(
                  (c) => c['phone'].toString() == phone,
                );
                if (existsAlready || seenInFile.contains(phone)) {
                  skippedDuplicate++;
                  continue;
                }

                seenInFile.add(phone);
                await DatabaseHelper.instance
                    .upsertContact(widget.restaurantId, {
                      'phone': phone,
                      'name': name.isNotEmpty ? name : phone,
                      'status': 'Active',
                      'labels': <String>[],
                    });
                added++;
              }

              await loadData();
              isImporting = false;
              if (ctx.mounted) {
                Navigator.pop(ctx); // close progress dialog
                showDialog(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    title: Text(
                      "Import Complete",
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: Text(
                      "$added contact(s) added.\n$skippedDuplicate duplicate(s) skipped.\n$skippedInvalid invalid row(s) skipped.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              }
            });
          }

          return AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: primaryTeal),
                const SizedBox(width: 16),
                const Text("Importing contacts..."),
              ],
            ),
          );
        },
      ),
    );
  }

  // 🔥 FIX 4: Remove label dialog — lets users unassign a label from a contact
  void _showRemoveLabelDialog(Map<String, dynamic> contact) {
    List<String> cLabels =
        (contact['labels'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (cLabels.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "Remove Label",
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Tap a label to remove it from ${contact['name']}:",
                style: TextStyle(color: textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cLabels
                    .map(
                      (label) => ActionChip(
                        label: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        avatar: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.red,
                        ),
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: Colors.red.shade200),
                        onPressed: () async {
                          var updatedContact = Map<String, dynamic>.from(
                            contact,
                          );
                          List<String> updatedLabels = List<String>.from(
                            cLabels,
                          );
                          updatedLabels.remove(label);
                          updatedContact['labels'] = updatedLabels;

                          await DatabaseHelper.instance.upsertContact(
                            widget.restaurantId,
                            updatedContact,
                          );
                          await loadData();

                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Removed '$label' from ${contact['name']}",
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: primaryTeal));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  "Total Contacts",
                  _allContacts.length.toString(),
                  Icons.people_outline,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildSummaryCard(
                  "Active Contacts",
                  _allContacts
                      .where((c) => c['status'] == 'Active')
                      .length
                      .toString(),
                  Icons.check_circle_outline,
                  color: successText,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildSummaryCard(
                  "Blocked/Opt-out",
                  _allContacts
                      .where((c) => c['status'] != 'Active')
                      .length
                      .toString(),
                  Icons.block,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _showAddContactDialog(),
                      icon: const Icon(Icons.person_add_alt_1, size: 16),
                      label: const Text(
                        "Add Contact",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryTeal,
                        side: BorderSide(color: primaryTeal),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _importContactsFromCsv(),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text(
                        "Import CSV",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(Icons.checklist, color: textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Batch Select:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildBatchButton(
                      "All",
                      () => _selectBatch(_allContacts.length),
                    ),
                    const SizedBox(width: 8),
                    _buildBatchButton("First 50", () => _selectBatch(50)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selectedContactPhones.isEmpty
                          ? null
                          : () =>
                                setState(() => _selectedContactPhones.clear()),
                      child: Text(
                        "Clear",
                        style: TextStyle(
                          color: _selectedContactPhones.isEmpty
                              ? Colors.grey
                              : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _selectedContactPhones.isEmpty
                      ? null
                      : () => _showApplyLabelDialog(),
                  icon: const Icon(Icons.label_outline, size: 16),
                  label: Text(
                    "Apply Label (${_selectedContactPhones.length})",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_allContacts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.contact_phone_outlined,
                    size: 48,
                    color: textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No contacts found",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _allContacts.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 1, color: cardBorder),
                itemBuilder: (context, index) {
                  var contact = _allContacts[index];
                  bool isSelected = _selectedContactPhones.contains(
                    contact['phone'],
                  );
                  List<String> cLabels =
                      (contact['labels'] as List<dynamic>?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      [];

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected)
                          _selectedContactPhones.remove(contact['phone']);
                        else
                          _selectedContactPhones.add(contact['phone']);
                      });
                    },
                    child: Container(
                      color: isSelected
                          ? primaryTeal.withOpacity(0.05)
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            activeColor: primaryTeal,
                            onChanged: (val) {
                              setState(() {
                                if (val == true)
                                  _selectedContactPhones.add(contact['phone']);
                                else
                                  _selectedContactPhones.remove(
                                    contact['phone'],
                                  );
                              });
                            },
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              "${index + 1}",
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: primaryTeal,
                                  child: Text(
                                    contact['name'].toString().isNotEmpty
                                        ? contact['name'][0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      contact['name'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: textDark,
                                      ),
                                    ),
                                    Text(
                                      "+${contact['phone']}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // 🔥 FIX 4: Labels column — tap a label chip to remove it
                          Expanded(
                            flex: 2,
                            child: cLabels.isEmpty
                                ? Text(
                                    "No labels",
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 13,
                                    ),
                                  )
                                : Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: cLabels
                                        .map(
                                          (l) => GestureDetector(
                                            onLongPress: () =>
                                                _showRemoveLabelDialog(contact),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: Colors.blue.shade200,
                                                ),
                                              ),
                                              child: Text(
                                                l,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue.shade700,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: successBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  contact['status'],
                                  style: TextStyle(
                                    color: successText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBatchButton(String title, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: textDark,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon, {
    Color? color,
  }) {
    Color effectiveColor = color ?? primaryTeal;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: effectiveColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: effectiveColor, size: 24),
          ),
        ],
      ),
    );
  }
}
