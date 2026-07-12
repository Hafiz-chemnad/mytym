import 'package:flutter/material.dart';
import 'tabs/contacts_tab.dart';
import 'tabs/labels_tab.dart';
import 'tabs/campaigns_tab.dart';
import 'tabs/templates_tab.dart'; // 🚀 ADDED: Import new tab

class MarketingScreen extends StatefulWidget {
  final String restaurantId;
  const MarketingScreen({super.key, required this.restaurantId});

  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  int _selectedTabIndex = 0;

  final GlobalKey<ContactsTabState> _contactsKey = GlobalKey<ContactsTabState>();
  final GlobalKey<LabelsTabState> _labelsKey = GlobalKey<LabelsTabState>();
  final GlobalKey<CampaignsTabState> _campaignsKey = GlobalKey<CampaignsTabState>();
  // Templates tab doesn't strictly need a GlobalKey right now, but added for consistency

  final Color primaryTeal = const Color(0xFF096A56);
  final Color bgLight = const Color(0xFFF2F7F4);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);

  void _onTabTap(int index) {
    setState(() => _selectedTabIndex = index);

    if (index == 0) _contactsKey.currentState?.loadData();
    if (index == 1) _labelsKey.currentState?.loadLabels();
    if (index == 2) _campaignsKey.currentState?.loadData();
  }

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
                Text("Manage your WhatsApp contacts, automated labels, templates, and broadcast campaigns.", style: TextStyle(color: textMuted, fontSize: 13)),
              ],
            ),
          ),
          Divider(height: 1, color: cardBorder),

          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cardBorder, width: 1)), color: Colors.white),
            child: Row(
              children: [
                _buildTab(0, "Contacts"),
                _buildTab(1, "Labels"),
                _buildTab(2, "Campaigns"),
                _buildTab(3, "Templates"), // 🚀 ADDED: New Tab Button
              ],
            ),
          ),

          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                ContactsTab(key: _contactsKey, restaurantId: widget.restaurantId),
                LabelsTab(key: _labelsKey, restaurantId: widget.restaurantId),
                CampaignsTab(key: _campaignsKey, restaurantId: widget.restaurantId),
                TemplatesTab(restaurantId: widget.restaurantId), // 🚀 ADDED: New Tab View
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String title) {
    bool isActive = _selectedTabIndex == index;
    return InkWell(
      onTap: () => _onTabTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? primaryTeal : Colors.transparent, width: 3))),
        child: Text(title, style: TextStyle(color: isActive ? primaryTeal : textMuted, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }
}