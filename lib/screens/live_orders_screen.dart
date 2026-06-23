import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';

class LiveOrdersScreen extends StatefulWidget {
  final String restaurantId;
  final Function(String) onOrderContactSelected;

  const LiveOrdersScreen({super.key, required this.restaurantId, required this.onOrderContactSelected});

  @override
  _LiveOrdersScreenState createState() => _LiveOrdersScreenState();
}

class _LiveOrdersScreenState extends State<LiveOrdersScreen> {
  final ApiService _apiService = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _orders = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  Set<String> _knownOrderIds = {}; 

  // 🚀 New State for 3-Column Layout
  Map<String, dynamic>? _selectedOrder;

  // 🎨 POS Theme Colors extracted from Lead's UI
  final Color primaryTeal = const Color(0xFF096A56); // Dark Teal Text/Buttons
  final Color bgLight = const Color(0xFFF2F7F4); // Very light mint background
  final Color cardBorder = const Color(0xFFDCE5E1); // Subtle borders
  final Color textDark = const Color(0xFF1B2420);
  final Color textMuted = const Color(0xFF6B7A75);
  final Color successBg = const Color(0xFFE6F4EA);
  final Color successText = const Color(0xFF14804A);

  @override
  void initState() {
    super.initState();
    _fetchOrdersAndStats();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) => _fetchOrdersAndStats());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _fetchOrdersAndStats() async {
    try {
      final data = await _apiService.fetchLiveOrders(widget.restaurantId);
      
      if (_knownOrderIds.isNotEmpty) {
        bool shouldPlaySound = false;
        for (var order in data) {
          String id = order['orderId'] ?? '';
          if (id.isNotEmpty && !_knownOrderIds.contains(id)) {
            shouldPlaySound = true;
          }
        }
        if (shouldPlaySound) await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
      }
      
      _knownOrderIds = data.map<String>((o) => (o['orderId'] ?? '').toString()).toSet();

      data.sort((a, b) {
        String dateA = a['createdAt'] is Map ? (a['createdAt']['\$date'] ?? '').toString() : (a['createdAt'] ?? '').toString();
        String dateB = b['createdAt'] is Map ? (b['createdAt']['\$date'] ?? '').toString() : (b['createdAt'] ?? '').toString();
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _orders = data;
          _isLoading = false;
          // Auto-select first order if none selected
          if (_selectedOrder == null && _orders.isNotEmpty) {
            _selectedOrder = _orders.first;
          } else if (_selectedOrder != null && _orders.isNotEmpty) {
            // Update selected order data if it changed
            try {
              _selectedOrder = _orders.firstWhere((o) => o['orderId'] == _selectedOrder!['orderId']);
            } catch (e) {
              _selectedOrder = _orders.first;
            }
          }
        });
      }
    } catch (e) {
      print("Fetch Dashboard Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _cleanTextForPDF(String text) {
    return text.replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]', unicode: true), '');
  }

  Future<void> _printKOT(Map<String, dynamic> order, String formattedDate) async {
    final pdf = pw.Document();
    String orderId = order['orderId'] ?? 'N/A';
    String customer = order['customerNumber'] ?? 'N/A';
    String notes = order['additionalNotes'] ?? '';
    List<dynamic> items = order['items'] ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text("KITCHEN ORDER TICKET", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))),
                pw.SizedBox(height: 10),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 5),
                pw.Text("Order ID: ${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text("Date: $formattedDate", style: const pw.TextStyle(fontSize: 12)),
                pw.Text("Customer: +$customer", style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 5),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("ITEM", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.Text("QTY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  ]
                ),
                pw.SizedBox(height: 5),
                ...items.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(child: pw.Text(_cleanTextForPDF(item['name'] ?? ''), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14))),
                        pw.Text("x${item['qty'] ?? 1}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      ]
                    )
                  );
                }),
                pw.SizedBox(height: 5),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 5),
                if (notes.isNotEmpty) ...[
                  pw.Text("NOTES: ${_cleanTextForPDF(notes)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.SizedBox(height: 10),
                ],
                pw.Center(child: pw.Text("*** End ***", style: const pw.TextStyle(fontSize: 10))),
                pw.SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'KOT_$orderId');
  }

  void _showNotesDialog(String orderId, String currentStatus, String currentNotes) {
    TextEditingController notesController = TextEditingController(text: currentNotes);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Chef Notes", style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal)),
        content: TextField(
          controller: notesController,
          decoration: InputDecoration(
            hintText: "E.g., Less spicy",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryTeal, width: 2)),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              Navigator.pop(context);
              bool ok = await _apiService.updateOrderStatus(orderId: orderId, paymentStatus: currentStatus, notes: notesController.text.trim());
              if (ok) _fetchOrdersAndStats();
            },
            child: const Text("Save Notes", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _openMap(dynamic location) async {
    if (location is Map && location['lat'] != null && location['lng'] != null) {
      // 🚀 ഇവിടെ നമ്മൾ lat, lng എന്നിവ കൃത്യമായി ഡിക്ലയർ ചെയ്യുന്നു ✅
      final lat = location['lat'];
      final lng = location['lng'];
      
      // 🗺️ കറക്റ്റ് ആയ ഗൂഗിൾ മാപ്പ് സെർച്ച് URL
      final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
      
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open Google Maps.")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location details not available.")));
    }
  }

  String _formatDate(String rawDate) {
    if (rawDate.isEmpty) return "N/A";
    DateTime? parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return "N/A";
    return "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
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
                        // 🚀 Column 1: Order List (Left)
                        Expanded(flex: 3, child: _buildOrdersList()),
                        const SizedBox(width: 20),
                        // 🚀 Column 2 & 3: Order Details & Items (Right)
                        Expanded(flex: 7, child: _selectedOrder == null 
                          ? Center(child: Text("Select an order to view details", style: TextStyle(color: textMuted, fontSize: 16)))
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 4, child: _buildOrderInfoPanel()),
                                const SizedBox(width: 20),
                                Expanded(flex: 5, child: _buildItemsPanel()),
                              ],
                            )
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // 📝 1. Top Header (Search & Filters like Screenshot)
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
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                height: 44,
                decoration: BoxDecoration(color: const Color(0xFFE9F0EC), borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder)),
                child: Row(
                  children: [
                    Icon(Icons.search, color: textMuted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(decoration: InputDecoration(hintText: "Search by Order ID, customer, or phone...", hintStyle: TextStyle(color: textMuted, fontSize: 14), border: InputBorder.none))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            _filterChip("Today", true),
            const SizedBox(width: 8),
            _filterChip("Pending", false),
            const SizedBox(width: 8),
            _filterChip("Paid", false),
          ],
        )
      ],
    );
  }

  Widget _filterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? successBg : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? successText : cardBorder),
      ),
      child: Row(
        children: [
          if (isSelected) ...[Icon(Icons.check, size: 14, color: successText), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: isSelected ? successText : textDark, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        ],
      ),
    );
  }

  // 📝 2. Left Column: Master List
  Widget _buildOrdersList() {
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
                Text("${_orders.length} loaded", style: TextStyle(color: textMuted, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          Expanded(
            child: ListView.separated(
              itemCount: _orders.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF0F4F2)),
              itemBuilder: (context, index) {
                var o = _orders[index];
                bool isSelected = _selectedOrder?['orderId'] == o['orderId'];
                String id = o['orderId'] ?? '';
                String shortId = id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
                String total = o['totalAmount']?.toString() ?? '0';
                String payStatus = (o['paymentStatus'] ?? 'pending').toString().toLowerCase();
                String rawDate = o['createdAt'] is Map ? (o['createdAt']['\$date'] ?? '') : (o['createdAt'] ?? '');
                
                return InkWell(
                  onTap: () => setState(() => _selectedOrder = o),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFF4F9F7) : Colors.white,
                      border: Border(left: BorderSide(color: isSelected ? primaryTeal : Colors.transparent, width: 4))
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(shortId, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: primaryTeal)),
                            Text("₹$total", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 12, color: textMuted),
                                const SizedBox(width: 4),
                                Text(_formatDate(rawDate).split(' ').last, style: TextStyle(color: textMuted, fontSize: 12)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: payStatus == 'paid' ? successBg : Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text(payStatus.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: payStatus == 'paid' ? successText : Colors.orange.shade800)),
                            )
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  // 📝 3. Middle Column: Order Info & Pricing
  Widget _buildOrderInfoPanel() {
    if (_selectedOrder == null) return const SizedBox();
    String id = _selectedOrder!['orderId'] ?? '';
    String phone = _selectedOrder!['customerNumber'] ?? '';
    String total = _selectedOrder!['totalAmount']?.toString() ?? '0';
    String rawDate = _selectedOrder!['createdAt'] is Map ? (_selectedOrder!['createdAt']['\$date'] ?? '') : (_selectedOrder!['createdAt'] ?? '');
    String formattedDate = _formatDate(rawDate);
    String payStatus = (_selectedOrder!['paymentStatus'] ?? 'pending').toString().toLowerCase();
    String notes = _selectedOrder!['additionalNotes'] ?? '';

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(id.length > 8 ? id.substring(0, 8).toUpperCase() : id, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: primaryTeal)),
                  const SizedBox(height: 4),
                  Text("WhatsApp Order", style: TextStyle(color: textMuted, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: successBg, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 14, color: successText),
                    const SizedBox(width: 4),
                    Text("Live", style: TextStyle(color: successText, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 24),
          
          // Information Section
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: primaryTeal),
              const SizedBox(width: 8),
              Text("Order Information", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Customer Phone:", "+$phone"),
          _infoRow("Ordered Time:", formattedDate),
          if (notes.isNotEmpty) _infoRow("Chef Notes:", notes),
          
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFE2EAE5))),

          // Pricing Section
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: primaryTeal),
              const SizedBox(width: 8),
              Text("Pricing", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Subtotal", "₹$total"),
          _infoRow("Tax", "₹0.00"),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
              Text("₹$total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: primaryTeal)),
            ],
          ),

          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFE2EAE5))),

          // Payment Status Update
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 18, color: primaryTeal),
              const SizedBox(width: 8),
              Text("Payment Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: cardBorder), borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: payStatus == 'paid' ? 'paid' : 'pending',
                items: const [
                  DropdownMenuItem(value: 'paid', child: Text("Paid (Completed)")),
                  DropdownMenuItem(value: 'pending', child: Text("Pending")),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    bool ok = await _apiService.updateOrderStatus(orderId: id, paymentStatus: val, notes: notes);
                    if (ok) _fetchOrdersAndStats();
                  }
                },
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _infoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: TextStyle(color: textMuted, fontSize: 13))),
          Expanded(flex: 6, child: Text(val, textAlign: TextAlign.right, style: TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // 📝 4. Right Column: Items & Actions
  Widget _buildItemsPanel() {
    if (_selectedOrder == null) return const SizedBox();
    List<dynamic> items = _selectedOrder!['items'] ?? [];
    String rawDate = _selectedOrder!['createdAt'] is Map ? (_selectedOrder!['createdAt']['\$date'] ?? '') : (_selectedOrder!['createdAt'] ?? '');
    
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorder)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 20, color: primaryTeal),
                const SizedBox(width: 8),
                Text("Items (${items.length})", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF0F4F2)),
              itemBuilder: (context, index) {
                var item = items[index];
                double price = (item['price'] ?? 0).toDouble();
                int qty = item['qty'] ?? 1;
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
                            Text(item['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textDark)),
                            const SizedBox(height: 4),
                            Text("$qty × ₹$price", style: TextStyle(color: textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text("₹${price * qty}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTeal)),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2EAE5)),
          // Bottom Actions
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionBtn("Edit Note", Icons.edit_note, false, () => _showNotesDialog(_selectedOrder!['orderId'], _selectedOrder!['paymentStatus'] ?? 'pending', _selectedOrder!['additionalNotes'] ?? '')),
                _actionBtn("Chat", Icons.chat, false, () => widget.onOrderContactSelected(_selectedOrder!['customerNumber'])),
                _actionBtn("Map", Icons.location_on, false, () => _openMap(_selectedOrder!['location'])),
                _actionBtn("Print KOT", Icons.print, true, () => _printKOT(Map<String, dynamic>.from(_selectedOrder!), _formatDate(rawDate))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, bool isPrimary, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? primaryTeal : Colors.white,
          border: Border.all(color: isPrimary ? primaryTeal : cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : primaryTeal),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isPrimary ? Colors.white : primaryTeal, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}