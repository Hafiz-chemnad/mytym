import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MenuGridCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int catIndex;
  final int itemIndex;
  final ValueChanged<bool> onToggleAvailability;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MenuGridCard({
    super.key,
    required this.item,
    required this.catIndex,
    required this.itemIndex,
    required this.onToggleAvailability,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    String imageUrl = item['imageUrl']?.toString() ?? '';
    String itemName = (item['name']?.toString() ?? item['title']?.toString() ?? 'UNKNOWN').toUpperCase();
    String price = "₹${double.tryParse(item['price'].toString())?.toStringAsFixed(2) ?? '0.00'}";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 55,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF096A56), // Matches your tymTealDark
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => _buildImagePlaceholder(),
                        )
                      : _buildImagePlaceholder(),
                ),
                Expanded(
                  flex: 45,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          itemName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          price,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF096A56)),
                        ),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: item['isAvailable'] ?? true,
                            activeColor: const Color(0xFF10B981),
                            onChanged: onToggleAvailability,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: InkWell(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF64748B)),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: InkWell(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(Icons.fastfood_outlined, size: 32, color: Color(0xFFCBD5E1)),
      ),
    );
  }
}