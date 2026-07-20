class OrderAssignment {
  final String id;
  final String orderId;
  final String displayId;
  final String deliveryBoyPhone;
  final String deliveryBoyName;
  final String deliveryStatus; // 'assigned' | 'db_accepted' | 'picked_up' | 'delivered'
  final String? paymentMethod; // 'cash' | 'gpay'
  final String assignedAt;
  final String? acceptedAt;
  final String? pickedUpAt;
  final String? deliveredAt;
  final double deliveryCharge;

  OrderAssignment({
    required this.id,
    required this.orderId,
    required this.displayId,
    required this.deliveryBoyPhone,
    required this.deliveryBoyName,
    required this.deliveryStatus,
    this.paymentMethod,
    required this.assignedAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    required this.deliveryCharge, // ✅ ADDED THIS
  });

  factory OrderAssignment.fromJson(Map<String, dynamic> json) {
    return OrderAssignment(
      id: json['id'] ?? '',
      orderId: json['order_id'] ?? '',
      displayId: json['display_id'] ?? '',
      deliveryBoyPhone: json['delivery_boy_phone'] ?? '',
      deliveryBoyName: json['delivery_boy_name'] ?? '',
      deliveryStatus: json['delivery_status'] ?? 'assigned',
      paymentMethod: json['payment_method'],
      assignedAt: json['assigned_at'] ?? '',
      acceptedAt: json['accepted_at'],
      pickedUpAt: json['picked_up_at'],
      deliveredAt: json['delivered_at'],
      deliveryCharge: double.tryParse(json['delivery_charge']?.toString() ?? '0') ?? 0.0,
    );
  }
}