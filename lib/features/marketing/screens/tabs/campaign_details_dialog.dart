import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // 🚀 NEW IMPORT
import '../../../../core/network/crm_api_client.dart'; // 🚀 NEW IMPORT

class CampaignDetailsDialog extends StatefulWidget {
  final String restaurantId;
  final Map<String, dynamic> initialCampaign;

  const CampaignDetailsDialog({super.key, required this.restaurantId, required this.initialCampaign});

  @override
  State<CampaignDetailsDialog> createState() => _CampaignDetailsDialogState();
}

class _CampaignDetailsDialogState extends State<CampaignDetailsDialog> {
  bool _isLoading = true;
  Map<String, dynamic> _campaign = {};
  List<dynamic> _recipients = [];

  final Color primaryTeal = const Color(0xFF096A56);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);

  @override
  void initState() {
    super.initState();
    _campaign = widget.initialCampaign;
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    String safeId = widget.initialCampaign['campaign_id']?.toString() ?? widget.initialCampaign['id']?.toString() ?? '';

    // 🚀 THE FIX: A direct, raw HTTP call to bypass any SQLite parsing errors!
    try {
      final url = Uri.parse('${CrmApiClient.baseUrl}/api/${widget.restaurantId}/campaigns/$safeId');
      final response = await http.get(url, headers: CrmApiClient.defaultHeaders);

      if (response.statusCode == 200) {
        final detail = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _campaign = detail;
            if (detail['recipients'] is List) {
              _recipients = detail['recipients'];
            }
            _isLoading = false;
          });
        }
        return; // Success! Exit early.
      } else {
        // If Python fails, tell us exactly why!
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Backend Error: ${response.statusCode}. Please check Python logs."), backgroundColor: Colors.red)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Network Error: $e"), backgroundColor: Colors.red)
        );
      }
    }

    // Fallback if HTTP fails
    if (mounted) {
      setState(() {
        if (_campaign['recipients_json'] != null) {
          try {
            _recipients = jsonDecode(_campaign['recipients_json']);
          } catch (e) {}
        }
        _isLoading = false;
      });
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(color: textDark, fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int total = int.tryParse(_campaign['recipients_count']?.toString() ?? '0') ?? 0;
    if (total == 0) total = int.tryParse(_campaign['recipients']?.toString() ?? '0') ?? _recipients.length;
    
    int sent = int.tryParse(_campaign['sent_count']?.toString() ?? '0') ?? 0;
    int failed = int.tryParse(_campaign['failed_count']?.toString() ?? '0') ?? 0;
    
    String deliveryRate = total > 0 ? ((sent / total) * 100).toStringAsFixed(1) : "0.0";
    String failureRate = total > 0 ? ((failed / total) * 100).toStringAsFixed(1) : "0.0";

    String displayDate = _campaign['created_at']?.toString() ?? _campaign['date']?.toString() ?? '-';
    if (displayDate.contains('T')) displayDate = displayDate.split('T').first;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1000,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text("Campaign: ${_campaign['name'] ?? 'Details'}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textDark)),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Text(_campaign['status']?.toString().toUpperCase() ?? 'UNKNOWN', style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              // METADATA GRID
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Template", style: TextStyle(color: textMuted, fontSize: 12)), const SizedBox(height: 4), Text(_campaign['template_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Audience Type", style: TextStyle(color: textMuted, fontSize: 12)), const SizedBox(height: 4), Text(_campaign['audience_type'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Created At", style: TextStyle(color: textMuted, fontSize: 12)), const SizedBox(height: 4), Text(displayDate, style: const TextStyle(fontWeight: FontWeight.bold))]),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // STATS CARDS
              Row(
                children: [
                  _buildStatCard("Recipients", total.toString(), Icons.people_outline, Colors.blue),
                  const SizedBox(width: 16),
                  _buildStatCard("Messages Sent", sent.toString(), Icons.send_outlined, primaryTeal),
                  const SizedBox(width: 16),
                  _buildStatCard("Delivery Rate", "$deliveryRate%", Icons.check_circle_outline, Colors.green),
                  const SizedBox(width: 16),
                  _buildStatCard("Failure Rate", "$failureRate%", Icons.cancel_outlined, Colors.red),
                ],
              ),
              const SizedBox(height: 32),

              // TARGET AUDIENCE TABLE
              Text("Target Audience", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
              const SizedBox(height: 16),
              
              Expanded(
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      // Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                        child: Row(
                          children: [
                            Expanded(flex: 2, child: Text("PHONE", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold, fontSize: 12))),
                            Expanded(flex: 2, child: Text("STATUS", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold, fontSize: 12))),
                            Expanded(flex: 3, child: Text("STATUS DESCRIPTION", style: TextStyle(color: textMuted, fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Table Body
                      Expanded(
                        child: _recipients.isEmpty
                            ? Center(child: Text("No detailed records found. (Check internet connection)", style: TextStyle(color: textMuted)))
                            : ListView.separated(
                                itemCount: _recipients.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  var rec = _recipients[index];
                                  String phone = rec['phone']?.toString() ?? '';
                                  String maskedPhone = phone.length > 4 ? "******${phone.substring(phone.length - 4)}" : phone;
                                  String status = rec['status']?.toString() ?? 'pending';
                                  String error = rec['error']?.toString() ?? '—';

                                  Color statusColor = status == 'delivered' || status == 'sent' ? Colors.green : (status == 'failed' ? Colors.red : Colors.orange);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    child: Row(
                                      children: [
                                        Expanded(flex: 2, child: Text(maskedPhone, style: const TextStyle(fontWeight: FontWeight.w500))),
                                        Expanded(
                                          flex: 2, 
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                                child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                          )
                                        ),
                                        Expanded(flex: 3, child: Text(error, style: TextStyle(color: textMuted, fontSize: 13))),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ],
        ),
      ),
    );
  }
}