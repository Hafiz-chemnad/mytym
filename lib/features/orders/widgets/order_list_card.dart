import 'package:flutter/material.dart';

class OrderListCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isSelected;
  final bool isUnacknowledged;
  final Color blinkColor;
  final VoidCallback onTap;

  const OrderListCard({
    super.key,
    required this.order,
    required this.isSelected,
    required this.isUnacknowledged,
    required this.blinkColor,
    required this.onTap,
  });

  String _formatJustTime(String rawDate) {
    if (rawDate.isEmpty) return "N/A";
    DateTime? parsed = DateTime.tryParse(rawDate)?.toLocal();
    if (parsed == null) return "N/A";
    return "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    String mongoId = order['_id']?.toString() ?? '';
    String displayId = order['displayId']?.toString() ?? order['orderId']?.toString() ?? mongoId;

    String shortId = displayId.startsWith('ORD')
        ? displayId
        : (displayId.length > 8 ? displayId.substring(0, 8).toUpperCase() : displayId);
    
    String total = order['totalAmount']?.toString() ?? '0';
    String payStatus = (order['paymentStatus'] ?? 'pending').toString().toLowerCase();
    String rawDate = order['createdAt'] is Map ? (order['createdAt']['\$date'] ?? '') : (order['createdAt'] ?? '');

    Color badgeBg;
    Color badgeText;
    if (payStatus == 'paid' || payStatus == 'completed') {
      badgeBg = const Color(0xFFE6F4EA);
      badgeText = const Color(0xFF14804A);
    } else if (payStatus == 'accepted' || payStatus == 'preparing') {
      badgeBg = Colors.blue.shade50;
      badgeText = Colors.blue.shade800;
    } else if (payStatus == 'assigned') {
      badgeBg = Colors.purple.shade50;
      badgeText = Colors.purple.shade800;
    } else if (payStatus == 'rejected') {
      badgeBg = const Color(0xFFFEF2F2);
      badgeText = const Color(0xFFD92D20);
    } else {
      badgeBg = Colors.orange.shade50;
      badgeText = Colors.orange.shade800;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUnacknowledged ? blinkColor : (isSelected ? const Color(0xFFF4F9F7) : Colors.white),
          border: Border(
            left: BorderSide(
              color: isSelected ? const Color(0xFF096A56) : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  shortId,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: isUnacknowledged ? Colors.red.shade700 : const Color(0xFF096A56),
                  ),
                ),
                Text("₹$total", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2420))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 12, color: Color(0xFF6B7A75)),
                    const SizedBox(width: 4),
                    Text(_formatJustTime(rawDate), style: const TextStyle(color: Color(0xFF6B7A75), fontSize: 12)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    payStatus.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}