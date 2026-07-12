import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueNotifier<int> charCount;
  final bool isSending;
  final bool isRecording;
  final Function(String text) onSendText;
  final Function(String type) onSendMedia;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.charCount,
    required this.isSending,
    required this.isRecording,
    required this.onSendText,
    required this.onSendMedia,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
      decoration: const BoxDecoration(
        color: Colors.white, 
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1))
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: charCount,
              builder: (context, count, child) {
                if (count == 0 && !isRecording) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6, right: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isRecording) ...[
                        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                        const SizedBox(width: 4),
                        const Text(
                          "Recording... Tap stop to send", 
                          style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)
                        ),
                      ] else if (count > 0) ...[
                        Text(
                          "$count / 4096", 
                          style: TextStyle(
                            fontSize: 11, 
                            fontWeight: FontWeight.w600, 
                            color: count > 4000 ? const Color(0xFFEF4444) : const Color(0xFF94A3B8)
                          )
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9), 
                      borderRadius: BorderRadius.circular(24), 
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1)
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF64748B)),
                          padding: EdgeInsets.zero,
                          onSelected: isSending ? (_) {} : (type) => onSendMedia(type),
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'image', child: Row(children: [Icon(Icons.image, size: 18), SizedBox(width: 8), Text('Image')])),
                            const PopupMenuItem(value: 'video', child: Row(children: [Icon(Icons.videocam, size: 18), SizedBox(width: 8), Text('Video')])),
                            const PopupMenuItem(value: 'audio', child: Row(children: [Icon(Icons.audiotrack, size: 18), SizedBox(width: 8), Text('Audio file')])),
                            const PopupMenuItem(value: 'document', child: Row(children: [Icon(Icons.description, size: 18), SizedBox(width: 8), Text('Document')])),
                          ],
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller, 
                            maxLines: 4, 
                            minLines: 1,
                            style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              hintText: "Type your reply...", 
                              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500), 
                              border: InputBorder.none, 
                              isDense: true, 
                              contentPadding: EdgeInsets.symmetric(vertical: 12)
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ValueListenableBuilder<int>(
                  valueListenable: charCount,
                  builder: (context, count, child) {
                    if (count == 0 && !isSending) {
                      return GestureDetector(
                        onTap: isRecording ? onStopRecording : onStartRecording,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: isRecording ? const Color(0xFFEF4444) : const Color(0xFF0F172A), 
                              shape: BoxShape.circle
                            ),
                            child: Center(
                              child: Icon(isRecording ? Icons.stop_rounded : Icons.mic, color: Colors.white, size: 20)
                            ),
                          ),
                        ),
                      );
                    }
                    bool canSend = count > 0 && !isSending;
                    return GestureDetector(
                      onTap: canSend
                          ? () {
                              final text = controller.text.trim();
                              controller.clear();
                              onSendText(text);
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: canSend ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1), 
                            shape: BoxShape.circle, 
                            boxShadow: [
                              if (canSend) BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))
                            ]
                          ),
                          child: Center(
                            child: isSending 
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 18)
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}