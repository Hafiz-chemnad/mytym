import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

// 🚀 MODULAR IMPORTS
import '../../settings/services/settings_api_service.dart';
import '../../settings/services/settings_db_service.dart';
import '../../menu/services/menu_db.dart';
import '../../chat/services/chat_api.dart';
import '../services/order_api.dart';
import '../services/order_db.dart';
import '../../delivery_boys/services/delivery_boy_api.dart';
import '../../delivery_boys/services/delivery_boy_db.dart';
import '../utils/kot_printer.dart';
import '../widgets/order_list_card.dart';
import '../widgets/order_detail_panel.dart';
import '../../../core/database/db_connection.dart';
import '../../marketing/services/crm_api.dart';
import '../../marketing/services/crm_db.dart';

class LiveOrdersScreen extends StatefulWidget {
  final String restaurantId;
  final Function(String) onOrderContactSelected;
  final ValueNotifier<int> syncTrigger;

  const LiveOrdersScreen({
    super.key,
    required this.restaurantId,
    required this.onOrderContactSelected,
    required this.syncTrigger,
  });

  @override
  _LiveOrdersScreenState createState() => _LiveOrdersScreenState();
}

class _LiveOrdersScreenState extends State<LiveOrdersScreen> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _orders = [];
  bool _isLoading = true;
  bool _isProcessingAction = false;
  final Set<String> _acknowledgedOrderIds = {};
  bool _isFirstLoad = true;

  String _searchQuery = "";
  String _activeFilter = "Live";
  Set<String> _unreadNumbers = {};
  
  late AnimationController _blinkController;
  late Animation<Color?> _blinkColor;

  Map<String, dynamic>? _selectedOrder;
  Map<String, String> _itemNameResolver = {};
  List<Map<String, String>> _deliveryBoys = [];

  // 🎨 POS Theme Colors
  final Color primaryTeal = const Color(0xFF096A56);
  final Color bgLight = const Color(0xFFF2F7F4);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _blinkColor = ColorTween(
      begin: Colors.white,
      end: const Color(0xFFFEE2E2),
    ).animate(_blinkController);
    _audioPlayer.setReleaseMode(ReleaseMode.loop);

    _initializeAppState();
    widget.syncTrigger.addListener(_fetchOrdersAndStats);
  }

  @override
  void dispose() {
    widget.syncTrigger.removeListener(_fetchOrdersAndStats);
    _audioPlayer.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  Future<void> _initializeAppState() async {
    try {
      final profile = await SettingsApiService.instance.fetchRestaurantProfile(widget.restaurantId);
      if (profile != null) {
        await SettingsDbService.instance.saveSettings(profile);
      }
    } catch (e) {
      print("Failed to initialize profile on Orders screen: $e");
    }

    await _loadNameResolver();
    await _loadDeliveryBoys();
    await _fetchOrdersAndStats();
  }

  String _getSafeId(Map<String, dynamic> o) {
    return o['_id']?.toString() ?? o['id']?.toString() ?? o['orderId']?.toString() ?? '';
  }

  Future<void> _loadUnreadNumbers() async {
    try {
      final readSet = await CrmDbService.instance.getReadContactNumbers(widget.restaurantId);
      final db = await DbConnection.instance.database;
      final rows = await db.rawQuery(
        '''SELECT DISTINCT customer_number FROM ${DbConnection.tableMessages}
           WHERE restaurant_id = ?
             AND (direction = 'inbound' OR is_outgoing = 0)''',
        [widget.restaurantId],
      );
      final allInboundNumbers = rows.map((r) => r['customer_number'].toString()).toSet();
      if (mounted) {
        setState(() {
          _unreadNumbers = allInboundNumbers.difference(readSet);
        });
      }
    } catch (e) {
      print("❌ Failed to load unread numbers: $e");
    }
  }

  Future<void> _fetchOrdersAndStats() async {
    try {
      // 🚀 Using isolated OrderDbService
      final localData = await OrderDbService.instance.getAllOrders(widget.restaurantId);

      if (mounted) {
        setState(() {
          _orders = localData;
          _isLoading = false;
          _processOrderState(localData);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
    await _loadUnreadNumbers();
  }

  void _processOrderState(List<dynamic> data) {
    if (_isFirstLoad) {
      for (var o in data) {
        _acknowledgedOrderIds.add(_getSafeId(o));
      }
      _isFirstLoad = false;
    } else {
      bool hasUnacknowledged = data.any((o) => !_acknowledgedOrderIds.contains(_getSafeId(o)));

      if (hasUnacknowledged) {
        try {
          if (_audioPlayer.state != PlayerState.playing) {
            _audioPlayer.play(AssetSource('sounds/notification.mp3')).catchError((e) => print("Audio play suppressed"));
          }
        } catch (e) {
          print("Audio engine busy, skipping ping.");
        }
      } else {
        try {
          if (_audioPlayer.state == PlayerState.playing) _audioPlayer.stop();
        } catch (e) {}
      }
    }

    if (_selectedOrder != null) {
      try {
        _selectedOrder = _orders.firstWhere((o) => _getSafeId(o) == _getSafeId(_selectedOrder!));
      } catch (e) {
        _selectedOrder = null;
      }
    }
  }

  List<dynamic> get _filteredOrders {
    return _orders.where((o) {
      String orderId = o['orderId']?.toString().toLowerCase() ?? '';
      String phone = o['customerNumber']?.toString().toLowerCase() ?? '';
      String searchTarget = "$orderId $phone";
      if (_searchQuery.isNotEmpty && !searchTarget.contains(_searchQuery.toLowerCase())) return false;

      String payStatus = (o['paymentStatus'] ?? 'pending').toString().toLowerCase();

      switch (_activeFilter) {
        case "Today":
          String rawDate = o['createdAt'] is Map ? (o['createdAt']['\$date'] ?? '') : (o['createdAt'] ?? '');
          DateTime? d = DateTime.tryParse(rawDate)?.toLocal();
          if (d != null) {
            DateTime now = DateTime.now();
            if (d.year != now.year || d.month != now.month || d.day != now.day) return false;
          }
          break;
        case "COD":
          if (payStatus != 'cod') return false;
          break;
        case "Pending":
          if (!{'pending', 'cod', 'online'}.contains(payStatus)) return false;
          break;
        case "Live":
          if (!{'pending', 'cod', 'online', 'accepted', 'preparing', 'assigned', 'paid', 'ready'}.contains(payStatus)) return false;
          break;
        case "Rejected":
          if (payStatus != 'rejected') return false;
          break;
        case "Accepted":
          if (payStatus != 'accepted') return false;
          break;
        case "Assigned":
          if (payStatus != 'assigned') return false;
          break;
        case "Ready":                              
          if (payStatus != 'ready') return false;
          break;  
        case "Completed":
          if (!{'completed', 'paid'}.contains(payStatus)) return false;
          break;
        case "Paid":
          if (payStatus != 'paid') return false;
          break;
      }
      return true;
    }).toList();
  }

  String _formatFullDate(String rawDate) {
    if (rawDate.isEmpty) return "N/A";
    DateTime? parsed = DateTime.tryParse(rawDate)?.toLocal();
    if (parsed == null) return "N/A";
    int hour = parsed.hour;
    String ampm = hour >= 12 ? 'PM' : 'AM';
    int hour12 = hour % 12 == 0 ? 12 : hour % 12;
    String yy = parsed.year.toString().substring(2); 
    return "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/$yy ${hour12.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')} $ampm";
  }

  Future<void> _loadNameResolver() async {
    final items = await MenuDbService.instance.getAllMenuItems(widget.restaurantId);
    Map<String, String> resolver = {};
    for (var item in items) {
      String id = item['retailerId']?.toString() ?? item['id']?.toString() ?? '';
      String name = item['name']?.toString() ?? 'Unknown Item';
      if (id.isNotEmpty) resolver[id] = name;
    }
    if (mounted) setState(() => _itemNameResolver = resolver);
  }

  String _resolveItemName(String rawName) {
    if (!rawName.startsWith('tym_') && !rawName.contains('tym_')) return rawName;
    String idToFind = rawName;
    final match = RegExp(r'tym_\d+').firstMatch(rawName);
    if (match != null) idToFind = match.group(0)!;
    return _itemNameResolver[idToFind] ?? rawName;
  }

  Future<void> _loadDeliveryBoys() async {
    // 🚀 On-demand refresh (no background polling — delivery boys change
    // rarely). Pulls from erp_backend, reseeds local SQLite, then reads.
    await DeliveryBoyApi.instance.refreshDeliveryBoys(widget.restaurantId);
    final boys = await DeliveryBoyDbService.instance.getAllDeliveryBoys(widget.restaurantId);
    if (mounted) setState(() => _deliveryBoys = boys);
  }

  // ====================================================================
  // 🚀 ACTION HANDLERS
  // ====================================================================

  Future<bool> _sendOrderNotification(String phone, String text, {String? templateFallback, List<String> fallbackParams = const []}) async {
    try {
      final settings = await SettingsDbService.instance.getSettings();
      String phoneId = settings?['phoneNumberId']?.toString() ?? "";
      if (phoneId.isEmpty) {
        final profile = await SettingsApiService.instance.fetchRestaurantProfile(widget.restaurantId);
        phoneId = profile?['phoneNumberId']?.toString() ?? "";
      }

      String rawPhone = phone.replaceAll('+', '').replaceAll(' ', '').trim();
      bool textSuccess = await ChatApi.instance.sendMessage(to: rawPhone, text: text, restaurantId: widget.restaurantId, phoneNumberId: phoneId);

      if (!textSuccess && templateFallback != null) {
        return await CrmApi.instance.sendTemplateMessage(restaurantId: widget.restaurantId, customerNumber: rawPhone, templateName: templateFallback, templateParams: fallbackParams);
      }
      return textSuccess;
    } catch (e) {
      return false;
    }
  }

  void _showNotesDialog(String orderId, String currentStatus, String currentNotes) {
    String cleanForDisplay = currentNotes.replaceAll('[ACCEPTED]', '').replaceAll('[REJECTED]', '').replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '').trim();
    TextEditingController notesController = TextEditingController(text: cleanForDisplay);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Chef Notes", style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal)),
        content: TextField(
          controller: notesController,
          decoration: InputDecoration(hintText: "E.g., Less spicy", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryTeal, width: 2))),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              Navigator.pop(context);
              String userText = notesController.text.trim();
              String tagsToKeep = '';
              if (currentNotes.contains('[ACCEPTED]')) tagsToKeep += '\n[ACCEPTED]';
              if (currentNotes.contains('[REJECTED]')) tagsToKeep += '\n[REJECTED]';
              final dbMatch = RegExp(r'\[DELIVERY_BOY:[^\]]*\]').firstMatch(currentNotes);
              if (dbMatch != null) tagsToKeep += '\n${dbMatch.group(0)}';
              String finalNotes = userText.isEmpty ? tagsToKeep.trim() : '$userText$tagsToKeep';

              bool ok = await OrderApi.instance.updateOrderStatus(restaurantId: widget.restaurantId, orderId: orderId, status: currentStatus, notes: finalNotes);
              if (ok) _fetchOrdersAndStats();
            },
            child: const Text("Save Notes", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleAcceptOrder(Map<String, dynamic> order, String formattedDate) async {
    if (_isProcessingAction) return; 
    setState(() => _isProcessingAction = true);
    
    try {
      String mongoId = order['_id']?.toString() ?? '';
      String displayId = order['displayId']?.toString().isNotEmpty == true ? order['displayId'].toString() : order['orderId']?.toString() ?? mongoId;
      String phone = order['customerNumber'] ?? '';
      String currentNotes = order['additionalNotes'] ?? '';

      String newNotes = currentNotes.isEmpty ? "[ACCEPTED]" : "$currentNotes\n[ACCEPTED]";
      
      await OrderDbService.instance.updateOrderStatusLocally(widget.restaurantId, mongoId, 'accepted', notes: newNotes);
      await _fetchOrdersAndStats(); 

      OrderApi.instance.updateOrderStatus(restaurantId: widget.restaurantId, orderId: displayId, status: 'accepted', notes: newNotes).then((updated) {
        if (!updated) print('⚠️ Accept API call failed for $displayId — local DB already updated.');
      });

      // 🚀 Use the new KotPrinter utility
      final settings = await SettingsDbService.instance.getSettings();
      String restaurantName = settings?['name']?.toString().isNotEmpty == true ? settings!['name'].toString() : 'Our Restaurant';
      String restaurantAddress = settings?['address']?.toString() ?? '';

      KotPrinter.printKOT(
        order: order, 
        formattedDate: formattedDate, 
        restaurantName: restaurantName, 
        restaurantAddress: restaurantAddress, 
        resolveItemName: _resolveItemName
      );

      if (phone.isNotEmpty) {
        String itemsStr = "";
        double calcSubtotal = 0;
        List<dynamic> items = order['items'] ?? [];

        for (var item in items) {
          String name = _resolveItemName(item['name'] ?? '');
          double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          double lineTotal = price * qty;
          calcSubtotal += lineTotal;
          itemsStr += "* $name – ₹$price × $qty = ₹$lineTotal\n";
        }

        double total = double.tryParse(order['totalAmount']?.toString() ?? '0') ?? 0.0;
        double deliveryCharge = total - calcSubtotal;
        if (deliveryCharge < 0) deliveryCharge = 0;
        
        String orderType = (order['orderType'] ?? '').toString().toUpperCase();

        String closingLine = orderType == 'TAKEAWAY'
            ? '''🍽️ We will inform you once your order is ready for pickup.
ഓർഡർ തയ്യാറാകുമ്പോൾ ഞങ്ങൾ നിങ്ങളെ അറിയിക്കും.'''
            : '''📞 The delivery boy will contact you soon.
ഡെലിവറി ബോയ് ഉടൻ തന്നെ നിങ്ങളെ ബന്ധപ്പെടും.''';

        String msg = '''🎉 Order Confirmed! ✅

🚚 Your order has been received successfully.

🧾 Order Summary
—————————————-
Order ID: $displayId

$itemsStr
💰 Sub Total: ₹$calcSubtotal
🚚 Delivery Charge: ₹$deliveryCharge
💳 Total Payable: ₹$total

⸻⸻⸻⸻
$closingLine

🙏 Thank you for your order!
🏪 $restaurantName''';

        bool success = await _sendOrderNotification(phone, msg, templateFallback: 'two');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(success ? "✅ Order accepted! Customer notified." : "⚠️ Order accepted, but WhatsApp message failed."),
            backgroundColor: success ? const Color(0xFF14804A) : const Color(0xFFD92D20),
          ));
        }
      }
    } finally {
      setState(() => _isProcessingAction = false);
    }
  }

  void _handleRejectOrder(Map<String, dynamic> order) async {
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString().isNotEmpty == true ? order['displayId'].toString() : order['orderId']?.toString() ?? mongoId;
    String phone = order['customerNumber'] ?? '';
    String currentNotes = order['additionalNotes'] ?? '';

    String newNotes = currentNotes.isEmpty ? "[REJECTED]" : "$currentNotes\n[REJECTED]";
    await OrderDbService.instance.updateOrderStatusLocally(widget.restaurantId, mongoId, 'rejected', notes: newNotes);
    _fetchOrdersAndStats();

    OrderApi.instance.updateOrderStatus(restaurantId: widget.restaurantId, orderId: displayId, status: 'rejected', notes: newNotes);

    if (phone.isNotEmpty) {
      final settings = await SettingsDbService.instance.getSettings();
      String restaurantName = settings?['name']?.toString().isNotEmpty == true ? settings!['name'].toString() : 'Our Restaurant';
      
      String msg = '''❌ Order Rejected\n\nSorry, your order #$displayId cannot be processed.\n\n📌 Reason: Currently unavailable\n\n🏪 $restaurantName''';

      bool success = await _sendOrderNotification(phone, msg, templateFallback: 'two');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? "❌ Order rejected! Customer notified." : "⚠️ Order rejected, but WhatsApp message failed."),
          backgroundColor: success ? const Color(0xFF14804A) : const Color(0xFFD92D20),
        ));
      }
    }
  }

  Future<void> _handleReadyOrder(Map<String, dynamic> order) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);
    
    try {
      String mongoId = order['_id']?.toString() ?? '';
      String displayId = order['displayId']?.toString().isNotEmpty == true ? order['displayId'].toString() : order['orderId']?.toString() ?? mongoId;
      String phone = order['customerNumber'] ?? '';
      String currentNotes = order['additionalNotes'] ?? '';

      String msg = '🍽️ Your order $displayId is ready!\n\nPlease come and pick up your order. Thank you! 🙏';
      bool sent = await _sendOrderNotification(phone, msg, templateFallback: 'two');

      await OrderDbService.instance.updateOrderStatusLocally(widget.restaurantId, mongoId, 'ready', notes: currentNotes);
      _fetchOrdersAndStats();

      OrderApi.instance.updateOrderStatus(restaurantId: widget.restaurantId, orderId: displayId, status: 'ready', notes: currentNotes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sent ? "✅ Customer notified order is ready!" : "⚠️ Marked ready, but WhatsApp message failed."),
          backgroundColor: sent ? const Color(0xFF14804A) : const Color(0xFFD92D20),
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _handleCompleteOrder(Map<String, dynamic> order) async {
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString().isNotEmpty == true ? order['displayId'].toString() : order['orderId']?.toString() ?? mongoId;
    String currentNotes = order['additionalNotes'] ?? '';

    await OrderDbService.instance.updateOrderStatusLocally(widget.restaurantId, mongoId, 'completed');
    _fetchOrdersAndStats();

    OrderApi.instance.updateOrderStatus(restaurantId: widget.restaurantId, orderId: displayId, status: 'completed', notes: currentNotes);
  }

  void _showCreateDeliveryBoyDialog(BuildContext parentContext, StateSetter setParentDialogState) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text("New Delivery Boy", style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal, fontSize: 16)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController, textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: "Name", hintText: "e.g. Raju Kumar", prefixIcon: Icon(Icons.person_outline, color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryTeal, width: 2))),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Name is required" : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: phoneController, keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: "WhatsApp Number", hintText: "e.g. 9876543210  (without 91)", prefixIcon: Icon(Icons.phone_outlined, color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryTeal, width: 2)), helperText: "Country code 91 will be added automatically"),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return "Phone number is required";
                  final digits = v.trim().replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10) return "Enter at least 10 digits";
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              String digits = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
              if (digits.length == 10) digits = '91$digits'; 
              else if (digits.startsWith('9191') && digits.length == 14) digits = digits.substring(2); 
              else if (digits.startsWith('91') && digits.length > 12) digits = '91${digits.substring(digits.length - 10)}';
              
              final name = nameController.text.trim();
              Navigator.pop(ctx);

              final success = await DeliveryBoyApi.instance.addDeliveryBoy(widget.restaurantId, name, digits);
              if (!success) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(content: Text("Failed to save delivery boy — check connection."), backgroundColor: Color(0xFFEF4444)),
                );
              }
              final updated = await DeliveryBoyDbService.instance.getAllDeliveryBoys(widget.restaurantId);
              setParentDialogState(() => _deliveryBoys = updated);
              if (mounted) setState(() => _deliveryBoys = updated);
            },
            child: const Text("Add", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDeliveryBoyDialog(BuildContext parentContext, StateSetter setParentDialogState, Map<String, String> boy) {
    final nameController = TextEditingController(text: boy['name']);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text("Edit Delivery Boy", style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal, fontSize: 16)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController, textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: "Name", prefixIcon: Icon(Icons.person_outline, color: textMuted), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryTeal, width: 2))),
            validator: (v) => (v == null || v.trim().isEmpty) ? "Name is required" : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newName = nameController.text.trim();
              final phone = boy['phone']!;
              Navigator.pop(ctx);

              final success = await DeliveryBoyApi.instance.updateDeliveryBoyName(widget.restaurantId, phone, newName);
              if (!success) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(content: Text("Failed to update — check connection."), backgroundColor: Color(0xFFEF4444)),
                );
              }
              final updated = await DeliveryBoyDbService.instance.getAllDeliveryBoys(widget.restaurantId);
              setParentDialogState(() => _deliveryBoys = updated);
              if (mounted) setState(() => _deliveryBoys = updated);
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDeliveryBoy(BuildContext parentContext, StateSetter setParentDialogState, Map<String, String> boy) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Delivery Boy?"),
        content: Text("Remove ${boy['name']} (+${boy['phone']}) from your delivery list?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final phone = boy['phone']!;
              Navigator.pop(ctx);

              final success = await DeliveryBoyApi.instance.deleteDeliveryBoy(widget.restaurantId, phone);
              if (!success) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(content: Text("Failed to delete — check connection."), backgroundColor: Color(0xFFEF4444)),
                );
              }
              final updated = await DeliveryBoyDbService.instance.getAllDeliveryBoys(widget.restaurantId);
              setParentDialogState(() => _deliveryBoys = updated);
              if (mounted) setState(() => _deliveryBoys = updated);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAssignDeliveryDialog(Map<String, dynamic> order) {
    final screenContext = context;

    showDialog(
      context: screenContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (sbContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Assign Delivery Boy", style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal, fontSize: 16)),
                  TextButton.icon(
                    style: TextButton.styleFrom(backgroundColor: primaryTeal.withOpacity(0.08), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    icon: Icon(Icons.add, size: 16, color: primaryTeal), label: Text("Create New", style: TextStyle(color: primaryTeal, fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: () => _showCreateDeliveryBoyDialog(sbContext, setDialogState),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: _deliveryBoys.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.motorcycle_outlined, size: 48, color: textMuted.withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text("No delivery boys yet.\nTap \"Create New\" to add one.", textAlign: TextAlign.center, style: TextStyle(color: textMuted, fontSize: 13)),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${_deliveryBoys.length} delivery boy${_deliveryBoys.length > 1 ? 's' : ''} available", style: TextStyle(color: textMuted, fontSize: 12)),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _deliveryBoys.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F4F2)),
                              itemBuilder: (_, i) {
                                final boy = _deliveryBoys[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  leading: CircleAvatar(backgroundColor: primaryTeal.withOpacity(0.1), child: Text((boy['name'] ?? '?')[0].toUpperCase(), style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold))),
                                  title: Text(boy['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Text("+${boy['phone'] ?? ''}", style: TextStyle(color: textMuted, fontSize: 12)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined, size: 18, color: textMuted),
                                        tooltip: "Edit name",
                                        onPressed: () => _showEditDeliveryBoyDialog(sbContext, setDialogState, boy),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                                        tooltip: "Delete",
                                        onPressed: () => _confirmDeleteDeliveryBoy(sbContext, setDialogState, boy),
                                      ),
                                      const SizedBox(width: 4),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                                        onPressed: () async {
                                          Navigator.pop(dialogContext);
                                          await _assignDeliveryBoy(order, boy['phone']!, boy['name']!, screenContext);
                                        },
                                        child: const Text("Assign", style: TextStyle(color: Colors.white, fontSize: 13)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text("Cancel", style: TextStyle(color: textMuted))),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _assignDeliveryBoy(Map<String, dynamic> order, String deliveryPhone, String deliveryName, BuildContext screenContext) async {
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString().isNotEmpty == true ? order['displayId'].toString() : order['orderId']?.toString() ?? mongoId;
    String customerPhone = order['customerNumber'] ?? 'Unknown';
    String total = order['totalAmount']?.toString() ?? '0';
    String orderNotes = order['additionalNotes']?.toString() ?? '';

    String locationText = "No location provided";
    var loc = order['location'];
    if (loc is Map && loc['lat'] != null && loc['lng'] != null) {
      locationText = "https://www.google.com/maps?q=${loc['lat']},${loc['lng']}";
    }

    String itemsListStr = "";
    List<dynamic> itemsList = order['items'] ?? [];
    for (var item in itemsList) {
      String name = _resolveItemName(item['name'] ?? '');
      int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      itemsListStr += "$qty x $name\n";
    }

    String msg = '🚚 New Delivery Order\n\n🧾 Order ID: $displayId\n\n📞 +$customerPhone\n\n📍 $locationText\n\n🍽️ Items:\n$itemsListStr\n💰 Total: ₹$total';
    bool deliverySuccess = await _sendOrderNotification(deliveryPhone, msg, templateFallback: 'two');

    String cleanDeliveryPhone = deliveryPhone.replaceAll('+', '').replaceAll(' ', '').trim();
    String customerMsg = '🚴 Your delivery is on the way!\n\n📦 Order ID: $displayId\n\n🧑 Delivery Partner: $deliveryName\n📞 Contact: +$cleanDeliveryPhone\n\n🙏 Thank you for your order!';
    bool customerSuccess = await _sendOrderNotification(customerPhone, customerMsg, templateFallback: 'two');

    if (mongoId.isNotEmpty) {
      String deliveryTag = '[DELIVERY_BOY:$deliveryName|$cleanDeliveryPhone]';
      String cleanedNotes = orderNotes.replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '').trim();
      String updatedNotes = cleanedNotes.isEmpty ? deliveryTag : '$cleanedNotes\n$deliveryTag';

      await OrderDbService.instance.updateOrderStatusLocally(widget.restaurantId, mongoId, 'assigned', notes: updatedNotes);
      _fetchOrdersAndStats();

      OrderApi.instance.updateOrderStatus(restaurantId: widget.restaurantId, orderId: displayId, status: 'assigned', notes: updatedNotes);
    }

    if (mounted) {
      String snackMsg;
      if (deliverySuccess && customerSuccess) snackMsg = "✅ Assigned to $deliveryName! Both messages sent.";
      else if (deliverySuccess) snackMsg = "✅ Assigned to $deliveryName. Customer notification failed.";
      else if (customerSuccess) snackMsg = "⚠️ Assigned to $deliveryName. Delivery boy message failed.";
      else snackMsg = "⚠️ Assigned to $deliveryName, but both WhatsApp messages failed.";
      
      ScaffoldMessenger.of(screenContext).showSnackBar(SnackBar(
        content: Text(snackMsg), backgroundColor: (deliverySuccess || customerSuccess) ? const Color(0xFF14804A) : const Color(0xFFD92D20),
      ));
    }
  }

  Future<void> _openMap(dynamic location) async {
    if (location is Map && location['lat'] != null && location['lng'] != null) {
      final Uri url = Uri.parse("https://www.google.com/maps?q=${location['lat']},${location['lng']}");
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open Google Maps.")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location details not available.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: bgLight,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryTeal))
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeader(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildOrdersList()),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 7,
                          child: _selectedOrder == null
                              ? Center(child: Text("No order selected", style: TextStyle(color: textMuted, fontSize: 16)))
                              : OrderDetailPanel(
                                  order: _selectedOrder!,
                                  resolveItemName: _resolveItemName,
                                  hasUnreadChat: _unreadNumbers.contains(_selectedOrder!['customerNumber'] ?? ''),
                                  onAccept: () {
                                    String rawDate = _selectedOrder!['createdAt'] is Map ? (_selectedOrder!['createdAt']['\$date'] ?? '') : (_selectedOrder!['createdAt'] ?? '');
                                    _handleAcceptOrder(Map<String, dynamic>.from(_selectedOrder!), _formatFullDate(rawDate));
                                  },
                                  onReject: () => _handleRejectOrder(_selectedOrder!),
                                  onAssignDelivery: () => _showAssignDeliveryDialog(_selectedOrder!),
                                  onMarkReady: () => _handleReadyOrder(_selectedOrder!),
                                  onMarkCompleted: () => _handleCompleteOrder(_selectedOrder!),
                                  onChefNote: () => _showNotesDialog(
                                    _selectedOrder!['orderId'] ?? _selectedOrder!['_id'],
                                    _selectedOrder!['paymentStatus'] ?? 'pending',
                                    _selectedOrder!['additionalNotes'] ?? ''
                                  ),
                                  onChat: () async {
                                    String customerNumber = _selectedOrder!['customerNumber'] ?? '';
                                    if (_unreadNumbers.contains(customerNumber)) {
                                      await CrmDbService.instance.markContactAsRead(widget.restaurantId, customerNumber, '');
                                      await _loadUnreadNumbers();
                                    }
                                    widget.onOrderContactSelected(customerNumber);
                                  },
                                  onMap: () => _openMap(_selectedOrder!['location']),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTopHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Live Orders", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: textDark)),
        Text("View and manage real-time WhatsApp orders", style: TextStyle(color: textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2, 
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16), height: 44,
                decoration: BoxDecoration(color: const Color(0xFFE9F0EC), borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder)),
                child: Row(
                  children: [
                    Icon(Icons.search, color: textMuted, size: 20), const SizedBox(width: 10),
                    Expanded(child: TextField(onChanged: (val) => setState(() => _searchQuery = val), decoration: InputDecoration(hintText: "Search ID or phone...", hintStyle: TextStyle(color: textMuted, fontSize: 14), border: InputBorder.none))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip("All", Icons.list_alt_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Today", Icons.today_rounded), const SizedBox(width: 8),
                    _buildFilterChip("COD", Icons.money), const SizedBox(width: 8),
                    _buildFilterChip("Pending", Icons.hourglass_empty_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Live", Icons.bolt_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Accepted", Icons.check_circle_outline), const SizedBox(width: 8),
                    _buildFilterChip("Assigned", Icons.motorcycle_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Ready", Icons.restaurant_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Completed", Icons.done_all_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Paid", Icons.payments_rounded), const SizedBox(width: 8),
                    _buildFilterChip("Rejected", Icons.cancel_outlined),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _chipColor(String label) {
    switch (label) {
      case "COD": return Colors.orange.shade700;
      case "Pending": return Colors.orange.shade700;
      case "Live": return const Color(0xFF7C3AED);
      case "Accepted": return const Color(0xFF1570EF);
      case "Assigned": return const Color(0xFF0891B2);
      case "Completed": return const Color(0xFF14804A);
      case "Paid": return const Color(0xFF14804A);
      case "Rejected": return const Color(0xFFD92D20);
      default: return const Color(0xFF14804A);
    }
  }

  Widget _buildFilterChip(String label, [IconData? icon]) {
    bool isSelected = _activeFilter == label;
    final Color accent = _chipColor(label);
    final Color bg = isSelected ? accent.withOpacity(0.12) : Colors.white;
    final Color border = isSelected ? accent : cardBorder;
    final Color textColor = isSelected ? accent : textDark;

    return InkWell(
      onTap: () => setState(() { _activeFilter = label; _selectedOrder = null; }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[Icon(Icons.check, size: 13, color: accent), const SizedBox(width: 4)]
            else if (icon != null) ...[Icon(icon, size: 13, color: textMuted), const SizedBox(width: 4)],
            Text(label, style: TextStyle(color: textColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList() {
    final list = _filteredOrders; 
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Order Records", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark)),
                Text("${list.length} records", style: TextStyle(color: textMuted, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text("No orders found", style: TextStyle(color: textMuted)))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF0F4F2)),
                    itemBuilder: (context, index) {
                      var o = list[index];
                      String uniqueId = _getSafeId(o);
                      bool isSelected = _getSafeId(_selectedOrder ?? {}) == uniqueId;
                      bool isUnacknowledged = !_acknowledgedOrderIds.contains(uniqueId);

                      return AnimatedBuilder(
                        animation: _blinkColor,
                        builder: (context, child) {
                          return OrderListCard(
                            order: o,
                            isSelected: isSelected,
                            isUnacknowledged: isUnacknowledged,
                            blinkColor: _blinkColor.value ?? Colors.white,
                            onTap: () {
                              setState(() {
                                _selectedOrder = o;
                                _acknowledgedOrderIds.add(uniqueId);
                                if (!list.any((item) => !_acknowledgedOrderIds.contains(_getSafeId(item)))) {
                                  try { _audioPlayer.stop(); } catch (e) {}
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}