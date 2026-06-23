import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OrdersScreen extends StatefulWidget {
  final String restaurantId;

  const OrdersScreen({super.key, required this.restaurantId});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  Timer? _pollingTimer;
  List<dynamic> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    // 🔄 ഓരോ 5 സെക്കൻഡിലും ഓർഡറുകൾ പുതുക്കുന്നു
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) => _fetchOrders());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    try {
      final url = Uri.parse('https://tym-whatsapp-backend.onrender.com/api/orders/restaurant/${widget.restaurantId}');
      final response = await http.get(url);

      // orders_screen.dart ലെ മാറ്റം
if (response.statusCode == 200) {
  final Map<String, dynamic> data = jsonDecode(response.body);
  if (mounted) {
    setState(() {
      // ✅ 'data' അല്ലെങ്കിൽ 'orders' കീയിൽ നിന്ന് ഓർഡറുകൾ എടുക്കുന്നു
      _orders = data['data'] ?? data['orders'] ?? []; 
      _isLoading = false;
    });
  }
}
    } catch (e) {
      print("Orders Fetch Error: $e");
    }
  }

  // 🛠️ ഓർഡർ സ്റ്റാറ്റസ് അപ്ഡേറ്റ് ചെയ്യാൻ (Accept/Complete)
  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      final url = Uri.parse('https://tym-whatsapp-backend.onrender.com/api/orders/$orderId/status');
      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"paymentStatus": newStatus}), //
      );

      if (response.statusCode == 200) {
        _fetchOrders(); // സ്ക്രീൻ റീഫ്രഷ് ചെയ്യുന്നു
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Order $newStatus")));
      }
    } catch (e) {
      print("Update Status Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Live Orders",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _orders.isEmpty
                  ? const Center(child: Text("No orders yet."))
                  : ListView.builder(
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        return _buildOrderCard(order);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          "Order ID: ${order['_id']?.toString().substring(0, 8).toUpperCase() ?? 'N/A'}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text("Customer: ${order['customerNumber'] ?? 'N/A'}"),
        trailing: _statusBadge(order['paymentStatus'] ?? 'Pending'),
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Order Details:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // ഇവിടെ ഐറ്റംസ് ലിസ്റ്റ് ചെയ്യാം
                Text("Total: ₹${order['totalAmount'] ?? '0'}"),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _updateStatus(order['_id'], "Completed"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text("Accept Order", style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _updateStatus(order['_id'], "Cancelled"),
                      child: const Text("Reject"),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color = status == "Paid" ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}