import 'package:flutter/material.dart';

class OrderDetailPanel extends StatelessWidget {
  final Map<String, dynamic> order;
  final String Function(String) resolveItemName;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onAssignDelivery;
  final VoidCallback onMarkReady;
  final VoidCallback onMarkCompleted;
  final VoidCallback onChefNote;
  final VoidCallback onChat;
  final VoidCallback onMap;
  final bool hasUnreadChat;

  const OrderDetailPanel({
    super.key,
    required this.order,
    required this.resolveItemName,
    required this.onAccept,
    required this.onReject,
    required this.onAssignDelivery,
    required this.onMarkReady,
    required this.onMarkCompleted,
    required this.onChefNote,
    required this.onChat,
    required this.onMap,
    required this.hasUnreadChat,
  });

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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: _buildInfoPanel()),
        const SizedBox(width: 20),
        Expanded(flex: 5, child: _buildItemsPanel()),
      ],
    );
  }

  Widget _buildInfoPanel() {
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString() ?? order['orderId']?.toString() ?? mongoId;
    String phone = order['customerNumber'] ?? '';
    String total = order['totalAmount']?.toString() ?? '0';
    String rawDate = order['createdAt'] is Map ? (order['createdAt']['\$date'] ?? '') : (order['createdAt'] ?? '');
    String payStatus = (order['paymentStatus'] ?? 'pending').toString().toLowerCase();
    String notes = order['additionalNotes'] ?? '';

    bool isLive = payStatus != 'completed' && payStatus != 'paid' && payStatus != 'rejected';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5E1)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF096A56)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    const Text("WhatsApp Order", style: TextStyle(color: Color(0xFF6B7A75), fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isLive ? const Color(0xFFE6F4EA) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(isLive ? Icons.check_circle : Icons.done_all_rounded, size: 14, color: isLive ? const Color(0xFF14804A) : const Color(0xFF3B82F6)),
                    const SizedBox(width: 4),
                    Text(isLive ? "Live" : "Completed", style: TextStyle(color: isLive ? const Color(0xFF14804A) : const Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Color(0xFF096A56)),
              SizedBox(width: 8),
              Text("Order Information", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2420))),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Customer Phone:", "+$phone"),
          _infoRow("Ordered Time:", _formatFullDate(rawDate)),
          Builder(
            builder: (context) {
              String cleanNotes = notes.replaceAll('[ACCEPTED]', '').replaceAll('[REJECTED]', '').replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '').trim();
              if (cleanNotes.isNotEmpty) return _infoRow("Chef Notes:", cleanNotes);
              return const SizedBox();
            },
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFE2EAE5))),
          const Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: Color(0xFF096A56)),
              SizedBox(width: 8),
              Text("Pricing", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2420))),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Subtotal", "₹$total"),
          _infoRow("Tax", "₹0.00"),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B2420))),
              Text("₹$total", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF096A56))),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFE2EAE5))),
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFF096A56)),
              SizedBox(width: 8),
              Text("Order Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2420))),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final Map<String, Map<String, dynamic>> statusStyles = {
                'pending': {'label': '⏳ Pending', 'bg': const Color(0xFFFFF7ED), 'text': const Color(0xFFC2410C)},
                'cod': {'label': '💵 COD (Cash on Delivery)', 'bg': const Color(0xFFFFF7ED), 'text': const Color(0xFFC2410C)},
                'online': {'label': '💳 Online Payment', 'bg': const Color(0xFFEFF6FF), 'text': const Color(0xFF1D4ED8)},
                'accepted': {'label': '✅ Accepted', 'bg': const Color(0xFFE6F4EA), 'text': const Color(0xFF14804A)},
                'preparing': {'label': '👨‍🍳 Preparing', 'bg': const Color(0xFFE6F4EA), 'text': const Color(0xFF14804A)},
                'assigned': {'label': '🚴 Assigned to Delivery Boy', 'bg': const Color(0xFFF5F3FF), 'text': const Color(0xFF6D28D9)},
                'ready': {'label': '🍽️ Ready for Pickup', 'bg': const Color(0xFFFEF3C7), 'text': const Color(0xFFB45309)},
                'completed': {'label': '🎉 Completed', 'bg': const Color(0xFFE6F4EA), 'text': const Color(0xFF14804A)},
                'paid': {'label': '💰 Paid', 'bg': const Color(0xFFE6F4EA), 'text': const Color(0xFF14804A)},
                'rejected': {'label': '❌ Rejected', 'bg': const Color(0xFFFEF2F2), 'text': const Color(0xFFD92D20)},
              };
              final style = statusStyles[payStatus] ?? statusStyles['pending']!;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: style['bg'] as Color, borderRadius: BorderRadius.circular(8), border: Border.all(color: (style['text'] as Color).withOpacity(0.2))),
                child: Text(style['label'] as String, style: TextStyle(color: style['text'] as Color, fontWeight: FontWeight.bold, fontSize: 14)),
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
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Color(0xFF6B7A75), fontSize: 13))),
          Expanded(flex: 6, child: Text(val, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF1B2420), fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildItemsPanel() {
    List<dynamic> items = order['items'] ?? [];
    String payStatus = (order['paymentStatus'] ?? 'pending').toString().toLowerCase();
    String notes = order['additionalNotes'] ?? '';

    bool isRejected = payStatus == 'rejected' || notes.contains("[REJECTED]");
    bool isAccepted = payStatus == 'accepted' || payStatus == 'preparing' || notes.contains("[ACCEPTED]");
    bool isReady = payStatus == 'ready';    
    bool isAssigned = payStatus == 'assigned';
    bool isCompleted = payStatus == 'completed' || payStatus == 'paid';
    
    final loc = order['location'];
    final orderType = (order['orderType'] ?? '').toString().toUpperCase();
    final hasLocation = loc is Map && loc['lat'] != null && loc['lng'] != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5E1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined, size: 20, color: Color(0xFF096A56)),
                const SizedBox(width: 8),
                Text("Items (${items.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2420))),
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
                double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
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
                            Text(resolveItemName(item['name'] ?? ''), style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("$qty × ₹$price", style: const TextStyle(color: Color(0xFF6B7A75), fontSize: 12)),
                          ],
                        ),
                      ),
                      Text("₹${(price * qty).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF096A56))),
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
                if (isRejected) ...[
                  _statusCard("❌ Order Rejected", const Color(0xFFFEF2F2), const Color(0xFFD92D20)),
                ] else if (isCompleted) ...[
                  _statusCard("✅ Order Completed", const Color(0xFFE6F4EA), const Color(0xFF14804A)),
                ] else if (isAssigned) ...[
                  Builder(
                    builder: (ctx) {
                      String dbName = '';
                      String dbPhone = '';
                      final match = RegExp(r'\[DELIVERY_BOY:([^|]+)\|([^\]]+)\]').firstMatch(notes);
                      if (match != null) {
                        dbName = match.group(1) ?? '';
                        dbPhone = match.group(2) ?? '';
                      }
                      return Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDD6FE))),
                            child: Row(
                              children: [
                                Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.motorcycle_rounded, size: 18, color: Color(0xFF6D28D9))),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Assigned to", style: TextStyle(fontSize: 11, color: Color(0xFF6D28D9), fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 2),
                                      Text(dbName.isNotEmpty ? dbName : 'Delivery Boy', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF3B0764))),
                                      if (dbPhone.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Text("+$dbPhone", style: const TextStyle(fontSize: 12, color: Color(0xFF6D28D9))),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [Expanded(child: _actionBtn("Mark as Completed", Icons.check_circle_outline, const Color(0xFF14804A), Colors.white, onMarkCompleted))]),
                        ],
                      );
                    },
                  ),
                ] else if (isReady) ...[
                  Row(children: [Expanded(child: _actionBtn("Mark as Picked Up", Icons.check_circle_outline, const Color(0xFF14804A), Colors.white, onMarkCompleted))]),
                ] else if (isAccepted) ...[
                  if (orderType == 'TAKEAWAY')
                    Row(children: [Expanded(child: _actionBtn("Order Ready", Icons.notifications_active_rounded, const Color(0xFFB45309), Colors.white, onMarkReady))])
                  else
                    Row(children: [Expanded(child: _actionBtn("Assign Delivery Boy", Icons.motorcycle, const Color(0xFF1570EF), Colors.white, onAssignDelivery))]),
                ] else ...[
                  Row(
                    children: [
                      Expanded(child: _actionBtn("Accept Order", Icons.check_circle, const Color(0xFF14804A), Colors.white, onAccept)),
                      const SizedBox(width: 12),
                      Expanded(child: _actionBtn("Reject Order", Icons.cancel, const Color(0xFFD92D20), Colors.white, onReject)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _actionBtn("Chef Note", Icons.edit_note, Colors.white, const Color(0xFF096A56), onChefNote)),
                    const SizedBox(width: 8),
                    Expanded(child: _chatActionBtn(hasUnreadChat, onChat)),
                    const SizedBox(width: 8),
                    if (orderType == 'TAKEAWAY' || !hasLocation)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.store_outlined, size: 16, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Flexible(child: Text(orderType == 'TAKEAWAY' ? "Takeaway" : "No Location", style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(child: _actionBtn("Map", Icons.location_on, Colors.white, const Color(0xFF096A56), onMap)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String text, Color bg, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Center(child: Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color bgColor, Color textColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: bgColor == Colors.white ? const Color(0xFFDCE5E1) : bgColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _chatActionBtn(bool hasUnread, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDCE5E1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat, size: 16, color: Color(0xFF096A56)),
                SizedBox(width: 4),
                Flexible(child: Text("Chat", style: TextStyle(color: Color(0xFF096A56), fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (hasUnread)
              Positioned(
                top: -6,
                right: -6,
                child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );
  }
}