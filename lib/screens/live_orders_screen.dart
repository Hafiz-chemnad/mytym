import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';

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

// 🚀 FIX: Added SingleTickerProviderStateMixin for the blinking animation
class _LiveOrdersScreenState extends State<LiveOrdersScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  @override
  bool get wantKeepAlive => true;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _orders = [];
  bool _isLoading = true;
  bool _isProcessingAction = false;
  // 🚀 FIX: Instance variables (not static) so they reset when screen rebuilds
  final Set<String> _acknowledgedOrderIds = {};
  bool _isFirstLoad = true;

  // 🚀 FIX: Search & Filter State
  String _searchQuery = "";
  String _activeFilter = "Live"; // Default: show all active orders
  Set<String> _unreadNumbers = {};
  // Blinking Animation State
  late AnimationController _blinkController;
  late Animation<Color?> _blinkColor;

  Map<String, dynamic>? _selectedOrder;

  // 🎨 POS Theme Colors
  final Color primaryTeal = const Color(0xFF096A56);
  final Color bgLight = const Color(0xFFF2F7F4);
  final Color cardBorder = const Color(0xFFDCE5E1);
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);
  final Color successBg = const Color(0xFFE6F4EA);
  final Color successText = const Color(0xFF14804A);

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

    // 🚀 THE NEW ENGINE: Listen to main.dart instead of a Timer!
    widget.syncTrigger.addListener(_fetchOrdersAndStats);
  }

  @override
  void dispose() {
    widget.syncTrigger.removeListener(
      _fetchOrdersAndStats,
    ); // 🚀 Clean up listener
    _audioPlayer.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  // 🚀 NEW: Guarantees the phone number ID is saved before anything else happens!
  Future<void> _initializeAppState() async {
    try {
      // 1. Fetch the profile directly from API
      final profile = await _apiService.fetchRestaurantProfile(
        widget.restaurantId,
      );
      if (profile != null) {
        // 2. Instantly save it to SQLite globally
        await DatabaseHelper.instance.saveSettings(profile);
      }
    } catch (e) {
      print("Failed to initialize profile on Orders screen: $e");
    }

    // 3. Now that settings are safe, load the names and orders!
    await _loadNameResolver();
    await _loadDeliveryBoys();
    await _fetchOrdersAndStats();
  }

  // 🚀 FIX: Bulletproof ID extractor
  String _getSafeId(Map<String, dynamic> o) {
    return o['_id']?.toString() ??
        o['id']?.toString() ??
        o['orderId']?.toString() ??
        '';
  }
  Future<void> _loadUnreadNumbers() async {
  try {
    final readSet = await DatabaseHelper.instance.getReadContactNumbers(
      widget.restaurantId,
    );
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''SELECT DISTINCT customer_number FROM messages
         WHERE restaurant_id = ?
           AND (direction = 'inbound' OR is_outgoing = 0)''',
      [widget.restaurantId],
    );
    final allInboundNumbers =
        rows.map((r) => r['customer_number'].toString()).toSet();
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
      // 🚀 ONLY READ FROM SQLITE! No more background API syncing here!
      final localData = await DatabaseHelper.instance.getAllOrders(
        widget.restaurantId,
      );

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

  // 🚀 Helper to handle the audio pings and selection logic cleanly
  // 🚀 Helper to handle the audio pings and selection logic cleanly
  void _processOrderState(List<dynamic> data) {
    if (_isFirstLoad) {
      for (var o in data) {
        _acknowledgedOrderIds.add(_getSafeId(o));
      }
      _isFirstLoad = false;
    } else {
      bool hasUnacknowledged = data.any(
        (o) => !_acknowledgedOrderIds.contains(_getSafeId(o)),
      );

      if (hasUnacknowledged) {
        try {
          if (_audioPlayer.state != PlayerState.playing) {
            _audioPlayer
                .play(AssetSource('sounds/notification.mp3'))
                .catchError((e) => print("Audio play suppressed"));
          }
        } catch (e) {
          print("Audio engine busy, skipping ping.");
        }
      } else {
        // 🚀 CRITICAL FIX: Stop the audio if all orders are acknowledged!
        try {
          if (_audioPlayer.state == PlayerState.playing) {
            _audioPlayer.stop();
          }
        } catch (e) {}
      }
    }

    if (_selectedOrder != null) {
      try {
        // 🚀 Search ALL orders (not filtered) so _selectedOrder isn't nulled out
        // when the status change moves it out of the active filter bucket.
        _selectedOrder = _orders.firstWhere(
          (o) => _getSafeId(o) == _getSafeId(_selectedOrder!),
        );
      } catch (e) {
        // Only null it if truly gone from the full list
        _selectedOrder = null;
      }
    }
  }

  // NOTE: orderId here must be the display ID (ORD-XXXXX), not MongoDB _id.

  // 🚀 FIX: Actual dynamic filtering logic
  List<dynamic> get _filteredOrders {
    return _orders.where((o) {
      // 1. Search Filter
      String orderId = o['orderId']?.toString().toLowerCase() ?? '';
      String phone = o['customerNumber']?.toString().toLowerCase() ?? '';
      String searchTarget = "$orderId $phone";
      if (_searchQuery.isNotEmpty &&
          !searchTarget.contains(_searchQuery.toLowerCase()))
        return false;

      // 2. Status & Date Filters
      String payStatus = (o['paymentStatus'] ?? 'pending')
          .toString()
          .toLowerCase();

      switch (_activeFilter) {
        case "Today":
          String rawDate = o['createdAt'] is Map
              ? (o['createdAt']['\$date'] ?? '')
              : (o['createdAt'] ?? '');
          DateTime? d = DateTime.tryParse(rawDate)?.toLocal();
          if (d != null) {
            DateTime now = DateTime.now();
            if (d.year != now.year || d.month != now.month || d.day != now.day)
              return false;
          }
          break;
        case "COD":
          if (payStatus != 'cod') return false;
          break;
        case "Pending":
          if (!{'pending', 'cod', 'online'}.contains(payStatus)) return false;
          break;
        case "Live":
          // Everything active: new orders + in-progress + assigned + online-paid (Razorpay)
          // "paid" is included because a Razorpay order is paid upfront but still needs
          // to be prepared and delivered — it must not be invisible in the live view.
          if (!{
            'pending',
            'cod',
            'online',
            'accepted',
            'preparing',
            'assigned',
            'paid',
            'ready',
          }.contains(payStatus))
            return false;
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
        case "Ready":                              // 🆕 ADD THIS BLOCK
          if (payStatus != 'ready') return false;
          break;  
        case "Completed":
          if (!{'completed', 'paid'}.contains(payStatus)) return false;
          break;
        case "Paid":
          if (payStatus != 'paid') return false;
          break;
        // "All" -> no filter
      }

      return true;
    }).toList();
  }

  // 🚀 FIX: Clean date/time extractors to avoid logic confusion
  String _formatFullDate(String rawDate) {
    if (rawDate.isEmpty) return "N/A";
    DateTime? parsed = DateTime.tryParse(rawDate)?.toLocal();
    if (parsed == null) return "N/A";
    // Format: DD/MM/YY HH:MM AM/PM  — matches physical receipt style
    int hour = parsed.hour;
    String ampm = hour >= 12 ? 'PM' : 'AM';
    int hour12 = hour % 12 == 0 ? 12 : hour % 12;
    String yy = parsed.year.toString().substring(2); // last 2 digits
    return "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/$yy ${hour12.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')} $ampm";
  }

  String _formatJustTime(String rawDate) {
    if (rawDate.isEmpty) return "N/A";
    DateTime? parsed = DateTime.tryParse(rawDate)?.toLocal();
    if (parsed == null) return "N/A";
    return "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
  }

  String _cleanTextForPDF(String text) {
    return text.replaceAll(
      RegExp(
        r'[\u{1F300}-\u{1F9FF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
        unicode: true,
      ),
      '',
    );
  }

  Future<void> _printKOT(
    Map<String, dynamic> order,
    String formattedDate,
  ) async {
    final pdf = pw.Document();
    String displayId = order['displayId'] ?? order['orderId'] ?? 'N/A';
    String customer = order['customerNumber'] ?? 'N/A';
    // Strip internal tags from notes before printing
    String rawNotes = order['additionalNotes'] ?? '';
    String notes = rawNotes
        .replaceAll('[ACCEPTED]', '')
        .replaceAll('[REJECTED]', '')
        .replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '')
        .trim();
    List<dynamic> items = order['items'] ?? [];

    // Load restaurant name & address from SQLite settings
    final settings = await DatabaseHelper.instance.getSettings();
    String restaurantName =
        settings?['name']?.toString().toUpperCase() ?? 'RESTAURANT';
    String restaurantAddress = settings?['address']?.toString() ?? '';

    // Calculate totals
    double subTotal = 0;
    for (var item in items) {
      double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      subTotal += price * qty;
    }
    double orderTotal =
        double.tryParse(order['totalAmount']?.toString() ?? '0') ?? subTotal;

    // Short order number for display (last 4 chars of displayId or full if short)
    String shortOrderNo = displayId.length > 4
        ? displayId.substring(displayId.length - 4)
        : displayId;

    pw.TextStyle bold(double size) =>
        pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size);
    pw.TextStyle normal(double size) => pw.TextStyle(fontSize: size);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ── HEADER ──────────────────────────────────────
              pw.Text(
                restaurantName,
                style: bold(13),
                textAlign: pw.TextAlign.center,
              ),
              if (restaurantAddress.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  restaurantAddress,
                  style: normal(8),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // ── ORDER META ──────────────────────────────────
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Order No : $shortOrderNo", style: bold(9)),
                  pw.Text("WhatsApp Order", style: bold(9)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text("Customer: +$customer", style: normal(8))],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Date & Time:", style: normal(8)),
                  pw.Text(formattedDate, style: normal(8)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // ── COLUMN HEADERS ───────────────────────────────
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text("Item", style: bold(9))),
                  pw.SizedBox(width: 4),
                  pw.Text("Qty", style: bold(9)),
                  pw.SizedBox(width: 8),
                  pw.Text("Price", style: bold(9)),
                  pw.SizedBox(width: 8),
                  pw.Text("Amt", style: bold(9)),
                ],
              ),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // ── ITEMS ────────────────────────────────────────
              ...items.map((item) {
                double price =
                    double.tryParse(item['price']?.toString() ?? '0') ?? 0;
                int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
                double amt = price * qty;
                String itemName = _cleanTextForPDF(
                  _resolveItemName(item['name'] ?? ''),
                );
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(itemName, style: bold(10)),
                      ),
                      pw.SizedBox(width: 4),
                      pw.SizedBox(
                        width: 22,
                        child: pw.Text(
                          "$qty",
                          style: normal(10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.SizedBox(
                        width: 38,
                        child: pw.Text(
                          price.toStringAsFixed(2),
                          style: normal(10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.SizedBox(
                        width: 38,
                        child: pw.Text(
                          amt.toStringAsFixed(2),
                          style: normal(10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // ── TOTALS ───────────────────────────────────────
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Sub Total", style: normal(9)),
                  pw.Text(subTotal.toStringAsFixed(2), style: normal(9)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("+GST", style: normal(9)),
                  pw.Text("0.00", style: normal(9)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Total =", style: bold(12)),
                  pw.Text(orderTotal.toStringAsFixed(2), style: bold(12)),
                ],
              ),
              pw.Divider(),

              // ── NOTES ────────────────────────────────────────
              if (notes.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text("Notes: ${_cleanTextForPDF(notes)}", style: bold(9)),
              ],

              // ── FOOTER ───────────────────────────────────────
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  "This is a Kitchen Order Ticket.\nNot a payment proof.",
                  style: normal(7),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text("*" * 32, style: normal(7))),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'KOT_$displayId',
    );
  }

  void _showNotesDialog(
    String orderId,
    String currentStatus,
    String currentNotes,
  ) {
    // Strip internal tags before showing to the user
    String cleanForDisplay = currentNotes
        .replaceAll('[ACCEPTED]', '')
        .replaceAll('[REJECTED]', '')
        .replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '')
        .trim();

    TextEditingController notesController = TextEditingController(
      text: cleanForDisplay,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          "Chef Notes",
          style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal),
        ),
        content: TextField(
          controller: notesController,
          decoration: InputDecoration(
            hintText: "E.g., Less spicy",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: primaryTeal, width: 2),
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryTeal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              // Re-attach any internal tags that were in the original notes
              String userText = notesController.text.trim();
              String tagsToKeep = '';
              if (currentNotes.contains('[ACCEPTED]'))
                tagsToKeep += '\n[ACCEPTED]';
              if (currentNotes.contains('[REJECTED]'))
                tagsToKeep += '\n[REJECTED]';
              // Preserve the delivery boy tag so assign info isn't lost when notes are edited
              final dbMatch = RegExp(
                r'\[DELIVERY_BOY:[^\]]*\]',
              ).firstMatch(currentNotes);
              if (dbMatch != null) tagsToKeep += '\n${dbMatch.group(0)}';
              String finalNotes = userText.isEmpty
                  ? tagsToKeep.trim()
                  : '$userText$tagsToKeep';

              bool ok = await _apiService.updateOrderStatus(
                restaurantId: widget.restaurantId,
                orderId: orderId,
                status: currentStatus,
                notes: finalNotes,
              );
              if (ok) _fetchOrdersAndStats();
            },
            child: const Text(
              "Save Notes",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMap(dynamic location) async {
    if (location is Map && location['lat'] != null && location['lng'] != null) {
      final lat = location['lat'];
      final lng = location['lng'];
      final Uri url = Uri.parse("https://www.google.com/maps?q=$lat,$lng");
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open Google Maps.")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location details not available.")),
      );
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
                              ? Center(
                                  child: Text(
                                    "No order selected",
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: _buildOrderInfoPanel(),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      flex: 5,
                                      child: _buildItemsPanel(),
                                    ),
                                  ],
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
        Text(
          "Live Orders",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: textDark,
          ),
        ),
        Text(
          "View and manage real-time WhatsApp orders",
          style: TextStyle(color: textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2, // 🚀 Compact search bar so filter chips don't overflow
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F0EC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: textMuted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: "Search ID or phone...",
                          hintStyle: TextStyle(color: textMuted, fontSize: 14),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
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
                    _buildFilterChip("All", Icons.list_alt_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip("Today", Icons.today_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip("COD", Icons.money),
                    const SizedBox(width: 8),
                    _buildFilterChip("Pending", Icons.hourglass_empty_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip("Live", Icons.bolt_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip("Accepted", Icons.check_circle_outline),
                    const SizedBox(width: 8),
                    _buildFilterChip("Assigned", Icons.motorcycle_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip("Ready", Icons.restaurant_rounded), 
                    const SizedBox(width: 8),
                    _buildFilterChip("Completed", Icons.done_all_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip("Paid", Icons.payments_rounded),
                    const SizedBox(width: 8),
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

  // Accent colors per filter chip
  Color _chipColor(String label) {
    switch (label) {
      case "COD":
        return Colors.orange.shade700;
      case "Pending":
        return Colors.orange.shade700;
      case "Live":
        return const Color(0xFF7C3AED); // purple
      case "Accepted":
        return const Color(0xFF1570EF); // blue
      case "Assigned":
        return const Color(0xFF0891B2); // cyan
      case "Completed":
        return const Color(0xFF14804A); // green
      case "Paid":
        return const Color(0xFF14804A); // green
      case "Rejected":
        return const Color(0xFFD92D20); // red
      default:
        return const Color(0xFF14804A);
    }
  }

  Widget _buildFilterChip(String label, [IconData? icon]) {
    bool isSelected = _activeFilter == label;
    final Color accent = _chipColor(label);
    final Color bg = isSelected ? accent.withOpacity(0.12) : Colors.white;
    final Color border = isSelected ? accent : cardBorder;
    final Color textColor = isSelected ? accent : textDark;

    return InkWell(
      onTap: () => setState(() {
        _activeFilter = label;
        _selectedOrder = null;
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check, size: 13, color: accent),
              const SizedBox(width: 4),
            ] else if (icon != null) ...[
              Icon(icon, size: 13, color: textMuted),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList() {
    final list = _filteredOrders; // Use active filtered list
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Order Records",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textDark,
                  ),
                ),
                Text(
                  "${list.length} records",
                  style: TextStyle(color: textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      "No orders found",
                      style: TextStyle(color: textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Color(0xFFF0F4F2)),
                    itemBuilder: (context, index) {
                      var o = list[index];
                      String uniqueId = _getSafeId(o);
                      bool isSelected =
                          _getSafeId(_selectedOrder ?? {}) == uniqueId;
                      bool isUnacknowledged = !_acknowledgedOrderIds.contains(
                        uniqueId,
                      );

                      // 🚀 NEW: Grab both IDs!
                      String mongoId = o['_id']?.toString() ?? '';
                      String displayId =
                          o['displayId']?.toString() ??
                          o['orderId']?.toString() ??
                          mongoId;

                      // Don't chop the text if it starts with 'ORD-'
                      String shortId = displayId.startsWith('ORD')
                          ? displayId
                          : (displayId.length > 8
                                ? displayId.substring(0, 8).toUpperCase()
                                : displayId);
                      String total = o['totalAmount']?.toString() ?? '0';
                      String payStatus = (o['paymentStatus'] ?? 'pending')
                          .toString()
                          .toLowerCase();
                      String rawDate = o['createdAt'] is Map
                          ? (o['createdAt']['\$date'] ?? '')
                          : (o['createdAt'] ?? '');

                      // 🚀 PIGGYBACK: Badge color reflects the full combined status
                      Color badgeBg;
                      Color badgeText;
                      if (payStatus == 'paid' || payStatus == 'completed') {
                        badgeBg = successBg;
                        badgeText = successText;
                      } else if (payStatus == 'accepted' ||
                          payStatus == 'preparing') {
                        badgeBg = Colors.blue.shade50;
                        badgeText = Colors.blue.shade800;
                      } else if (payStatus == 'assigned') {
                        badgeBg = Colors.purple.shade50;
                        badgeText = Colors.purple.shade800;
                      } else if (payStatus == 'rejected') {
                        badgeBg = const Color(0xFFFEF2F2);
                        badgeText = const Color(0xFFD92D20);
                      } else {
                        // pending / cod / online = orange = new order
                        badgeBg = Colors.orange.shade50;
                        badgeText = Colors.orange.shade800;
                      }

                      return AnimatedBuilder(
                        animation: _blinkColor,
                        builder: (context, child) {
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedOrder = o;
                                _acknowledgedOrderIds.add(uniqueId);

                                // 🚀 WINDOWS AUDIO CRASH FIX: Armored stop command
                                if (!list.any(
                                  (item) => !_acknowledgedOrderIds.contains(
                                    _getSafeId(item),
                                  ),
                                )) {
                                  try {
                                    _audioPlayer.stop();
                                  } catch (e) {
                                    print("Audio stop suppressed");
                                  }
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                // Blinks red if unacknowledged, stays green if selected, white otherwise
                                color: isUnacknowledged
                                    ? _blinkColor.value
                                    : (isSelected
                                          ? const Color(0xFFF4F9F7)
                                          : Colors.white),
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? primaryTeal
                                        : Colors.transparent,
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        shortId,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: isUnacknowledged
                                              ? Colors.red.shade700
                                              : primaryTeal,
                                        ),
                                      ),
                                      Text(
                                        "₹$total",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 12,
                                            color: textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatJustTime(rawDate),
                                            style: TextStyle(
                                              color: textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),

                                      // 🚀 FIX: Just use the Container here, no variables!
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeBg,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          payStatus.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: badgeText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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

  Widget _buildOrderInfoPanel() {
    if (_selectedOrder == null) return const SizedBox();
    String mongoId =
        _selectedOrder!['_id']?.toString() ?? ''; // Need this for the API!
    String displayId =
        _selectedOrder!['displayId']?.toString() ??
        _selectedOrder!['orderId']?.toString() ??
        mongoId;
    String phone = _selectedOrder!['customerNumber'] ?? '';
    String total = _selectedOrder!['totalAmount']?.toString() ?? '0';
    String rawDate = _selectedOrder!['createdAt'] is Map
        ? (_selectedOrder!['createdAt']['\$date'] ?? '')
        : (_selectedOrder!['createdAt'] ?? '');
    String payStatus = (_selectedOrder!['paymentStatus'] ?? 'pending')
        .toString()
        .toLowerCase();
    String notes = _selectedOrder!['additionalNotes'] ?? '';

    // Live badge: order is "live" until completed/paid/rejected
    bool isLive =
        payStatus != 'completed' &&
        payStatus != 'paid' &&
        payStatus != 'rejected';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 🚀 FIX: Wrap this Column in Expanded!
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayId,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: primaryTeal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "WhatsApp Order",
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12), // Give a little breathing room
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isLive ? successBg : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLive ? Icons.check_circle : Icons.done_all_rounded,
                      size: 14,
                      color: isLive ? successText : const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isLive ? "Live" : "Completed",
                      style: TextStyle(
                        color: isLive ? successText : const Color(0xFF3B82F6),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: primaryTeal),
              const SizedBox(width: 8),
              Text(
                "Order Information",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Customer Phone:", "+$phone"),
          _infoRow("Ordered Time:", _formatFullDate(rawDate)),
          // 🚀 Clean the secret tags out of the UI view
          Builder(
            builder: (context) {
              String cleanNotes = notes
                  .replaceAll('[ACCEPTED]', '')
                  .replaceAll('[REJECTED]', '')
                  .replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '')
                  .trim();
              if (cleanNotes.isNotEmpty) {
                return _infoRow("Chef Notes:", cleanNotes);
              }
              return const SizedBox();
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFE2EAE5)),
          ),
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: primaryTeal),
              const SizedBox(width: 8),
              Text(
                "Pricing",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Subtotal", "₹$total"),
          _infoRow("Tax", "₹0.00"),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total",
                style: TextStyle(fontWeight: FontWeight.bold, color: textDark),
              ),
              Text(
                "₹$total",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: primaryTeal,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFE2EAE5)),
          ),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: primaryTeal,
              ),
              const SizedBox(width: 8),
              Text(
                "Order Status",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 🚀 Status badge — read-only. Status only changes via the action buttons on the right.
          Builder(
            builder: (context) {
              // Map each status to a label + color pair
              final Map<String, Map<String, dynamic>> statusStyles = {
                'pending': {
                  'label': '⏳ Pending',
                  'bg': const Color(0xFFFFF7ED),
                  'text': const Color(0xFFC2410C),
                },
                'cod': {
                  'label': '💵 COD (Cash on Delivery)',
                  'bg': const Color(0xFFFFF7ED),
                  'text': const Color(0xFFC2410C),
                },
                'online': {
                  'label': '💳 Online Payment',
                  'bg': const Color(0xFFEFF6FF),
                  'text': const Color(0xFF1D4ED8),
                },
                'accepted': {
                  'label': '✅ Accepted',
                  'bg': const Color(0xFFE6F4EA),
                  'text': const Color(0xFF14804A),
                },
                'preparing': {
                  'label': '👨‍🍳 Preparing',
                  'bg': const Color(0xFFE6F4EA),
                  'text': const Color(0xFF14804A),
                },
                'assigned': {
                  'label': '🚴 Assigned to Delivery Boy',
                  'bg': const Color(0xFFF5F3FF),
                  'text': const Color(0xFF6D28D9),
                },
                'ready': {
                'label': '🍽️ Ready for Pickup',
                'bg': const Color(0xFFFEF3C7),
                'text': const Color(0xFFB45309),
                },
                'completed': {
                  'label': '🎉 Completed',
                  'bg': const Color(0xFFE6F4EA),
                  'text': const Color(0xFF14804A),
                },
                'paid': {
                  'label': '💰 Paid',
                  'bg': const Color(0xFFE6F4EA),
                  'text': const Color(0xFF14804A),
                },
                'rejected': {
                  'label': '❌ Rejected',
                  'bg': const Color(0xFFFEF2F2),
                  'text': const Color(0xFFD92D20),
                },
              };
              final style = statusStyles[payStatus] ?? statusStyles['pending']!;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: style['bg'] as Color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (style['text'] as Color).withOpacity(0.2),
                  ),
                ),
                child: Text(
                  style['label'] as String,
                  style: TextStyle(
                    color: style['text'] as Color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(color: textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              val,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: textDark,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsPanel() {
    if (_selectedOrder == null) return const SizedBox();
    List<dynamic> items = _selectedOrder!['items'] ?? [];
    String rawDate = _selectedOrder!['createdAt'] is Map
        ? (_selectedOrder!['createdAt']['\$date'] ?? '')
        : (_selectedOrder!['createdAt'] ?? '');
    String payStatus = (_selectedOrder!['paymentStatus'] ?? 'pending')
        .toString()
        .toLowerCase();
    String notes = _selectedOrder!['additionalNotes'] ?? '';
    // 🚀 PIGGYBACK: Use paymentStatus as the source of truth for the order flow.
    // isAccepted/isRejected/isAssigned/isCompleted all come from paymentStatus now.
    bool isRejected = payStatus == 'rejected' || notes.contains("[REJECTED]");
    bool isAccepted =
        payStatus == 'accepted' ||
        payStatus == 'preparing' ||
        notes.contains("[ACCEPTED]");
    bool isReady = payStatus == 'ready';    
    bool isAssigned = payStatus == 'assigned';
    bool isCompleted = payStatus == 'completed' || payStatus == 'paid';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 20,
                  color: primaryTeal,
                ),
                const SizedBox(width: 8),
                Text(
                  "Items (${items.length})",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textDark,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFF0F4F2)),
              itemBuilder: (context, index) {
                var item = items[index];
                // 🚀 FIX: Bulletproof integer and double parsing
                double price =
                    double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
                int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ✅ Fixed Code:
                            Text(
                              _resolveItemName(item['name'] ?? ''),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$qty × ₹$price",
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "₹${(price * qty).toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: primaryTeal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // 🚀 SMART FULFILLMENT FLOW: Buttons change based on piggybacked paymentStatus
                if (isRejected) ...[
                  // State 4: Rejected
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        "❌ Order Rejected",
                        style: TextStyle(
                          color: Color(0xFFD92D20),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ] else if (isCompleted) ...[
                  // State 5: Done
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F4EA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        "✅ Order Completed",
                        style: TextStyle(
                          color: Color(0xFF14804A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ] else if (isAssigned) ...[
                  // State 3: Assigned — show delivery boy info card + complete button
                  // Parse delivery boy name and phone from the embedded tag in notes
                  Builder(
                    builder: (ctx) {
                      String dbName = '';
                      String dbPhone = '';
                      final match = RegExp(
                        r'\[DELIVERY_BOY:([^|]+)\|([^\]]+)\]',
                      ).firstMatch(notes);
                      if (match != null) {
                        dbName = match.group(1) ?? '';
                        dbPhone = match.group(2) ?? '';
                      }
                      return Column(
                        children: [
                          // Delivery boy info card — always shown when isAssigned
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFDDD6FE),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEDE9FE),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.motorcycle_rounded,
                                    size: 18,
                                    color: Color(0xFF6D28D9),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Assigned to",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF6D28D9),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dbName.isNotEmpty
                                            ? dbName
                                            : 'Delivery Boy',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF3B0764),
                                        ),
                                      ),
                                      if (dbPhone.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          "+$dbPhone",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6D28D9),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _actionBtn(
                                  "Mark as Completed",
                                  Icons.check_circle_outline,
                                  const Color(0xFF14804A),
                                  Colors.white,
                                  () async {
                                    String mongoId =
                                        _selectedOrder!['_id']?.toString() ??
                                        '';
                                    String displayId =
                                        _selectedOrder!['displayId']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true
                                        ? _selectedOrder!['displayId']
                                              .toString()
                                        : _selectedOrder!['orderId']
                                                  ?.toString() ??
                                              mongoId;
                                    // Update local DB immediately (uses mongoId as PK)
                                    await DatabaseHelper.instance
                                        .updateOrderStatusLocally(
                                          widget.restaurantId,
                                          mongoId,
                                          'completed',
                                        );
                                    _fetchOrdersAndStats();
                                    // Fire API in background — use displayId (ORD-XXXXX), NOT mongoId
                                    _apiService
                                        .updateOrderStatus(
                                          restaurantId: widget.restaurantId,
                                          orderId: displayId,
                                          status: 'completed',
                                          notes: notes,
                                        )
                                        .then((ok) {
                                          if (!ok)
                                            print(
                                              '⚠️ Complete API call failed for $displayId — local DB already updated.',
                                            );
                                        });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ]else if (isReady) ...[
  // State 2b: TAKEAWAY order is ready — waiting for customer pickup
  Row(
    children: [
      Expanded(
        child: _actionBtn(
          "Mark as Picked Up",
          Icons.check_circle_outline,
          const Color(0xFF14804A),
          Colors.white,
          () async {
            String mongoId = _selectedOrder!['_id']?.toString() ?? '';
            String displayId =
                _selectedOrder!['displayId']?.toString().isNotEmpty == true
                    ? _selectedOrder!['displayId'].toString()
                    : _selectedOrder!['orderId']?.toString() ?? mongoId;
            String currentNotes = _selectedOrder!['additionalNotes'] ?? '';

            await DatabaseHelper.instance.updateOrderStatusLocally(
              widget.restaurantId,
              mongoId,
              'completed',
            );
            _fetchOrdersAndStats();

            _apiService
                .updateOrderStatus(
                  restaurantId: widget.restaurantId,
                  orderId: displayId,
                  status: 'completed',
                  notes: currentNotes,
                )
                .then((ok) {
                  if (!ok)
                    print(
                      '⚠️ Complete API call failed for $displayId — local DB already updated.',
                    );
                });
          },
        ),
      ),
    ],
  ),
] else if (isAccepted) ...[
  // State 2: Accepted/Preparing
  Builder(
    builder: (ctx) {
      final orderType = (_selectedOrder!['orderType'] ?? '')
          .toString()
          .toUpperCase();

      // 🥡 TAKEAWAY — notify customer the order is ready, don't assign a delivery boy
      if (orderType == 'TAKEAWAY') {
        return Row(
          children: [
            Expanded(
              child: _actionBtn(
                "Order Ready",
                Icons.notifications_active_rounded,
                const Color(0xFFB45309),
                Colors.white,
                () async {
                  if (_isProcessingAction) return;
                  setState(() => _isProcessingAction = true);
                  try {
                    String mongoId = _selectedOrder!['_id']?.toString() ?? '';
                    String displayId =
                        _selectedOrder!['displayId']?.toString().isNotEmpty == true
                            ? _selectedOrder!['displayId'].toString()
                            : _selectedOrder!['orderId']?.toString() ?? mongoId;
                    String phone = _selectedOrder!['customerNumber'] ?? '';
                    String currentNotes = _selectedOrder!['additionalNotes'] ?? '';

                    String msg =
                        '🍽️ Your order $displayId is ready!\n\n'
                        'Please come and pick up your order. Thank you! 🙏';

                    bool sent = await _sendOrderNotification(
                      phone,
                      msg,
                      templateFallback: 'two',
                      fallbackParams: [],
                    );

                    // Update local DB immediately
                    await DatabaseHelper.instance.updateOrderStatusLocally(
                      widget.restaurantId,
                      mongoId,
                      'ready',
                      notes: currentNotes,
                    );
                    _fetchOrdersAndStats();

                    // Fire API in background
                    _apiService
                        .updateOrderStatus(
                          restaurantId: widget.restaurantId,
                          orderId: displayId,
                          status: 'ready',
                          notes: currentNotes,
                        )
                        .then((ok) {
                          if (!ok)
                            print(
                              '⚠️ Ready status API call failed for $displayId — local DB already updated.',
                            );
                        });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            sent
                                ? "✅ Customer notified order is ready!"
                                : "⚠️ Marked ready, but WhatsApp message failed.",
                          ),
                          backgroundColor: sent
                              ? const Color(0xFF14804A)
                              : const Color(0xFFD92D20),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isProcessingAction = false);
                  }
                },
              ),
            ),
          ],
        );
      }

      // 🚚 DELIVERY — assign a delivery boy as before
      return Row(
        children: [
          Expanded(
            child: _actionBtn(
              "Assign Delivery Boy",
              Icons.motorcycle,
              const Color(0xFF1570EF),
              Colors.white,
              () => _showAssignDeliveryDialog(_selectedOrder!),
            ),
          ),
        ],
      );
    },
  ),
] else ...[
                  // State 1: New order (pending/cod/online) — Accept or Reject
                  Row(
                    children: [
                      Expanded(
                        child: _actionBtn(
                          "Accept Order",
                          Icons.check_circle,
                          const Color(0xFF14804A),
                          Colors.white,
                          () => _handleAcceptOrder(
                            Map<String, dynamic>.from(_selectedOrder!),
                            _formatFullDate(rawDate),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionBtn(
                          "Reject Order",
                          Icons.cancel,
                          const Color(0xFFD92D20),
                          Colors.white,
                          () => _handleRejectOrder(_selectedOrder!),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // 🚀 ROW 2: Utilities (Always visible)
                const SizedBox(height: 12),

                // 🚀 ROW 2: Utilities (Note, Chat, Map)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: _actionBtn(
                        "Chef Note",
                        Icons.edit_note,
                        Colors.white,
                        primaryTeal,
                        () => _showNotesDialog(
                          _selectedOrder!['orderId'],
                          _selectedOrder!['paymentStatus'] ?? 'pending',
                          _selectedOrder!['additionalNotes'] ?? '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
  child: _chatActionBtn(
    _selectedOrder!['customerNumber'] ?? '',
  ),
),

                    const SizedBox(width: 8),
                    // Hide Map button for TAKEAWAY orders or orders with no location
                    Builder(
                      builder: (ctx) {
                        final loc = _selectedOrder!['location'];
                        final orderType = (_selectedOrder!['orderType'] ?? '')
                            .toString()
                            .toUpperCase();
                        final hasLocation =
                            loc is Map &&
                            loc['lat'] != null &&
                            loc['lng'] != null;
                        if (orderType == 'TAKEAWAY' || !hasLocation) {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.store_outlined,
                                    size: 16,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      orderType == 'TAKEAWAY'
                                          ? "Takeaway"
                                          : "No Location",
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Expanded(
                          child: _actionBtn(
                            "Map",
                            Icons.location_on,
                            Colors.white,
                            primaryTeal,
                            () => _openMap(loc),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    Color bgColor,
    Color textColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: bgColor == Colors.white ? cardBorder : bgColor,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 4),
            // 🚀 FIX: Wrap Text in Flexible so the ellipsis actually works!
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 NEW: SQLite-backed Name Resolver
  Map<String, String> _itemNameResolver = {};
Widget _chatActionBtn(String customerNumber) {
  final bool hasUnread = _unreadNumbers.contains(customerNumber);
  return InkWell(
    onTap: () async {
      if (hasUnread) {
        await DatabaseHelper.instance.markContactAsRead(
          widget.restaurantId,
          customerNumber,
          '',
        );
        await _loadUnreadNumbers();
      }
      widget.onOrderContactSelected(customerNumber);
    },
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: cardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat, size: 16, color: primaryTeal),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  "Chat",
                  style: TextStyle(
                    color: primaryTeal,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (hasUnread)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
  // 🚀 Fetch all items from SQLite and build a fast lookup dictionary
  Future<void> _loadNameResolver() async {
    final items = await DatabaseHelper.instance.getAllMenuItems(
      widget.restaurantId,
    );
    Map<String, String> resolver = {};
    for (var item in items) {
      String id =
          item['retailerId']?.toString() ?? item['id']?.toString() ?? '';
      String name = item['name']?.toString() ?? 'Unknown Item';
      if (id.isNotEmpty) resolver[id] = name;
    }
    if (mounted) setState(() => _itemNameResolver = resolver);
  }

  // 🚀 FIX: The new local resolver (Replaces ApiService.resolveItemName)
  String _resolveItemName(String rawName) {
    if (!rawName.startsWith('tym_') && !rawName.contains('tym_'))
      return rawName;

    // Extract ID if Meta sent "Product tym_12345"
    String idToFind = rawName;
    final match = RegExp(r'tym_\d+').firstMatch(rawName);
    if (match != null) idToFind = match.group(0)!;

    return _itemNameResolver[idToFind] ?? rawName;
  }
  // ====================================================================
  // 🚀 AUTOMATED WHATSAPP ORDER ACTIONS
  // ====================================================================

  Future<bool> _sendOrderNotification(
    String phone,
    String text, {
    String? templateFallback,
    List<String> fallbackParams = const [],
  }) async {
    try {
      final settings = await DatabaseHelper.instance.getSettings();
      String phoneId = settings?['phoneNumberId']?.toString() ?? "";

      if (phoneId.isEmpty) {
        final profile = await _apiService.fetchRestaurantProfile(
          widget.restaurantId,
        );
        phoneId = profile?['phoneNumberId']?.toString() ?? "";
      }

      String rawPhone = phone.replaceAll('+', '').replaceAll(' ', '').trim();

      // Touch the session

      // 🚀 1. TRY PRIMARY: Send Normal Free-Form Text
      bool textSuccess = await _apiService.sendMessage(
        to: rawPhone,
        text: text,
        restaurantId: widget.restaurantId,
        phoneNumberId: phoneId,
      );

      // 🚀 2. TRY FALLBACK: If normal text failed (403 / 24h limit) and we have a template!
      if (!textSuccess && templateFallback != null) {
        print(
          "⚠️ Normal message blocked. Falling back to template: $templateFallback",
        );
        return await _apiService.sendTemplateMessage(
          restaurantId: widget.restaurantId,
          customerNumber: rawPhone,
          templateName: templateFallback, // e.g., "two" from your screenshot
          templateParams: fallbackParams,
        );
      }

      return textSuccess;
    } catch (e) {
      print("Failed to send order notification: $e");
      return false;
    }
  }

  void _handleAcceptOrder(
    Map<String, dynamic> order,
    String formattedDate,
  ) async {
    if (_isProcessingAction) return; // 🚀 Prevent double-clicks!
    setState(() => _isProcessingAction = true);
    try {
      // mongoId  = SQLite primary key  (used for local DB updates only)
      // displayId = ORD-XXXXX string   (used for ALL API calls — matches /api/orders/{orderId}/status)
      String mongoId = order['_id']?.toString() ?? '';
      String displayId = order['displayId']?.toString().isNotEmpty == true
          ? order['displayId'].toString()
          : order['orderId']?.toString() ?? mongoId;
      String phone = order['customerNumber'] ?? '';
      String currentNotes = order['additionalNotes'] ?? '';

      String newNotes = currentNotes.isEmpty
          ? "[ACCEPTED]"
          : "$currentNotes\n[ACCEPTED]";
      // 🚀 PIGGYBACK: Update local DB first (uses mongoId as PK), then fire API with displayId.
      await DatabaseHelper.instance.updateOrderStatusLocally(
        widget.restaurantId,
        mongoId,
        'accepted',
        notes: newNotes,
      );
      await _fetchOrdersAndStats(); // Refresh UI immediately with new local status

      // Fire the API in the background — use displayId (ORD-XXXXX), NOT mongoId
      _apiService
          .updateOrderStatus(
            restaurantId: widget.restaurantId,
            orderId: displayId,
            status: 'accepted',
            notes: newNotes,
          )
          .then((updated) {
            if (!updated)
              print(
                '⚠️ Accept API call failed for $displayId — local DB already updated.',
              );
          });

      // Print KOT instantly
      _printKOT(order, formattedDate);

      if (phone.isNotEmpty) {
        // 🚀 DYNAMICALLY BUILD THE RECEIPT
        String itemsStr = "";
        double calcSubtotal = 0;
        List<dynamic> items = order['items'] ?? [];

        for (var item in items) {
          String name = _resolveItemName(item['name'] ?? '');
          double price =
              double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          double lineTotal = price * qty;
          calcSubtotal += lineTotal;
          itemsStr += "* $name – ₹$price × $qty = ₹$lineTotal\n";
        }

        double total =
            double.tryParse(order['totalAmount']?.toString() ?? '0') ?? 0.0;
        double deliveryCharge = total - calcSubtotal;
        if (deliveryCharge < 0) deliveryCharge = 0;
        final settings = await DatabaseHelper.instance.getSettings();
      String restaurantName = settings?['name']?.toString().isNotEmpty == true
    ? settings!['name'].toString()
    : 'Our Restaurant';
        String orderType = (order['orderType'] ?? '').toString().toUpperCase();

String closingLine = orderType == 'TAKEAWAY'
    ? '''🍽️ We will inform you once your order is ready for pickup.
ഓർഡർ തയ്യാറാകുമ്പോൾ ഞങ്ങൾ നിങ്ങളെ അറിയിക്കും.'''
    : '''📞 The delivery boy will contact you soon.
ഡെലിവറി ബോയ് ഉടൻ തന്നെ നിങ്ങളെ ബന്ധപ്പെടും.''';

String msg =
    '''🎉 Order Confirmed! ✅

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

        bool success = await _sendOrderNotification(
          phone,
          msg,
          templateFallback: 'two',
          fallbackParams: [],
        );

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("✅ Order accepted! Customer notified."),
                backgroundColor: Color(0xFF14804A),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "⚠️ Order accepted, but WhatsApp message failed.",
                ),
                backgroundColor: Color(0xFFD92D20),
              ),
            );
          }
        }
      }
    } finally {
      setState(() => _isProcessingAction = false);
    }
  }

  void _handleRejectOrder(Map<String, dynamic> order) async {
    // mongoId  = SQLite primary key  (local DB updates only)
    // displayId = ORD-XXXXX string   (ALL API calls)
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString().isNotEmpty == true
        ? order['displayId'].toString()
        : order['orderId']?.toString() ?? mongoId;
    String phone = order['customerNumber'] ?? '';
    String currentNotes = order['additionalNotes'] ?? '';

    String newNotes = currentNotes.isEmpty
        ? "[REJECTED]"
        : "$currentNotes\n[REJECTED]";
    // 🚀 Always update local DB first so UI responds instantly
    await DatabaseHelper.instance.updateOrderStatusLocally(
      widget.restaurantId,
      mongoId,
      'rejected',
      notes: newNotes,
    );
    _fetchOrdersAndStats();

    // Fire API in background — use displayId (ORD-XXXXX), NOT mongoId
    _apiService
        .updateOrderStatus(
          restaurantId: widget.restaurantId,
          orderId: displayId,
          status: 'rejected',
          notes: newNotes,
        )
        .then((updated) {
          if (!updated)
            print(
              '⚠️ Reject API call failed for $displayId — local DB already updated.',
            );
        });

    if (phone.isNotEmpty) {
      final settings = await DatabaseHelper.instance.getSettings();
String restaurantName = settings?['name']?.toString().isNotEmpty == true
    ? settings!['name'].toString()
    : 'Our Restaurant';
      // 🚀 NEW REJECT MESSAGE FORMAT
      String msg =
          '''❌ Order Rejected

Sorry, your order #$displayId cannot be processed.

📌 Reason: Currently unavailable

🏪 $restaurantName''';

      bool success = await _sendOrderNotification(
        phone,
        msg,
        templateFallback: 'two',
        fallbackParams: [],
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Order rejected! Customer notified."),
              backgroundColor: Color(0xFF14804A),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("⚠️ Order rejected, but WhatsApp message failed."),
              backgroundColor: Color(0xFFD92D20),
            ),
          );
        }
      }
    }
  }

  // ====================================================================
  // 🚚 DELIVERY BOY MANAGEMENT
  // ====================================================================

  // SQLite-backed list — loaded on initState, updated on every add
  List<Map<String, String>> _deliveryBoys = [];

  Future<void> _loadDeliveryBoys() async {
    final boys = await DatabaseHelper.instance.getAllDeliveryBoys();
    if (mounted) setState(() => _deliveryBoys = boys);
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Assign Delivery Boy",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryTeal,
                      fontSize: 16,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: primaryTeal.withOpacity(0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    icon: Icon(Icons.add, size: 16, color: primaryTeal),
                    label: Text(
                      "Create New",
                      style: TextStyle(
                        color: primaryTeal,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () =>
                        _showCreateDeliveryBoyDialog(sbContext, setDialogState),
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
                            Icon(
                              Icons.motorcycle_outlined,
                              size: 48,
                              color: textMuted.withOpacity(0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "No delivery boys yet.\nTap \"Create New\" to add one.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${_deliveryBoys.length} delivery boy${_deliveryBoys.length > 1 ? 's' : ''} available",
                            style: TextStyle(color: textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _deliveryBoys.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: Color(0xFFF0F4F2),
                              ),
                              itemBuilder: (_, i) {
                                final boy = _deliveryBoys[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: primaryTeal.withOpacity(
                                      0.1,
                                    ),
                                    child: Text(
                                      (boy['name'] ?? '?')[0].toUpperCase(),
                                      style: TextStyle(
                                        color: primaryTeal,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    boy['name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "+${boy['phone'] ?? ''}",
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryTeal,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () async {
                                      Navigator.pop(dialogContext);
                                      await _assignDeliveryBoy(
                                        order,
                                        boy['phone']!,
                                        boy['name']!,
                                        screenContext,
                                      );
                                    },
                                    child: const Text(
                                      "Assign",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text("Cancel", style: TextStyle(color: textMuted)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateDeliveryBoyDialog(
    BuildContext parentContext,
    StateSetter setParentDialogState,
  ) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          "New Delivery Boy",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryTeal,
            fontSize: 16,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: "Name",
                  hintText: "e.g. Raju Kumar",
                  prefixIcon: Icon(Icons.person_outline, color: textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryTeal, width: 2),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? "Name is required" : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "WhatsApp Number",
                  hintText: "e.g. 9876543210  (without 91)",
                  prefixIcon: Icon(Icons.phone_outlined, color: textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryTeal, width: 2),
                  ),
                  helperText: "Country code 91 will be added automatically",
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return "Phone number is required";
                  final digits = v.trim().replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10) return "Enter at least 10 digits";
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryTeal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              // Strip ALL non-digits and any leading +
              String digits = phoneController.text.trim().replaceAll(
                RegExp(r'\D'),
                '',
              );

              // Normalize to always be 91XXXXXXXXXX (12 digits)
              // Case 1: user typed 10-digit local  → prepend 91
              // Case 2: user typed 919876543210    → already correct (starts with 91, 12 digits)
              // Case 3: user typed 9191...         → strip first 91, then re-prepend (prevents double)
              if (digits.length == 10) {
                digits = '91$digits'; // local → full
              } else if (digits.startsWith('91') && digits.length == 12) {
                // already perfect — do nothing
              } else if (digits.startsWith('9191') && digits.length == 14) {
                digits = digits.substring(2); // strip duplicate 91
              } else if (digits.startsWith('91') && digits.length > 12) {
                // extra digits — just keep the last 10 and prefix
                digits = '91${digits.substring(digits.length - 10)}';
              }

              final name = nameController.text.trim();
              Navigator.pop(ctx);

              // Save to SQLite
              await DatabaseHelper.instance.addDeliveryBoy(name, digits);

              // Reload the list and refresh parent dialog
              final updated = await DatabaseHelper.instance
                  .getAllDeliveryBoys();
              setParentDialogState(() {
                _deliveryBoys = updated;
              });
              if (mounted) setState(() => _deliveryBoys = updated);
            },
            child: const Text("Add", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _assignDeliveryBoy(
    Map<String, dynamic> order,
    String deliveryPhone,
    String deliveryName,
    BuildContext screenContext,
  ) async {
    // mongoId  = SQLite primary key  (local DB updates only)
    // displayId = ORD-XXXXX string   (ALL API calls)
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString().isNotEmpty == true
        ? order['displayId'].toString()
        : order['orderId']?.toString() ?? mongoId;
    String customerPhone = order['customerNumber'] ?? 'Unknown';
    String total = order['totalAmount']?.toString() ?? '0';
    String orderNotes = order['additionalNotes']?.toString() ?? '';

    String locationText = "No location provided";
    var loc = order['location'];
    if (loc is Map && loc['lat'] != null && loc['lng'] != null) {
      locationText =
          "https://www.google.com/maps?q=${loc['lat']},${loc['lng']}";
    }

    String itemsListStr = "";
    List<dynamic> itemsList = order['items'] ?? [];
    for (var item in itemsList) {
      String name = _resolveItemName(item['name'] ?? '');
      int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      itemsListStr += "$qty x $name\n";
    }

    String msg =
        '🚚 New Delivery Order\n\n🧾 Order ID: $displayId\n\n📞 +$customerPhone\n\n📍 $locationText\n\n🍽️ Items:\n$itemsListStr\n💰 Total: ₹$total';

    // 1. Send message to delivery boy
    bool deliverySuccess = await _sendOrderNotification(
      deliveryPhone,
      msg,
      templateFallback: 'two',
      fallbackParams: [],
    );

    // 2. Send message to customer telling them who their delivery boy is
    String cleanDeliveryPhone = deliveryPhone
        .replaceAll('+', '')
        .replaceAll(' ', '')
        .trim();
    String customerMsg =
        '🚴 Your delivery is on the way!\n\n'
        '📦 Order ID: $displayId\n\n'
        '🧑 Delivery Partner: $deliveryName\n'
        '📞 Contact: +$cleanDeliveryPhone\n\n'
        '🙏 Thank you for your order!';

    bool customerSuccess = await _sendOrderNotification(
      customerPhone,
      customerMsg,
      templateFallback: 'two',
      fallbackParams: [],
    );

    if (mongoId.isNotEmpty) {
      // 3. Embed delivery boy info in notes so the panel can display it
      // Format: existing notes + [DELIVERY_BOY:Name|Phone]
      String deliveryTag = '[DELIVERY_BOY:$deliveryName|$cleanDeliveryPhone]';
      // Strip any old delivery boy tag before writing the new one
      String cleanedNotes = orderNotes
          .replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '')
          .trim();
      String updatedNotes = cleanedNotes.isEmpty
          ? deliveryTag
          : '$cleanedNotes\n$deliveryTag';

      await DatabaseHelper.instance.updateOrderStatusLocally(
        widget.restaurantId,
        mongoId,
        'assigned',
        notes: updatedNotes,
      );
      _fetchOrdersAndStats();

      // Fire API in background — use displayId (ORD-XXXXX), NOT mongoId
      _apiService
          .updateOrderStatus(
            restaurantId: widget.restaurantId,
            orderId: displayId,
            status: 'assigned',
            notes: updatedNotes,
          )
          .then((ok) {
            if (!ok)
              print(
                '⚠️ Assign API call failed for $displayId — local DB already updated.',
              );
          });
    }

    if (mounted) {
      String snackMsg;
      if (deliverySuccess && customerSuccess) {
        snackMsg = "✅ Assigned to $deliveryName! Both messages sent.";
      } else if (deliverySuccess) {
        snackMsg = "✅ Assigned to $deliveryName. Customer notification failed.";
      } else if (customerSuccess) {
        snackMsg = "⚠️ Assigned to $deliveryName. Delivery boy message failed.";
      } else {
        snackMsg =
            "⚠️ Assigned to $deliveryName, but both WhatsApp messages failed.";
      }
      ScaffoldMessenger.of(screenContext).showSnackBar(
        SnackBar(
          content: Text(snackMsg),
          backgroundColor: (deliverySuccess || customerSuccess)
              ? const Color(0xFF14804A)
              : const Color(0xFFD92D20),
        ),
      );
    }
  }
}
