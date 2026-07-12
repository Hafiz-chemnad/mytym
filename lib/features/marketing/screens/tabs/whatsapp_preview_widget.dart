import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class WhatsappPreviewWidget extends StatelessWidget {
  final Map<String, dynamic>? templateData;
  final Map<int, Map<String, dynamic>> variableMappings;
  final String? mediaUrl;
  final PlatformFile? mediaFile;

  const WhatsappPreviewWidget({
    super.key,
    required this.templateData,
    required this.variableMappings,
    this.mediaUrl,
    this.mediaFile,
  });

  String _getProcessedBody() {
    if (templateData == null) {
      return "Select a template on the left to see the preview.";
    }

    String? rawText;
    
    if (templateData!['body'] != null) {
      rawText = templateData!['body'].toString();
    } else if (templateData!['body_text'] != null) {
      rawText = templateData!['body_text'].toString();
    } else if (templateData!['text'] != null) {
      rawText = templateData!['text'].toString();
    } else if (templateData!['components'] is List) {
      // 🚀 THE FIX: Use orElse to prevent Dart from throwing StateErrors in the background
      var bodyComp = (templateData!['components'] as List).firstWhere(
        (c) => c is Map && c['type'] == 'BODY', 
        orElse: () => null, 
      );
      
      if (bodyComp != null) {
        rawText = bodyComp['text']?.toString();
      }
    }

    if (rawText == null || rawText.isEmpty) {
      return "Select a template on the left to see the preview.";
    }

    String text = rawText;

    variableMappings.forEach((key, map) {
      String type = map['type'] ?? 'custom';
      String val = map['value']?.toString() ?? '';

      if (type == 'name') {
        val = '[Customer Name]';
      } else if (type == 'phone') {
        val = '[Phone Number]';
      } else if (val.isEmpty) {
        val = '{{$key}}'; 
      }

      text = text.replaceAll('{{$key}}', val);
    });

    return text;
  }

  @override
  Widget build(BuildContext context) {
    // Standard WhatsApp Colors
    const Color waBackground = Color(0xFFEFEAE2);
    const Color waBubble = Colors.white;
    const Color waText = Color(0xFF111B21);
    const Color waMuted = Color(0xFF667781);
    const Color waButtonText = Color(0xFF00A884);

    return Container(
      color: waBackground,
      child: Stack(
        children: [
          // Simulated WhatsApp Doodle Background Pattern (Optional opacity layer)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.network(
                'https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png',
                repeat: ImageRepeat.repeat,
                errorBuilder: (ctx, err, stack) => const SizedBox(), // Fallback if no internet
              ),
            ),
          ),
          
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 350), // Mobile phone width
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Header
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)]),
                        child: Text("TODAY", style: TextStyle(fontSize: 12, color: waMuted, fontWeight: FontWeight.w500)),
                      ),
                    ),

                    // The Chat Bubble
                    Container(
                      decoration: BoxDecoration(
                        color: waBubble,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. HEADER (Image / Video / Doc Placeholder)
                          if (templateData?['header_type'] != null && templateData!['header_type'] != 'NONE') ...[
                            Container(
                              height: 140,
                              width: double.infinity,
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      templateData!['header_type'] == 'VIDEO' ? Icons.play_circle_fill : (templateData!['header_type'] == 'DOCUMENT' ? Icons.description : Icons.image),
                                      color: Colors.grey.shade400, size: 40,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      mediaFile != null ? mediaFile!.name : (mediaUrl?.isNotEmpty == true ? "URL Media Attached" : "Requires ${templateData!['header_type']}"),
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  ],
                                ),
                              ),
                            )
                          ],

                          // 2. BODY TEXT
                          Padding(
                            padding: const EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 4),
                            child: Text(
                              _getProcessedBody(),
                              style: const TextStyle(fontSize: 14.5, color: waText, height: 1.3),
                            ),
                          ),

                          // 3. FOOTER
                          if (templateData?['footer'] != null && templateData!['footer'].toString().isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
                              child: Text(
                                templateData!['footer'].toString(),
                                style: const TextStyle(fontSize: 12, color: waMuted),
                              ),
                            ),
                          ],

                          // Time Signature
                          Padding(
                            padding: const EdgeInsets.only(right: 10, bottom: 6),
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Text("10:42 AM", style: TextStyle(fontSize: 11, color: waMuted)),
                            ),
                          ),

                          // 4. BUTTONS
                          if (templateData?['buttons'] != null && (templateData!['buttons'] as List).isNotEmpty) ...[
                            const Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                            ...List.generate((templateData!['buttons'] as List).length, (index) {
                              var btn = templateData!['buttons'][index];
                              return Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(btn['type'] == 'URL' ? Icons.open_in_new : Icons.reply, size: 16, color: waButtonText),
                                        const SizedBox(width: 8),
                                        Text(btn['text'] ?? 'Button', style: const TextStyle(color: waButtonText, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                  if (index < (templateData!['buttons'] as List).length - 1)
                                    const Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F5)),
                                ],
                              );
                            })
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}