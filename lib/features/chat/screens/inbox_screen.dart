import 'dart:convert';
import 'package:flutter/material.dart';
import '../../marketing/services/crm_db.dart';
import '../services/chat_db.dart';

class InboxScreen extends StatefulWidget {
  final String restaurantId;
  final Function(String phone, String phoneId, String msgId) onContactSelected;
  final Function(int, String)? onUnreadCountChanged;
  final ValueNotifier<int> syncTrigger;

  const InboxScreen({
    super.key,
    required this.restaurantId,
    required this.onContactSelected,
    this.onUnreadCountChanged,
    required this.syncTrigger,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String _lastMessagesHash = "";
  String _searchQuery = "";
  String _activeFilter = "All";

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    widget.syncTrigger.addListener(_onSyncTriggered);
  }

  void _onSyncTriggered() {
    _fetchMessages(isPolling: true);
  }

  @override
  void dispose() {
    widget.syncTrigger.removeListener(_onSyncTriggered);
    super.dispose();
  }

  Future<void> _fetchMessages({bool isPolling = false}) async {
    try {
      // 🚀 Use the new Modular Chat DB Service
      final latestPerContact = await ChatDbService.instance.getAllMessages(
        widget.restaurantId,
      );

      String newHash = latestPerContact.length.toString() +
          latestPerContact.map((m) => '${m["_id"] ?? ""}:${m["createdAt"] ?? ""}').join('|');

      if (isPolling && newHash == _lastMessagesHash) return;
      _lastMessagesHash = newHash;

      if (mounted) {
        setState(() {
          _messages = latestPerContact;
          _isLoading = false;
        });
        _pushUnreadCount(latestPerContact);
      }
    } catch (e) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

bool _isUnread(Map<String, dynamic> latestMsg) {
  return ChatDbService.isContactUnread(latestMsg);   // 🚀 CHANGED
}
  bool _isSessionExpired(Map<String, dynamic> msg) {
  final String? lastInbound = msg['lastInboundTime']?.toString();
  if (lastInbound == null || lastInbound.isEmpty) return false; // no inbound ever — nothing to expire
  try {
    final DateTime inboundDt = DateTime.parse(lastInbound).toUtc();
    final Duration elapsed = DateTime.now().toUtc().difference(inboundDt);
    return elapsed.inHours >= 24;
  } catch (_) {
    return false;
  }
}

  void _pushUnreadCount(List<Map<String, dynamic>> latestPerContact) {
    final unreadMsgs = latestPerContact.where(_isUnread).toList();
    int count = unreadMsgs.length;

    String preview = "";
    if (unreadMsgs.isNotEmpty) {
      final latest = unreadMsgs.first;
      var content = latest['messageContent'];
      if (content is Map) {
        if (content['image'] != null) preview = "📷 Image";
else if (content['audio'] != null) preview = "🎵 Voice note";
else if (content['document'] != null) preview = "📄 Document";
else if (content['video'] != null) preview = "🎥 Video";
else if (content['location'] != null) preview = "📍 Location";
else if (content['order'] != null) preview = "🛒 New order";
else preview = content['text']?['body']?.toString() ?? "";
      } else {
        preview = (content ?? latest['messageText'] ?? "").toString();
      }
      String name = latest['customerName']?.toString() ?? latest['customerNumber']?.toString() ?? "";
      if (name.isNotEmpty) preview = "$name: $preview";
    }

    if (widget.onUnreadCountChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnreadCountChanged!(count, preview);
      });
    }
  }

  bool _isOutgoing(Map<String, dynamic> msg) =>
      msg['isOutgoing'] == true || msg['is_outgoing'] == true || msg['direction']?.toString().toLowerCase().contains('out') == true;

  String _msgId(Map<String, dynamic> msg) =>
      msg['_id']?.toString() ?? msg['id']?.toString() ?? msg['createdAt']?.toString() ?? '';

  String _timeAgo(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";
    try {
      DateTime date = DateTime.parse(rawDate).toLocal();
      Duration diff = DateTime.now().difference(date);
      if (diff.inDays > 1) return "${diff.inDays}d ago";
      if (diff.inDays == 1) return "1d ago";
      if (diff.inHours > 1) return "${diff.inHours}h ago";
      if (diff.inHours == 1) return "1h ago";
      if (diff.inMinutes > 1) return "${diff.inMinutes}m ago";
      if (diff.inMinutes == 1) return "1m ago";
      return "Now";
    } catch (e) {
      return "";
    }
  }

