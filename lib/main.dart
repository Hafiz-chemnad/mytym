import 'package:flutter/material.dart';
import 'package:whatsapp_erp_api/screens/login_screen.dart'; 
import 'package:whatsapp_erp_api/screens/inbox_screen.dart';
import 'package:whatsapp_erp_api/screens/chat_detail_screen.dart'; 
import 'package:whatsapp_erp_api/screens/live_orders_screen.dart'; 
import 'package:whatsapp_erp_api/screens/menu_management_screen.dart';
import 'package:whatsapp_erp_api/screens/marketing_screen.dart';
import 'package:whatsapp_erp_api/screens/settings_screen.dart'; 
import 'package:whatsapp_erp_api/services/api_service.dart'; // 🚀 ApiService Import ചെയ്തു
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        fontFamily: 'Roboto', // ADD THIS LINE: Tells Flutter to use your local font
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Segoe UI Symbol',
          'Noto Color Emoji',
        ],
      ),
      home: const LoginScreen(), 
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
  final ApiService _apiService = ApiService(); // 🚀 API സർവീസ്
  
  bool _isSidebarOpen = false;
  int _unreadCount = 0;
  int _selectedMenuIndex = 1; 
  String _sidebarView = "inbox"; 
  String? _selectedNumber;
  String? _selectedPhoneId;
  Timer? _pollingTimer;

  // 🚀 ലോഗിൻ ചെയ്ത റെസ്റ്റോറന്റിന്റെ യഥാർത്ഥ ഫോൺ ഐഡി സൂക്ഷിക്കാൻ
  String _restaurantPhoneId = ""; 

  // 🎨 POS Theme Colors
  static const Color primaryTeal = Color(0xFF096A56);
  static const Color textMuted = Color(0xFF6B7A75);
  static const Color textDark = Color(0xFF1B2420);

  @override
  void initState() {
    super.initState();
    _fetchRestaurantDetails(); // 🚀 തുടങ്ങുമ്പോൾ തന്നെ ഫോൺ ഐഡി എടുക്കുന്നു
    _startPollingMessages(widget.restaurantId); 
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // 🚀 റെസ്റ്റോറന്റിന്റെ യഥാർത്ഥ വിവരങ്ങൾ ഡാറ്റാബേസിൽ നിന്ന് എടുക്കുന്നു
  Future<void> _fetchRestaurantDetails() async {
    final profile = await _apiService.fetchRestaurantProfile(widget.restaurantId);
    if (profile != null && mounted) {
      setState(() {
        _restaurantPhoneId = profile['phoneNumberId']?.toString() ?? "";
      });
    }
  }

  void _startPollingMessages(String resId) {
    _pollingTimer?.cancel();
    _fetchUnreadCount(resId);
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) { 
      _fetchUnreadCount(resId);
    });
  }

  Future<void> _fetchUnreadCount(String resId) async {
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
        
        final unread = allMessages.where((m) {
          String msgResId = m['restaurantId']?.toString() ?? m['restaurant_id']?.toString() ?? "";
          String direction = m['direction']?.toString().toLowerCase() ?? "";
          bool isOutgoing = direction == 'outbound' || m['isOutgoing'] == true || m['is_outgoing'] == true;
          
          return msgResId == resId && !isOutgoing;
        }).toList();
        
        if (mounted) {
          setState(() { _unreadCount = unread.length; });
        }
      }
    } catch (e) {
      print("Polling Error: $e");
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
                Positioned(
                  right: 0, top: 0, bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isSidebarOpen ? 450 : 0,
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        if (_isSidebarOpen) 
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(-5, 0))
                      ],
                    ),
                    child: _isSidebarOpen ? _buildSidebarContent() : const SizedBox.shrink(),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: _isSidebarOpen ? 470 : 20, 
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF25D366),
                    elevation: 4,
                    onPressed: () {
                      setState(() {
                        _isSidebarOpen = !_isSidebarOpen;
                        if (_isSidebarOpen) _unreadCount = 0;
                      });
                    },
                    child: Badge(
                      label: Text(_unreadCount.toString()),
                      isLabelVisible: _unreadCount > 0,
                      child: const Icon(Icons.chat_rounded, size: 28, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavigationBar() {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 16),
            _buildTopTab(0, "Dashboard", Icons.dashboard_outlined),
            _buildTopTab(1, "Orders", Icons.receipt_long_rounded),
            _buildTopTab(2, "Menu", Icons.restaurant_menu_rounded),
            _buildTopTab(3, "Marketing", Icons.campaign_outlined),
            _buildTopTab(4, "Settings", Icons.settings_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTab(int index, String title, IconData icon) {
    bool isActive = _selectedMenuIndex == index;

    return InkWell(
      onTap: () => setState(() => _selectedMenuIndex = index),
      hoverColor: primaryTeal.withOpacity(0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: isActive ? primaryTeal : Colors.transparent, width: 3.0),
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

  Widget _buildMainContent() {
    switch (_selectedMenuIndex) {
      case 0:
        return const Center(child: Text("Welcome to Dashboard", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)));
      case 1: 
        return LiveOrdersScreen(
          restaurantId: widget.restaurantId,
          onOrderContactSelected: (phone) {
            setState(() {
              _selectedNumber = phone;
              // 🚀 ഹാർഡ്‌കോഡ് ഒഴിവാക്കി, ഒറിജിനൽ ഐഡി നൽകുന്നു ✅
              _selectedPhoneId = _restaurantPhoneId; 
              _sidebarView = "chat"; 
              _isSidebarOpen = true; 
            });
          },
        );
      case 2:
        return MenuManagementScreen(restaurantId: widget.restaurantId); 
      case 3:
        return MarketingScreen(restaurantId: widget.restaurantId);
      case 4:
        return SettingsScreen(restaurantId: widget.restaurantId);
      default: 
        return const Center(child: Text("Welcome to Dashboard"));
    }
  }

  Widget _buildSidebarContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: const BoxDecoration(
            color: Colors.white, 
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5)), 
          ),
          child: Row(
            children: [
              if (_sidebarView == "chat") ...[
                Container(
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
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
                          const Icon(Icons.forum_rounded, color: Color(0xFF10B981), size: 22),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            _sidebarView == "chat" ? "+${_selectedNumber ?? ''}" : "WhatsApp Manager",
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_sidebarView == "chat")
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            
                            // 🚀 THE FIX: Wrapped in Expanded with an ellipsis overflow
                            const Expanded(
                              child: Text(
                                "Active Session", 
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis, // 👈 Safely hides text when shrinking
                              ),
                            ),
                            
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFFEF4444)), 
                  onPressed: () => setState(() => _isSidebarOpen = false),
                ),
              )
            ],
          ),
        ),
        
        Expanded(
          child: _sidebarView == "inbox" 
            ? InboxScreen(
                restaurantId: widget.restaurantId,
                onContactSelected: (number, phoneId) => setState(() { 
                  _selectedNumber = number; 
                  // 🚀 ഫോൺ ഐഡി ശൂന്യമാണെങ്കിൽ റെസ്റ്റോറന്റിന്റെ ഐഡി കൊടുക്കുന്നു ✅
                  _selectedPhoneId = phoneId.isNotEmpty ? phoneId : _restaurantPhoneId; 
                  _sidebarView = "chat"; 
                }),
              )
            : ChatDetailScreen(
                phoneNumber: _selectedNumber ?? "", 
                restaurantId: widget.restaurantId,
                // 🚀 ഹാർഡ്‌കോഡ് ഒഴിവാക്കി ✅
                phoneNumberId: _selectedPhoneId ?? _restaurantPhoneId,
              ),
        ),
      ],
    );
  }
}