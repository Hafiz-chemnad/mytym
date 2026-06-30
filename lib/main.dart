import 'dart:io';
import 'dart:async'; // 🚀 Added for Timer
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

// --- Screen Imports ---
import 'package:whatsapp_erp_api/screens/login_screen.dart';
import 'package:whatsapp_erp_api/screens/inbox_screen.dart';
import 'package:whatsapp_erp_api/screens/chat_detail_screen.dart';
import 'package:whatsapp_erp_api/screens/live_orders_screen.dart';
import 'package:whatsapp_erp_api/screens/menu_management_screen.dart';
import 'package:whatsapp_erp_api/screens/marketing/marketing_screen.dart';
import 'package:whatsapp_erp_api/screens/settings_screen.dart';
import 'package:whatsapp_erp_api/services/api_service.dart';
import 'package:whatsapp_erp_api/services/database_helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        fontFamily: 'Roboto',
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Segoe UI Symbol',
          'Noto Color Emoji',
        ],
      ),
      home: FutureBuilder<String?>(
        future: DatabaseHelper.instance.getSessionRestaurantId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final savedId = snapshot.data;
          return (savedId != null)
              ? DashboardScreen(restaurantId: savedId)
              : const LoginScreen();
        },
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final String restaurantId;
  const DashboardScreen({super.key, required this.restaurantId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();

  // 🚀 1. THE MASTER TRIGGER (ഇതാണ് മറ്റ് സ്ക്രീനുകൾക്ക് സിഗ്നൽ കൊടുക്കുന്നത്)
  final ValueNotifier<int> _globalSyncTrigger = ValueNotifier<int>(0);
  Timer? _masterTimer;

  // ── UI State ──────────────────────────────────────────────
  bool _isSidebarOpen = false;
  int _unreadCount = 0;
  String _latestUnreadPreview = "";
  int _selectedMenuIndex = 0;

  // 🚀 FIX: Single read-cache shared between badge counter (_refreshUnreadBadge)
  // and InboxScreen's onTap. When a user taps a contact the entry is added here
  // and _refreshUnreadBadge immediately sees it and clears the badge.

  // ── Chat / Sidebar State ──────────────────────────────────
  String _sidebarView = "inbox";
  String? _selectedNumber;
  String? _selectedPhoneId;
  String _restaurantPhoneId = "";

  // 🎨 POS Theme Colors
  static const Color primaryTeal = Color(0xFF096A56);
  static const Color textMuted = Color(0xFF6B7A75);
  static const Color textDark = Color(0xFF1B2420);

  int get _stackIndex =>
      _selectedMenuIndex.clamp(0, 3); // 🚀 Only 4 screens now

  @override
  void initState() {
    super.initState();
    _fetchRestaurantDetails();
    _startMasterLoop(); // 🚀 2. START THE ENGINE
  }

  @override
  void dispose() {
    _masterTimer?.cancel(); // 🚀 Kill timer when app closes
    _globalSyncTrigger.dispose();
    super.dispose();
  }

  // 🚀 3. THE MASTER LOOP: (എല്ലാ പശ്ചാത്തല പ്രവർത്തനങ്ങളും ഇവിടെ നടക്കും)
  void _startMasterLoop() {
    // Run once immediately on launch so the badge shows right away
    _refreshUnreadBadge();

    // 6 സെക്കൻഡ് കൂടുമ്പോൾ ഓർഡറും മെസ്സേജും ചെക്ക് ചെയ്യും
    _masterTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _apiService.syncMessagesBackground(widget.restaurantId);
      await _apiService.syncOrdersBackground(widget.restaurantId);

      // ഡാറ്റ വന്നാൽ മറ്റ് സ്ക്രീനുകളെ അറിയിക്കാൻ വാല്യൂ കൂട്ടുന്നു
      _globalSyncTrigger.value++;

      // 🚀 FIX: Always refresh the badge from DB, regardless of sidebar state.
      // Previously the badge only updated when InboxScreen was alive (sidebar open).
      await _refreshUnreadBadge();
    });
  }

  /// Counts unread messages directly from SQLite.
  /// "Unread" = latest message for a contact is inbound AND its msg_id is not
  /// in our local _readCache (same logic as InboxScreen._isUnread).
  // Find the entire _refreshUnreadBadge method and replace it:
  Future<void> _refreshUnreadBadge() async {
    try {
      final latestPerContact = await DatabaseHelper.instance.getAllMessages(
        widget.restaurantId,
      );

      int count = 0;
      String preview = "";

      for (final msg in latestPerContact) {
        final String? lastInbound = msg['lastInboundTime']?.toString();
        if (lastInbound == null || lastInbound.isEmpty) continue;

        final String? readAt = msg['contactReadAt']?.toString();
        bool isUnread;
        if (readAt == null || readAt.isEmpty) {
          isUnread = true;
        } else {
          try {
            isUnread = DateTime.parse(
              lastInbound,
            ).toUtc().isAfter(DateTime.parse(readAt).toUtc());
          } catch (_) {
            isUnread = false;
          }
        }
        if (!isUnread) continue;

        count++;
        if (preview.isEmpty) {
          // Always use lastInboundContent for preview — never outbound message
          dynamic content;
          final String? rawInboundContent = msg['lastInboundContent']
              ?.toString();
          if (rawInboundContent != null && rawInboundContent.isNotEmpty) {
            try {
              content = jsonDecode(rawInboundContent);
            } catch (_) {
              content = rawInboundContent;
            }
          }

          String text = "";
          if (content is Map) {
            if (content['image'] != null)
              text = "📷 Image";
            else if (content['audio'] != null)
              text = "🎵 Voice note";
            else if (content['document'] != null)
              text = "📄 Document";
            else if (content['video'] != null)
              text = "🎥 Video";
            else if (content['text'] is Map)
              text = content['text']['body']?.toString() ?? "";
            else if (content['body'] != null)
              text = content['body'].toString();
            else if (content['button'] is Map)
              text = "🔘 ${content['button']['text'] ?? 'Button'}";
            else if (content['interactive'] is Map) {
              final inter = content['interactive'];
              if (inter['button_reply'] != null)
                text = "🔘 ${inter['button_reply']['title'] ?? ''}";
              else if (inter['list_reply'] != null)
                text = "📋 ${inter['list_reply']['title'] ?? ''}";
            }
          } else if (content is String && content.isNotEmpty) {
            text = content;
          }

          // If we still have no text, show a generic label
          if (text.isEmpty) text = "💬 New message";

          final String customerPhone = msg['customerNumber']?.toString() ?? '';
          final String name = msg['customerName']?.toString() ?? customerPhone;
          preview = name.isNotEmpty ? "$name: $text" : text;
        }
      }

      if (mounted &&
          (_unreadCount != count || _latestUnreadPreview != preview)) {
        setState(() {
          _unreadCount = count;
          _latestUnreadPreview = preview;
        });
      }
    } catch (e) {
      print("❌ Badge refresh error: $e");
    }
  }

  Future<void> _fetchRestaurantDetails() async {
    final profile = await _apiService.fetchRestaurantProfile(
      widget.restaurantId,
    );
    if (profile != null && mounted) {
      setState(() {
        _restaurantPhoneId = profile['phoneNumberId']?.toString() ?? "";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          _buildTopNavigationBar(),
          Expanded(
            child: Stack(
              children: [
                _buildMainContent(),

                // 🚀 Tap outside the sidebar to close it
                if (_isSidebarOpen)
                  Positioned.fill(
                    right: 450, // only covers the area LEFT of the sidebar
                    child: GestureDetector(
                      onTap: () => setState(() => _isSidebarOpen = false),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),

                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isSidebarOpen ? 450 : 0,
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        if (_isSidebarOpen)
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 15,
                            offset: const Offset(-5, 0),
                          ),
                      ],
                    ),
                    child: _isSidebarOpen
                        ? _buildSidebarContent()
                        : const SizedBox.shrink(),
                  ),
                ),

                Positioned(
                  bottom: 20,
                  right: _isSidebarOpen ? 470 : 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🚀 FIX: Show latest unread message preview above the FAB
                      if (_unreadCount > 0 &&
                          _latestUnreadPreview.isNotEmpty &&
                          !_isSidebarOpen)
                        GestureDetector(
                          onTap: () => setState(() => _isSidebarOpen = true),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: const BoxConstraints(maxWidth: 240),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF25D366),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _latestUnreadPreview,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      FloatingActionButton(
                        backgroundColor: const Color(0xFF25D366),
                        elevation: 4,
                        onPressed: () =>
                            setState(() => _isSidebarOpen = !_isSidebarOpen),
                        child: Badge(
                          label: Text(_unreadCount.toString()),
                          isLabelVisible: _unreadCount > 0,
                          child: const Icon(
                            Icons.chat_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🚀 4. UPDATE TOP NAVIGATION (ഉപയോഗമില്ലാത്ത Dashboard ടാബ് കളഞ്ഞു)
  Widget _buildTopNavigationBar() {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 16),
            _buildTopTab(0, "Orders", Icons.receipt_long_rounded),
            _buildTopTab(1, "Menu", Icons.restaurant_menu_rounded),
            _buildTopTab(2, "Marketing", Icons.campaign_outlined),
            _buildTopTab(3, "Settings", Icons.settings_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTab(int index, String title, IconData icon) {
    final bool isActive = _selectedMenuIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedMenuIndex = index),
      hoverColor: primaryTeal.withOpacity(0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        height: 56,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primaryTeal : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isActive ? primaryTeal : textMuted),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isActive ? primaryTeal : textDark,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 5. PASS THE TRIGGER TO CHILDREN
  Widget _buildMainContent() {
    return IndexedStack(
      index: _stackIndex,
      children: [
        // Index 0: Live Orders (Now receives the syncTrigger)
        LiveOrdersScreen(
          restaurantId: widget.restaurantId,
          syncTrigger: _globalSyncTrigger,
          onOrderContactSelected: (phone) {
            setState(() {
              _selectedNumber = phone;
              _selectedPhoneId = _restaurantPhoneId;
              _sidebarView = "chat";
              _isSidebarOpen = true;
            });
          },
        ),
        // Index 1: Menu Management
        MenuManagementScreen(restaurantId: widget.restaurantId),
        // Index 2: Marketing
        MarketingScreen(restaurantId: widget.restaurantId),
        // Index 3: Settings
        SettingsScreen(restaurantId: widget.restaurantId),
      ],
    );
  }

  Widget _buildSidebarContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
            ),
          ),
          child: Row(
            children: [
              if (_sidebarView == "chat") ...[
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: Color(0xFF0F172A),
                    ),
                    onPressed: () => setState(() => _sidebarView = "inbox"),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (_sidebarView != "chat") ...[
                          const Icon(
                            Icons.forum_rounded,
                            color: Color(0xFF10B981),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            _sidebarView == "chat"
                                ? "+${_selectedNumber ?? ''}"
                                : "WhatsApp Manager",
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_sidebarView == "chat")
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Customer Chat",
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Color(0xFFEF4444),
                  ),
                  onPressed: () => setState(() => _isSidebarOpen = false),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _sidebarView == "chat" ? 1 : 0,
            children: [
              InboxScreen(
                restaurantId: widget.restaurantId,
                syncTrigger: _globalSyncTrigger,
                // 🚀 FIX: shared cache so tapping clears the FAB badge
                onContactSelected: (number, phoneId, msgId) async {
                  await DatabaseHelper.instance.markContactAsRead(
                    widget.restaurantId,
                    number,
                    msgId,
                  );
                  setState(() {
                    _selectedNumber = number;
                    _selectedPhoneId = phoneId.isNotEmpty
                        ? phoneId
                        : _restaurantPhoneId;
                    _sidebarView = "chat";
                  });
                  await _refreshUnreadBadge();
                },
                onUnreadCountChanged:
                    null, // badge is now driven by _refreshUnreadBadge
              ),
              _selectedNumber != null
                  ? ChatDetailScreen(
                      key: ValueKey(_selectedNumber),
                      phoneNumber: _selectedNumber!,
                      restaurantId: widget.restaurantId,
                      phoneNumberId: _selectedPhoneId ?? _restaurantPhoneId,
                      syncTrigger: _globalSyncTrigger,
                    )
                  : const Center(child: Text("Select a chat from the Inbox")),
            ],
          ),
        ),
      ],
    );
  }
}
