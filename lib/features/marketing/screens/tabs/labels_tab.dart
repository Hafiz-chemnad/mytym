import 'package:flutter/material.dart';
import '../../services/crm_db.dart';
import '../../services/label_api.dart';

class LabelsTab extends StatefulWidget {
  final String restaurantId;
  const LabelsTab({super.key, required this.restaurantId});

  @override
  State<LabelsTab> createState() => LabelsTabState();
}

class LabelsTabState extends State<LabelsTab> {
  bool _isLoading = false;
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
    loadLabels();
  }

  Future<void> loadLabels() async {
  // 1️⃣ Show cached local data immediately.
  final cachedLabels = await CrmDbService.instance.getAllLabels(widget.restaurantId);
  if (mounted) {
    setState(() {
      _labels = cachedLabels;
      _isLoading = false;
    });
  }

  // 2️⃣ Refresh from Mongo in the background.
  try {
    await LabelApi.instance.refreshLabels(widget.restaurantId);
    await CrmDbService.instance.cleanupOrphanedLabels(widget.restaurantId);
    await CrmDbService.instance.recalculateLabelCounts(widget.restaurantId);

    final freshLabels = await CrmDbService.instance.getAllLabels(widget.restaurantId);
    if (mounted) {
      setState(() {
        _labels = freshLabels;
      });
    }
  } catch (e) {
    // offline/backend down — cached data already shown, no crash
  }
}

  /// 🚀 PERF FIX: called after a single create/edit/delete. The write call
  /// itself already updated local SQLite with the authoritative backend
  /// response — there's no need to hit the network again or re-run the
  /// full cleanup/recalculate sweep for a change that touched one row.
  /// This is what was making every label action feel slow: a full
  /// network refresh + O(labels × contacts) recompute after every single
  /// write. loadLabels() (the heavy version) still runs once when the
  /// tab first opens, where a full resync genuinely is appropriate.
  Future<void> _reloadFromCache() async {
    final labels = await CrmDbService.instance.getAllLabels(widget.restaurantId);
    if (mounted) setState(() => _labels = labels);
  }

  void _showCreateOrEditLabelDialog({int? index}) {
    bool isEditing = index != null;
    TextEditingController nameCtrl = TextEditingController(text: isEditing ? _labels[index]['name'] : "");
    TextEditingController descCtrl = TextEditingController(text: isEditing ? _labels[index]['description'] : "");

    if (isEditing && _labels[index]['is_automated'] == 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Automated Smart Labels cannot be edited manually.")));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500, padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEditing ? "Edit Label" : "Create New Label", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                const SizedBox(height: 24),
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Label Name", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)))),
                const SizedBox(height: 16),
                TextField(controller: descCtrl, decoration: InputDecoration(labelText: "Description", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryTeal, width: 2)))),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold))), const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) return;

                        final String desc = descCtrl.text.trim().isEmpty ? "No description" : descCtrl.text.trim();
                        String result;

                        if (isEditing) {
                          result = await LabelApi.instance.updateLabel(widget.restaurantId, _labels[index]['id'], nameCtrl.text.trim(), desc);
                        } else {
                          String newId = 'lbl_${DateTime.now().millisecondsSinceEpoch}';
                          final success = await LabelApi.instance.createLabel(widget.restaurantId, newId, nameCtrl.text.trim(), desc);
                          result = success ? 'ok' : 'error';
                        }

                        if (result == 'forbidden') {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Automated Smart Labels cannot be edited manually.")));
                          return;
                        }
                        if (result == 'error') {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to save \u2014 check connection.")));
                          return;
                        }

                        await _reloadFromCache();
                        if (mounted) Navigator.pop(context);
                      },
                      child: Text(isEditing ? "Update Label" : "Save Label", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteLabel(int index) {
    if (_labels[index]['is_automated'] == 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Automated Smart Labels cannot be deleted manually.")));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Label?"),
        content: const Text("Are you sure you want to delete this label? The tag will also be removed from all contacts."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final result = await LabelApi.instance.deleteLabel(widget.restaurantId, _labels[index]['id']);

              if (result == 'forbidden') {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Automated Smart Labels cannot be deleted manually.")));
                }
                return;
              }
              if (result == 'error') {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete \u2014 check connection.")));
                }
                return;
              }

              await _reloadFromCache();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: primaryTeal));

    int totalLabelAssignments = _labels.fold(0, (sum, item) => sum + (int.tryParse(item['count']?.toString() ?? '0') ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSummaryCard("Total Labels", _labels.length.toString(), Icons.label_outline)), const SizedBox(width: 24),
              Expanded(child: _buildSummaryCard("Label Assignments", totalLabelAssignments.toString(), Icons.people_alt_outlined, color: primaryTeal)),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [Icon(Icons.local_offer_outlined, color: textMuted, size: 20), const SizedBox(width: 8), Text("Organize and manage your contact labels", style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 16))]),
                ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () => _showCreateOrEditLabelDialog(), icon: const Icon(Icons.add, size: 18), label: const Text("Create Label", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_labels.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(60), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)), child: Column(children: [Icon(Icons.label_off_outlined, size: 50, color: cardBorder), const SizedBox(height: 16), Text("No labels created yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark))]))
          else
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
              child: ListView.separated(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _labels.length, separatorBuilder: (context, index) => Divider(height: 1, color: cardBorder),
                itemBuilder: (context, index) {
                  var label = _labels[index];
                  bool isAuto = label['is_automated'] == 1;

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
                              Row(
                                children: [
                                  Text(label['name'], style: TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 15)),
                                  if (isAuto) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple.shade200)), child: Text("AUTO", style: TextStyle(fontSize: 9, color: Colors.purple.shade700, fontWeight: FontWeight.bold)))],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(label['description'], style: TextStyle(fontSize: 12, color: textMuted)),
                            ],
                          ),
                        ),
                        Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: successBg, borderRadius: BorderRadius.circular(12)), child: Text("${label['count']} contacts", style: TextStyle(color: successText, fontSize: 12, fontWeight: FontWeight.bold))))),
                        Row(
                          children: [
                            IconButton(icon: Icon(Icons.edit_outlined, color: isAuto ? Colors.grey.shade300 : textMuted, size: 20), onPressed: () => _showCreateOrEditLabelDialog(index: index)),
                            IconButton(icon: Icon(Icons.delete_outline, color: isAuto ? Colors.grey.shade300 : Colors.red.shade300, size: 20), onPressed: () => _confirmDeleteLabel(index)),
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