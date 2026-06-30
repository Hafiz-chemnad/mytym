import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/database_helper.dart';

class CampaignsTab extends StatefulWidget {
  final String restaurantId;
  const CampaignsTab({super.key, required this.restaurantId});

  @override
  State<CampaignsTab> createState() => CampaignsTabState();
}

class CampaignsTabState extends State<CampaignsTab> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _allContacts = [];
  List<Map<String, dynamic>> _labels = [];

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

  // 🚀 Read from SQLite (Instant Load)
  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      // Cleanup orphaned labels so campaign audience filter is always accurate
      await DatabaseHelper.instance.cleanupOrphanedLabels(widget.restaurantId);
      final campaigns = await DatabaseHelper.instance.getAllCampaigns(
        widget.restaurantId,
      );
      final contacts = await DatabaseHelper.instance.getAllContacts(
        widget.restaurantId,
      );
      final labels = await DatabaseHelper.instance.getAllLabels(
        widget.restaurantId,
      );

      if (mounted) {
        setState(() {
          _campaigns = campaigns;
          _allContacts = contacts;
          _labels = labels;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading campaigns: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =====================================================================
  // 🚀 THE BROADCAST ENGINE WIZARD
  // =====================================================================
  void _showCreateCampaignDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController templateNameCtrl = TextEditingController();
    TextEditingController paramsCtrl = TextEditingController();

    bool isSending = false;
    int sentCount = 0;
    int failCount = 0;

    String selectedAudienceType = 'All'; // 'All' or 'Label'
    String? selectedLabelId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Calculate actual recipients
            List<String> targetPhones = [];
            if (selectedAudienceType == 'All') {
              targetPhones = _allContacts
                  .map((c) => c['phone'].toString())
                  .toList();
            } else if (selectedAudienceType == 'Label' &&
                selectedLabelId != null) {
              targetPhones = _allContacts
                  .where((c) {
                    List<String> lbls =
                        (c['labels'] as List<dynamic>?)
                            ?.map((e) => e.toString())
                            .toList() ??
                        [];
                    return lbls.contains(selectedLabelId);
                  })
                  .map((c) => c['phone'].toString())
                  .toList();
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 900,
                height: 600,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
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
                              Text(
                                "Create New Campaign",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Configure your template and audience.",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                          if (!isSending)
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
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
                                  Text(
                                    "Campaign Details",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: nameCtrl,
                                    enabled: !isSending,
                                    decoration: InputDecoration(
                                      labelText:
                                          "Campaign Name (e.g., Summer Sale)",
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: primaryTeal,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  Text(
                                    "Meta Template",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: templateNameCtrl,
                                    enabled: !isSending,
                                    onChanged: (val) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: "Template Name",
                                      prefixIcon: const Icon(Icons.code),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: primaryTeal,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: paramsCtrl,
                                    enabled: !isSending,
                                    onChanged: (val) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText:
                                          "Parameters (Optional, comma separated)",
                                      hintText: "e.g. John, 20%",
                                      prefixIcon: const Icon(Icons.data_object),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: primaryTeal,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 24),
                                  Text(
                                    "Target Audience",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: cardBorder),
                                      color: const Color(0xFFF8FAFC),
                                    ),
                                    child: Column(
                                      children: [
                                        RadioListTile<String>(
                                          title: Text(
                                            "All Contacts (${_allContacts.length})",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          value: 'All',
                                          groupValue: selectedAudienceType,
                                          activeColor: primaryTeal,
                                          onChanged: (val) => setModalState(
                                            () => selectedAudienceType = val!,
                                          ),
                                        ),
                                        if (_labels.isNotEmpty)
                                          RadioListTile<String>(
                                            title: const Text(
                                              "By Specific Label",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            value: 'Label',
                                            groupValue: selectedAudienceType,
                                            activeColor: primaryTeal,
                                            onChanged: (val) {
                                              setModalState(() {
                                                selectedAudienceType = val!;
                                                selectedLabelId = _labels
                                                    .first['name']; // default to first
                                              });
                                            },
                                          ),
                                        if (selectedAudienceType == 'Label')
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 48,
                                              right: 16,
                                              bottom: 8,
                                            ),
                                            child: DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              value: selectedLabelId,
                                              items: _labels
                                                  .map(
                                                    (
                                                      l,
                                                    ) => DropdownMenuItem<String>(
                                                      value: l['name'],
                                                      child: Text(
                                                        "${l['name']} (${l['count']} contacts)",
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (val) => setModalState(
                                                () => selectedLabelId = val,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Total Recipients for this campaign: ${targetPhones.length}",
                                    style: TextStyle(
                                      color: primaryTeal,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
                                    color: const Color(0xFFE5DDD5),
                                    borderRadius: BorderRadius.circular(16),
                                    image: const DecorationImage(
                                      image: NetworkImage(
                                        "https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png",
                                      ),
                                      fit: BoxFit.cover,
                                      opacity: 0.4,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.only(
                                              topRight: Radius.circular(12),
                                              bottomLeft: Radius.circular(12),
                                              bottomRight: Radius.circular(12),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                templateNameCtrl.text.isEmpty
                                                    ? "Enter a template name..."
                                                    : "Sending template:\n👉 ${templateNameCtrl.text}",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: textDark,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (paramsCtrl
                                                  .text
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  "With Parameters:",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: textMuted,
                                                  ),
                                                ),
                                                Text(
                                                  "[${paramsCtrl.text}]",
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.blueAccent,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
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
                          ),
                        ],
                      ),
                    ),

                    Divider(height: 1, color: cardBorder),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!isSending)
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                "Cancel",
                                style: TextStyle(
                                  color: textMuted,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryTeal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: isSending || targetPhones.isEmpty
                                ? null
                                : () async {
                                    if (templateNameCtrl.text.trim().isEmpty ||
                                        nameCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Campaign Name and Template Name are required!",
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    setModalState(() {
                                      isSending = true;
                                      sentCount = 0;
                                      failCount = 0;
                                    });

                                    List<String> paramsList =
                                        paramsCtrl.text.isNotEmpty
                                        ? paramsCtrl.text
                                              .split(',')
                                              .map((e) => e.trim())
                                              .toList()
                                        : [];

                                    // 🚀 FIRE THE BROADCAST ENGINE
                                    for (String phone in targetPhones) {
                                      bool success = await _apiService
                                          .sendTemplateMessage(
                                            restaurantId: widget.restaurantId,
                                            customerNumber: phone,
                                            templateName: templateNameCtrl.text
                                                .trim(),
                                            templateParams: paramsList,
                                          );

                                      if (success)
                                        sentCount++;
                                      else
                                        failCount++;

                                      setModalState(() {});

                                      // 🛡️ Throttling to prevent Meta rate limits! (Wait 100ms between sends)
                                      await Future.delayed(
                                        const Duration(milliseconds: 100),
                                      );
                                    }

                                    // 🚀 Save Campaign permanently to SQLite
                                    await DatabaseHelper.instance.insertCampaign(
                                      widget.restaurantId,
                                      {
                                        "name": nameCtrl.text.trim(),
                                        "template_name": templateNameCtrl.text
                                            .trim(),
                                        "audience_type": selectedAudienceType,
                                        "recipients": targetPhones.length,
                                        "status":
                                            (failCount == targetPhones.length)
                                            ? "Failed"
                                            : "Completed",
                                        "date": DateTime.now()
                                            .toIso8601String(), // Save actual timestamp
                                      },
                                    );

                                    if (mounted) {
                                      // Capture messenger BEFORE popping dialog to avoid using unmounted context
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      Navigator.pop(context);
                                      await loadData(); // Refresh UI

                                      if (failCount > 0) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Finished: $sentCount sent, $failCount failed (Check template name).",
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Campaign '${nameCtrl.text}' completed perfectly! Sent to $sentCount users.",
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: primaryTeal,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: isSending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              isSending
                                  ? "Sending (${sentCount + failCount}/${targetPhones.length})..."
                                  : "Launch Campaign",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  // =====================================================================
  // UI BUILDER
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: primaryTeal));
    }

    int totalDelivered = _campaigns
        .where((c) => c['status'] == 'Completed')
        .fold(
          0,
          (sum, c) =>
              sum + (int.tryParse(c['recipients']?.toString() ?? '0') ?? 0),
        );
    int totalFailed = _campaigns
        .where((c) => c['status'] == 'Failed')
        .fold(
          0,
          (sum, c) =>
              sum + (int.tryParse(c['recipients']?.toString() ?? '0') ?? 0),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  "Total Campaigns",
                  _campaigns.length.toString(),
                  Icons.campaign_outlined,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildSummaryCard(
                  "Messages Delivered",
                  totalDelivered.toString(),
                  Icons.mark_chat_read_outlined,
                  color: primaryTeal,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildSummaryCard(
                  "Failed Messages",
                  totalFailed.toString(),
                  Icons.error_outline,
                  color: Colors.orange,
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
                    Icon(Icons.list_alt_rounded, color: textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "All Campaigns",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textDark,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _showCreateCampaignDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    "Create Campaign",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_campaigns.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(60),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  Icon(Icons.campaign_outlined, size: 50, color: cardBorder),
                  const SizedBox(height: 16),
                  Text(
                    "No campaigns yet",
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
                itemCount: _campaigns.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 1, color: cardBorder),
                itemBuilder: (context, index) {
                  var camp = _campaigns[index];
                  bool isCompleted = camp['status'] == 'Completed';
                  bool isFailed = camp['status'] == 'Failed';

                  // Clean up the date for display
                  // 🚀 FIX: Safely parse the date to prevent Red Screen of Death
                  String displayDate = 'Unknown date';
                  try {
                    DateTime? dt = DateTime.tryParse(
                      camp['date']?.toString() ?? '',
                    );
                    if (dt != null) {
                      displayDate = "${dt.day}/${dt.month}/${dt.year}";
                    }
                  } catch (e) {}

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(color: textMuted, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                camp['name'] ?? 'Unnamed',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Sent: $displayDate",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "${camp['recipients'] ?? 0} Recipients",
                            style: TextStyle(color: textDark, fontSize: 13),
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
                                color: isCompleted
                                    ? successBg
                                    : (isFailed
                                          ? Colors.red.shade50
                                          : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                camp['status'] ?? 'Pending',
                                style: TextStyle(
                                  color: isCompleted
                                      ? successText
                                      : (isFailed
                                            ? Colors.red
                                            : Colors.grey.shade700),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            // We don't delete campaigns to maintain CRM history, but you could add a view button here later
                            const Icon(
                              Icons.history,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
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