  String? _latestActivityTimestamp(Map<String, dynamic> msg) {
    final String? overall = msg['createdAt']?.toString();
    final String? lastInbound = msg['lastInboundTime']?.toString();
    DateTime? overallDt = overall != null ? DateTime.tryParse(overall) : null;
    DateTime? inboundDt = lastInbound != null ? DateTime.tryParse(lastInbound) : null;
    if (overallDt == null) return lastInbound;
    if (inboundDt == null) return overall;
    return inboundDt.isAfter(overallDt) ? lastInbound : overall;
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

  Widget _buildTopSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1))),
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
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1))),
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
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF0284C7) : const Color(0xFF4B5563)),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_isLoading && _messages.isEmpty) return const Center(child: CircularProgressIndicator());

    final List<Map<String, dynamic>> filtered = [];
    for (var msg in _messages) {
      String phone = msg['customerNumber']?.toString() ?? '';
      if (phone.isEmpty) continue;
      bool unread = _isUnread(msg);
      String name = msg['customerName']?.toString() ?? phone;
      if (name.isEmpty) name = phone;
      if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery.toLowerCase()) && !phone.contains(_searchQuery)) continue;
      if (_activeFilter == "Unread" && !unread) continue;
      filtered.add(msg);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text("${filtered.length} conversations", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text("No conversations found", style: TextStyle(color: Color(0xFF6B7280), fontSize: 16, fontWeight: FontWeight.bold)))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  itemBuilder: (context, i) {
                    
                    final msg = filtered[i];
                    final String phone = msg['customerNumber']?.toString() ?? '';
                    bool sessionExpired = _isSessionExpired(msg);
                    final bool unread = _isUnread(msg);
                    final String lastMsgId = _msgId(msg);
                    dynamic content;
                    final String? rawInbound = msg['lastInboundContent']?.toString();
                    if (rawInbound != null && rawInbound.isNotEmpty) {
                      try { content = jsonDecode(rawInbound); } catch (_) { content = rawInbound; }
                    } else {
                      content = "Tap to see messages";
                    }

                    String msgText = "💬 Message";
                    if (content is Map) {
                      if (content['image'] != null) msgText = "📷 Image";
else if (content['audio'] != null) msgText = "🎵 Voice note";
else if (content['document'] != null) msgText = "📄 Document";
else if (content['video'] != null) msgText = "🎥 Video";
else if (content['location'] != null) msgText = "📍 Location";
else if (content['order'] != null) msgText = "🛒 New order";
else if (content['text'] is Map) msgText = content['text']['body']?.toString() ?? "";
else if (content['body'] != null) msgText = content['body'].toString();
                    } else {
                      msgText = content?.toString() ?? "";
                    }

                    String name = msg['customerName']?.toString() ?? phone;
                    String initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : "U";
                    String phoneId = msg['phoneNumberId']?.toString() ?? "";
                    String timeAgo = _timeAgo(_latestActivityTimestamp(msg));
                    bool isOutgoing = _isOutgoing(msg);
                    bool previewIsInbound = rawInbound != null && rawInbound.isNotEmpty;

                  return _buildEnterpriseChatRow(phone, name, initial, msgText, unread, timeAgo, phoneId, isOutgoing, lastMsgId, previewIsInbound, sessionExpired);  // 🚀 CHANGED                  
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEnterpriseChatRow(String phone, String name, String initial, String msgText, bool hasUnread, String timeAgo, String phoneId, bool isOutgoing, String lastMsgId, bool previewIsInbound,bool sessionExpired) {
    return Material(
      color: hasUnread ? const Color(0xFFF0FDF4) : Colors.white,
      child: InkWell(
        onTap: () async {
          await CrmDbService.instance.markContactAsRead(widget.restaurantId, phone, lastMsgId);
          await _fetchMessages();
          if (mounted) widget.onContactSelected(phone, phoneId, lastMsgId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 46, height: 46, decoration: const BoxDecoration(color: Color(0xFFE5E7EB), shape: BoxShape.circle), child: Center(child: Text(initial, style: const TextStyle(fontSize: 20, color: Color(0xFF111827), fontWeight: FontWeight.w600)))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
  children: [
    Flexible(
      child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827)), maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    if (sessionExpired) ...[
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: const Text(
          "24h expired",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
        ),
      ),
    ],
  ],
),
const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(!previewIsInbound ? Icons.call_made_rounded : Icons.call_received_rounded, size: 14, color: !previewIsInbound ? const Color(0xFF9CA3AF) : const Color(0xFF3B82F6)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(msgText, style: TextStyle(fontSize: 14, color: hasUnread ? const Color(0xFF374151) : const Color(0xFF6B7280), fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(timeAgo, style: TextStyle(fontSize: 12, color: hasUnread ? const Color(0xFF10B981) : const Color(0xFF9CA3AF), fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(height: 8),
                  if (hasUnread) Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}