import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class InboxScreen extends StatefulWidget {
  final String restaurantId;
  final Function(String, String) onContactSelected;

  const InboxScreen({
    super.key,
    required this.restaurantId,
    required this.onContactSelected,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  Timer? _pollingTimer;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  // 🚀 Real Functional States
  String _searchQuery = "";
  String _activeFilter = "All"; // Can be "All" or "Unread"

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchMessages();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final url = Uri.parse('https://tym-whatsapp-backend.onrender.com/api/messages');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        List<dynamic> allMessages = [];

        if (decodedData is Map) {
          allMessages = decodedData['data'] ?? decodedData['messages'] ?? [];
        } else if (decodedData is List) {
          allMessages = decodedData;
        }

        final myMessages = allMessages.where((m) {
          String resId = m['restaurantId']?.toString() ?? m['restaurant_id']?.toString() ?? "";
          return resId == widget.restaurantId;
        }).toList();

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(myMessages);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Inbox Fetch Error: $e");
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🕒 Transforms timestamps into "56 mins ago", "1 day ago", etc.
  String _timeAgo(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";
    try {
      DateTime date = DateTime.parse(rawDate).toLocal();
      Duration diff = DateTime.now().difference(date);
      
      if (diff.inDays > 1) return "${diff.inDays} days ago";
      if (diff.inDays == 1) return "1 day ago";
      if (diff.inHours > 1) return "${diff.inHours} hrs ago";
      if (diff.inHours == 1) return "1 hr ago";
      if (diff.inMinutes > 1) return "${diff.inMinutes} mins ago";
      if (diff.inMinutes == 1) return "1 min ago";
      return "Just now";
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB), 
      body: Column(
        children: [
          _buildTopSearchBar(),
          _buildFilterBar(),
          Expanded(child: _buildChatList()),
        ],
      ),
    );
  }

  // 🔍 Fully Functional Search Bar & Refresh
  Widget _buildTopSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: "Search name or phone...",
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF), size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 🔄 Real Refresh Button
          InkWell(
            onTap: () {
              setState(() => _isLoading = true);
              _fetchMessages();
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF4B5563)),
            ),
          ),
        ],
      ),
    );
  }

  // 🎛️ Fully Functional Filters (All vs Unread)
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          _buildFilterChip("All"),
          const SizedBox(width: 12),
          _buildFilterChip("Unread"),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isActive = _activeFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE0F2FE) : const Color(0xFFF3F4F6), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? const Color(0xFFBAE6FD) : Colors.transparent),
        ),
        child: Text(
          label, 
          style: TextStyle(
            fontSize: 13, 
            fontWeight: FontWeight.bold,
            color: isActive ? const Color(0xFF0284C7) : const Color(0xFF4B5563)
          )
        ),
      ),
    );
  }

  // 📋 Filtered Chat List
  Widget _buildChatList() {
    if (_isLoading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
    }

    final Map<String, Map<String, dynamic>> latestChats = {};
    final Map<String, int> unreadCounts = {};
    final Map<String, bool> hasSeenOutgoing = {};

    for (var msg in _messages.reversed) {
      String phone = msg['customerNumber']?.toString() ?? msg['customer_number']?.toString() ?? "";
      if (phone.isEmpty) continue;

      bool isOutgoing = msg['isOutgoing'] == true || msg['is_outgoing'] == true || msg['direction']?.toString().toLowerCase().contains('out') == true;

      if (!latestChats.containsKey(phone)) {
        latestChats[phone] = msg;
        unreadCounts[phone] = 0;
        hasSeenOutgoing[phone] = false;
      }

      if (!hasSeenOutgoing[phone]! && !isOutgoing) {
        unreadCounts[phone] = unreadCounts[phone]! + 1;
      } else if (isOutgoing) {
        hasSeenOutgoing[phone] = true;
      }
    }

    // 🚀 APPLY REAL FILTERS & SEARCH
    List<String> filteredContacts = latestChats.keys.where((phone) {
      final lastMsg = latestChats[phone]!;
      String name = lastMsg['customerName']?.toString() ?? phone;
      if (name.isEmpty) name = phone;
      
      int unreads = unreadCounts[phone] ?? 0;

      // 1. Check Search Query
      if (_searchQuery.isNotEmpty) {
        if (!name.toLowerCase().contains(_searchQuery.toLowerCase()) && !phone.contains(_searchQuery)) {
          return false; // Hide if it doesn't match search
        }
      }

      // 2. Check Active Tab Filter
      if (_activeFilter == "Unread" && unreads == 0) {
        return false; // Hide read messages if "Unread" tab is active
      }

      return true;
    }).toList();

    if (filteredContacts.isEmpty) {
      return const Center(child: Text("No conversations found.", style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.bold)));
    }

    return ListView.separated(
      itemCount: filteredContacts.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
      itemBuilder: (context, i) {
        final phone = filteredContacts[i];
        final lastMsg = latestChats[phone]!;
        final int unreads = unreadCounts[phone] ?? 0;

        String msgText = lastMsg['messageContent'] is Map
            ? (lastMsg['messageContent']['text']?['body'] ?? "[Media/Interactive]") 
            : (lastMsg['messageContent'] ?? lastMsg['messageText'] ?? "No messages yet");
            
        if (msgText.contains("templateName")) msgText = "[Campaign Message]";
        if (lastMsg['messageContent'] is Map && lastMsg['messageContent']['location'] != null) msgText = "📍 Location";

        String name = lastMsg['customerName']?.toString() ?? phone;
        if (name.isEmpty) name = phone;
        
        String initial = name.replaceAll(RegExp(r'[^a-zA-Z]'), ''); 
        initial = initial.isNotEmpty ? initial[0].toUpperCase() : "U";

        String phoneId = lastMsg['phoneNumberId']?.toString() ?? ""; 
        String timeAgo = _timeAgo(lastMsg['createdAt']?.toString() ?? lastMsg['created_at']?.toString());

        return _buildEnterpriseChatRow(phone, name, initial, msgText, unreads, timeAgo, phoneId);
      }
    );
  }

  // 🏢 Chat Row UI
  Widget _buildEnterpriseChatRow(String phone, String name, String initial, String msgText, int unreadCount, String timeAgo, String phoneId) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => widget.onContactSelected(phone, phoneId),
        hoverColor: const Color(0xFFF9FAFB),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: Stack(
                  children: [
                    Container(
                      width: 46, height: 46,
                      decoration: const BoxDecoration(color: Color(0xFFE5E7EB), shape: BoxShape.circle),
                      child: Center(
                        child: Text(initial, style: const TextStyle(fontSize: 20, color: Color(0xFF111827), fontWeight: FontWeight.w600)),
                      ),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFF10B981), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.chat_bubble_rounded, size: 10, color: Colors.white), 
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      msgText,
                      style: TextStyle(fontSize: 14, color: unreadCount > 0 ? const Color(0xFF374151) : const Color(0xFF6B7280), fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w400),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("TYM", style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Text(timeAgo, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}