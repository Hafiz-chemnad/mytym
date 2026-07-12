import 'package:flutter/material.dart';
import '../../services/template_api.dart';
import '../../services/template_db.dart';
import '../../../settings/services/settings_db_service.dart'; // Adjust path based on your folder structure

class TemplatesTab extends StatefulWidget {
  final String restaurantId;
  const TemplatesTab({super.key, required this.restaurantId});

  @override
  State<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<TemplatesTab> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _templates = [];

  final Color primaryTeal = const Color(0xFF096A56);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);

  @override
  void initState() {
    super.initState();
    _loadLocalTemplates();
  }

  Future<void> _loadLocalTemplates() async {
    final cached = await TemplateDbService.instance.getAllTemplates(widget.restaurantId);
    if (mounted) {
      setState(() {
        _templates = cached;
      });
    }
  }

  Future<void> _refreshFromMeta() async {
    setState(() => _isLoading = true);
    
    // Grab Meta credentials from Settings
    final settings = await SettingsDbService.instance.getSettings();
    final wabaId = settings?['wabaId']?.toString() ?? ''; // 🚀 Changed here
    final token = settings?['waToken']?.toString() ?? '';

    if (wabaId.isNotEmpty && token.isNotEmpty) {
      await TemplateApi.instance.refreshTemplateStatus(widget.restaurantId, wabaId, token);
      await _loadLocalTemplates();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Missing Meta credentials in Settings.")),
        );
      }
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  // lib/ui/templates/templates_tab.dart

  void _showCreateTemplateDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController bodyCtrl = TextEditingController();
    TextEditingController headerTextCtrl = TextEditingController(); // 🚀 ADDED
    
    String selectedCategory = 'MARKETING';
    String selectedLanguage = 'en_US';
    String selectedHeaderType = 'NONE'; // 🚀 ADDED
    bool isSubmitting = false;
    List<Map<String, dynamic>> buttonsList = []; // 🚀 ADDED: {type, text, url/phone_number}
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 600,
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Create Meta Template", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                          if (!isSubmitting) IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: nameCtrl,
                        enabled: !isSubmitting,
                        decoration: InputDecoration(
                          labelText: "Template Name (lowercase, no spaces)",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 🚀 NEW DROPDOWN: HEADER SELECTION RUNTIME BLOCK
                      DropdownButtonFormField<String>(
                        value: selectedHeaderType,
                        decoration: InputDecoration(labelText: "Header Type", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                        items: const [
                          DropdownMenuItem(value: 'NONE', child: Text("None (Text starts immediately)")),
                          DropdownMenuItem(value: 'TEXT', child: Text("Text (Bold Title)")),
                          DropdownMenuItem(value: 'IMAGE', child: Text("Image Media asset")),
                          DropdownMenuItem(value: 'VIDEO', child: Text("Video Media asset")),
                          DropdownMenuItem(value: 'DOCUMENT', child: Text("Document PDF/File asset")),
                        ],
                        onChanged: isSubmitting ? null : (val) => setModalState(() => selectedHeaderType = val!),
                      ),
                      const SizedBox(height: 16),

                      // 🚀 CONDITIONAL TEXT FIELD FOR TEXT HEADER
                      if (selectedHeaderType == 'TEXT') ...[
                        TextField(
                          controller: headerTextCtrl,
                          enabled: !isSubmitting,
                          maxLength: 60, // Meta max characters for text header
                          decoration: InputDecoration(
                            labelText: "Header Text Title",
                            hintText: "Order Alert!",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedCategory,
                              decoration: InputDecoration(labelText: "Category", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              items: const [
                                DropdownMenuItem(value: 'MARKETING', child: Text("Marketing")),
                                DropdownMenuItem(value: 'UTILITY', child: Text("Utility")),
                                DropdownMenuItem(value: 'AUTHENTICATION', child: Text("Authentication")),
                              ],
                              onChanged: isSubmitting ? null : (val) => setModalState(() => selectedCategory = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedLanguage,
                              decoration: InputDecoration(labelText: "Language", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              items: const [
                                DropdownMenuItem(value: 'en_US', child: Text("English (US)")),
                                DropdownMenuItem(value: 'en_GB', child: Text("English (UK)")),
                              ],
                              onChanged: isSubmitting ? null : (val) => setModalState(() => selectedLanguage = val!),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      TextField(
                        controller: bodyCtrl,
                        enabled: !isSubmitting,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: "Message Body",
                          hintText: "Hi {{1}}! Enjoy {{2}}% off today.",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
Text("Buttons (optional)", style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 14)),
const SizedBox(height: 8),
...buttonsList.asMap().entries.map((entry) {
  int idx = entry.key;
  Map<String, dynamic> btn = entry.value;
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(8)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: btn['type'],
                isDense: true,
                decoration: const InputDecoration(labelText: "Type", isDense: true),
                items: const [
                  DropdownMenuItem(value: 'QUICK_REPLY', child: Text("Quick Reply")),
                  DropdownMenuItem(value: 'URL', child: Text("URL / Website")),
                  DropdownMenuItem(value: 'PHONE_NUMBER', child: Text("Phone Number")),
                ],
                onChanged: isSubmitting ? null : (val) => setModalState(() => btn['type'] = val),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: isSubmitting ? null : () => setModalState(() => buttonsList.removeAt(idx)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: btn['text'],
          enabled: !isSubmitting,
          decoration: const InputDecoration(labelText: "Button Text", isDense: true),
          onChanged: (val) => btn['text'] = val,
        ),
        if (btn['type'] == 'URL') ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: btn['url'],
            enabled: !isSubmitting,
            decoration: const InputDecoration(labelText: "URL (use {{1}} for dynamic value)", hintText: "https://example.com/order/{{1}}", isDense: true),
            onChanged: (val) => btn['url'] = val,
          ),
        ],
        if (btn['type'] == 'PHONE_NUMBER') ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: btn['phone_number'],
            enabled: !isSubmitting,
            decoration: const InputDecoration(labelText: "Phone Number (+countrycode)", isDense: true),
            onChanged: (val) => btn['phone_number'] = val,
          ),
        ],
      ],
    ),
  );
}).toList(),
Row(
  children: [
    OutlinedButton.icon(
      onPressed: isSubmitting || buttonsList.where((b) => b['type'] == 'QUICK_REPLY').length >= 3
        ? null
        : () => setModalState(() => buttonsList.add({'type': 'QUICK_REPLY', 'text': ''})),
      icon: const Icon(Icons.add, size: 16),
      label: const Text("Quick Reply"),
    ),
    const SizedBox(width: 8),
    OutlinedButton.icon(
      onPressed: isSubmitting || buttonsList.where((b) => b['type'] == 'URL').length >= 2
        ? null
        : () => setModalState(() => buttonsList.add({'type': 'URL', 'text': '', 'url': ''})),
      icon: const Icon(Icons.add, size: 16),
      label: const Text("URL"),
    ),
    const SizedBox(width: 8),
    OutlinedButton.icon(
      onPressed: isSubmitting || buttonsList.where((b) => b['type'] == 'PHONE_NUMBER').length >= 1
        ? null
        : () => setModalState(() => buttonsList.add({'type': 'PHONE_NUMBER', 'text': '', 'phone_number': ''})),
      icon: const Icon(Icons.add, size: 16),
      label: const Text("Phone"),
    ),
  ],
),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, padding: const EdgeInsets.symmetric(vertical: 16)),
                          onPressed: isSubmitting ? null : () async {
                            String name = nameCtrl.text.trim();
                            String body = bodyCtrl.text.trim();

                            if (name.isEmpty || body.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name and Body are required.")));
                              return;
                            }

                            setModalState(() => isSubmitting = true);
                            final settings = await SettingsDbService.instance.getSettings();
                            final wabaId = settings?['wabaId']?.toString() ?? '';
                            final token = settings?['waToken']?.toString() ?? '';

                            // 🚀 TRANSMIT WITH THE NEW HEADER PROPERTIES
                            bool success = await TemplateApi.instance.createTemplate(
                              widget.restaurantId,
                              wabaId: wabaId,
                              accessToken: token,
                              name: name,
                              category: selectedCategory,
                              language: selectedLanguage,
                              bodyText: body,
                              headerType: selectedHeaderType, // 🚀 PASSED
                              headerText: selectedHeaderType == 'TEXT' ? headerTextCtrl.text.trim() : null, 
                              buttons: buttonsList.isNotEmpty ? buttonsList : null,   // 🚀 ADDED// 🚀 PASSED
                            );

                            if (mounted) {
                              if (success) {
                                Navigator.pop(context);
                                await _refreshFromMeta();
                              } else {
                                setModalState(() => isSubmitting = false);
                              }
                            }
                          },
                          child: isSubmitting 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Text("Submit to Meta", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  void _confirmDelete(String templateName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Template?"),
        content: Text("This will permanently delete '$templateName' from your Meta account."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              final settings = await SettingsDbService.instance.getSettings();
              final wabaId = settings?['wabaId']?.toString() ?? ''; // 🚀 Changed here
              final token = settings?['waToken']?.toString() ?? '';

              bool success = await TemplateApi.instance.deleteTemplate(widget.restaurantId, templateName, wabaId, token);
              
              if (mounted) {
                if (success) {
                  await _loadLocalTemplates();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Template deleted.")));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete template.")));
                }
              }
              setState(() => _isLoading = false);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Message Templates", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textDark)),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _refreshFromMeta,
                    icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 18),
                    label: const Text("Sync Status"),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white),
                    onPressed: _showCreateTemplateDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Create Template", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text("Templates usually take a few hours to be reviewed by Meta, but can sometimes take up to 2 days.", style: TextStyle(color: textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          
          Expanded(
            child: _templates.isEmpty && !_isLoading
              ? Center(child: Text("No templates found. Create one to get started.", style: TextStyle(color: textMuted, fontSize: 16)))
              : ListView.separated(
                  itemCount: _templates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final t = _templates[index];
                    final String status = t['status']?.toString().toUpperCase() ?? 'PENDING';
                    
                    Color statusColor = Colors.orange;
                    if (status == 'APPROVED') statusColor = Colors.green;
                    if (status == 'REJECTED') statusColor = Colors.red;

                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(t['name'] ?? 'Unknown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark)),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                    child: Text(t['category'] ?? 'UNKNOWN', style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _confirmDelete(t['name']),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (status == 'REJECTED' && t['rejected_reason'] != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text("Reason: ${t['rejected_reason']}", style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                          Text(t['body_text'] ?? '', style: TextStyle(color: textMuted, fontSize: 14)),
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
}