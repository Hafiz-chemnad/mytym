class ChatMessage {
  final String? id;
  final String? restaurantId;
  final String? customerNumber;
  final String text;
  final DateTime? createdAt;
  final bool isOutgoing;

  ChatMessage({
    this.id,
    this.restaurantId,
    this.customerNumber,
    required this.text,
    this.createdAt,
    required this.isOutgoing,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      // പുതിയ MongoDB API-യിൽ സാധാരണ '_id' എന്നാകും വരിക
      id: json['_id']?.toString() ?? json['id']?.toString(),
      
      // ലീഡിന്റെ API പ്രകാരമുള്ള camelCase ഡാറ്റ എടുക്കുന്നു
      restaurantId: json['restaurantId']?.toString() ?? json['restaurant_id']?.toString(),
      customerNumber: json['customerNumber']?.toString() ?? json['customer_number']?.toString(),
      
      text: json['messageText']?.toString() ?? json['message_text']?.toString() ?? "",
      
      // സമയം കൃത്യമായി മാറ്റുന്നു
      createdAt: (json['createdAt'] != null || json['created_at'] != null) 
          ? DateTime.tryParse((json['createdAt'] ?? json['created_at']).toString()) 
          : null,
          
      // bool വാല്യൂ
      isOutgoing: json['isOutgoing'] == true || json['is_outgoing'] == true,
    );
  }
}