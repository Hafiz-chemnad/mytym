import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../services/api_service.dart';

class ChatDetailScreen extends StatefulWidget {
  final String phoneNumber;
  final String restaurantId;
  final String phoneNumberId;

  const ChatDetailScreen({
    super.key, 
    required this.phoneNumber, 
    required this.restaurantId,
    required this.phoneNumberId,
  });

  @override
  _ChatDetailScreenState createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _controller = TextEditingController();
  
  Timer? _pollingTimer;
  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false; 

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _fetchMessages();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // 🛡️ DEDUPLICATION HELPER: Extracts message body to track duplicates safely
  String _extractTextForDedup(dynamic m) {
    var content = m['messageContent'];
    if (content is Map) {
      if (content['text'] != null && content['text'] is Map) {
        return content['text']['body']?.toString() ?? "";
      } else if (content.containsKey('body')) {
        return content['body']?.toString() ?? "";
      }
    }
    return content?.toString() ?? m['messageText']?.toString() ?? m['message_text']?.toString() ?? "";
  }

Future<void> _fetchMessages() async {
    try {
      final data = await _apiService.fetchChatThread(widget.restaurantId, widget.phoneNumber);

      // 🚀 CRITICAL FIX: Sort OLDEST to NEWEST first!
      // This ensures the original message is processed before the ghost retries.
      data.sort((a, b) {
        DateTime d1 = DateTime.tryParse(a['createdAt'] ?? a['created_at'] ?? a['timestamp'] ?? '') ?? DateTime.now();
        DateTime d2 = DateTime.tryParse(b['createdAt'] ?? b['created_at'] ?? b['timestamp'] ?? '') ?? DateTime.now();
        return d1.compareTo(d2); 
      });

      final filteredData = <dynamic>[];
      final Set<String> seenWamids = {}; 

      for (var m in data) {
        String msgText = _extractTextForDedup(m).trim();
        DateTime msgTime = DateTime.tryParse(m['createdAt'] ?? m['created_at'] ?? m['timestamp'] ?? '') ?? DateTime.now();
        
        String direction = m['direction']?.toString().toLowerCase().trim() ?? '';
        String sender = m['sender']?.toString().toLowerCase().trim() ?? '';
        bool isOutgoing = m['isOutgoing'] == true || m['is_outgoing'] == true || direction.contains('out') || sender.contains('rest') || sender.contains('bot');

        // ---------------------------------------------------------
        // 1. THE WAMID FILTER (Only affects INCOMING customer messages)
        // ---------------------------------------------------------
        if (!isOutgoing) {
          String wamid = "";
          if (m['messageContent'] is Map && m['messageContent']['id'] != null) {
            wamid = m['messageContent']['id'].toString();
          }

          if (wamid.isNotEmpty && wamid.startsWith('wamid.')) {
            if (seenWamids.contains(wamid)) {
              continue; // 🚫 It is a newer ghost clone! Skip it.
            } else {
              seenWamids.add(wamid); // ✅ Keep the oldest original message.
            }
          }
        }

        // ---------------------------------------------------------
        // 2. STANDARD TEXT FILTER (For accidental human double-clicks)
        // ---------------------------------------------------------
        bool isDuplicate = filteredData.any((existingMsg) {
          String existingText = _extractTextForDedup(existingMsg).trim();
          DateTime existingTime = DateTime.tryParse(existingMsg['createdAt'] ?? existingMsg['created_at'] ?? existingMsg['timestamp'] ?? '') ?? DateTime.now();
          
          String exDirection = existingMsg['direction']?.toString().toLowerCase().trim() ?? '';
          String exSender = existingMsg['sender']?.toString().toLowerCase().trim() ?? '';
          bool existingOutgoing = existingMsg['isOutgoing'] == true || existingMsg['is_outgoing'] == true || exDirection.contains('out') || exSender.contains('rest') || exSender.contains('bot');

          if (msgText.isNotEmpty && msgText == existingText && isOutgoing == existingOutgoing) {
            if (msgTime.difference(existingTime).inSeconds.abs() <= 10) {
              return true;
            }
          }
          return false;
        });

        if (!isDuplicate) {
          filteredData.add(m);
        }
      }

      if (mounted) {
        setState(() {
          // 🚀 Re-reverse the list so the newest messages appear at the bottom of the UI
          _messages = filteredData.reversed.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Chat Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // 🕒 Formats clock time cleanly for chat bubbles (e.g., 10:42 AM)
  String _formatMsgTime(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";
    try {
      DateTime date = DateTime.parse(rawDate).toLocal();
      String period = date.hour >= 12 ? "PM" : "AM";
      int hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      String minute = date.minute.toString().padLeft(2, '0');
      return "$hour:$minute $period";
    } catch (e) {
      return "";
    }
  }

  Widget _buildMessageBody(String text, String mediaUrl, String mediaType, String fileName, bool isMine, bool isBot) {
    bool isPrivateLink = mediaUrl.contains('lookaside') || mediaUrl.contains('fbsbx');
    Color textColor = isMine ? const Color(0xFF0F172A) : const Color(0xFF1E293B);
    
    if (isPrivateLink) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffe2e8f0))
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF64748B)),
                SizedBox(width: 6),
                Text("Secured Media File", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text.isNotEmpty ? text : "This media is heavily secured. Please use your WhatsApp device to view this file.", 
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.3)
            ),
          ],
        ),
      );
    }

    if (mediaUrl.isEmpty) {
      return SelectableText(
        text.trim(), 
        style: TextStyle(fontSize: 15, color: textColor, height: 1.4, fontWeight: FontWeight.w500)
      );
    }

    IconData icon = Icons.attach_file_rounded;
    String label = "Open Attachment";
    
    if (mediaType == 'image') { icon = Icons.image_rounded; label = "View Image"; }
    else if (mediaType == 'video') { icon = Icons.video_library_rounded; label = "Play Video"; }
    else if (mediaType == 'audio') { icon = Icons.keyboard_voice_rounded; label = "Play Voice Note"; }
    else if (mediaType == 'document') { icon = Icons.description_rounded; label = fileName.isNotEmpty ? fileName : "Open Document"; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (text.isNotEmpty && !text.contains('RAW DATA')) ...[
          SelectableText(text, style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
        ],
        InkWell(
          onTap: () async {
            final Uri url = Uri.parse(mediaUrl);
            if (!await launchUrl(url, mode: LaunchMode.platformDefault)) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open file URL.")));
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine ? Colors.black.withOpacity(0.06) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: const Color(0xFF475569)),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label, 
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // 🎨 Slate Canvas Background
      /* appBar : AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF475569), Color(0xFF1E293B)]),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Icon(Icons.person_rounded, color: Colors.white, size: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "+${widget.phoneNumber}", 
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3)
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      const Text("WhatsApp Channel Live", style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      */
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.forum_outlined, size: 44, color: Color(0xFF94A3B8)),
                            SizedBox(height: 12),
                            Text("No messages in this chat loop", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        reverse: true, 
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          var content = m['messageContent'];
                          String msgText = "";
                          String mediaUrl = "";
                          String mediaType = "";
                          String fileName = "";
                          
                          if (content is Map) {
                            if (content['mediaUrl'] != null) mediaUrl = content['mediaUrl'].toString();
                            else if (content['cloudinary'] != null && content['cloudinary']['url'] != null) mediaUrl = content['cloudinary']['url'].toString();

                            if (content['image'] != null) {
                              mediaType = 'image';
                              if (mediaUrl.isEmpty && content['image']['url'] != null) mediaUrl = content['image']['url'].toString();
                            }
                            else if (content['video'] != null) {
                              mediaType = 'video';
                              if (mediaUrl.isEmpty && content['video']['url'] != null) mediaUrl = content['video']['url'].toString();
                            }
                            else if (content['audio'] != null) {
                              mediaType = 'audio';
                              if (mediaUrl.isEmpty && content['audio']['url'] != null) mediaUrl = content['audio']['url'].toString();
                            }
                            else if (content['document'] != null) {
                              mediaType = 'document';
                              fileName = content['document']['filename']?.toString() ?? "Document";
                              if (mediaUrl.isEmpty && content['document']['url'] != null) mediaUrl = content['document']['url'].toString();
                            }

                            if (content['text'] != null && content['text'] is Map) {
                              msgText = content['text']['body']?.toString() ?? "";
                            } 
                            else if (content['interactive'] != null && content['interactive'] is Map) {
                              var intObj = content['interactive'];
                              String iType = intObj['type']?.toString() ?? '';
                              
                              if (iType == 'button_reply' && intObj['button_reply'] != null) {
                                msgText = "🔘 " + (intObj['button_reply']['title']?.toString() ?? "Button Clicked");
                              } else if (iType == 'list_reply' && intObj['list_reply'] != null) {
                                msgText = "📋 " + (intObj['list_reply']['title']?.toString() ?? "List Selected");
                              } else {
                                String bodyText = intObj['body']?['text']?.toString() ?? "Interactive Menu";
                                String headerText = intObj['header']?['text']?.toString() ?? "";
                                if (headerText.isNotEmpty) {
                                  msgText = "🤖 *$headerText*\n$bodyText"; 
                                } else {
                                  msgText = "🤖 $bodyText";
                                }
                              }
                            } 
                            else if (content['type'] == 'template') {
                              msgText = "🤖 [WhatsApp Template]";
                              if (content['template'] != null && content['template']['name'] != null) {
                                msgText += "\nName: ${content['template']['name']}";
                              }
                            }
                            else if (content['location'] != null && content['location'] is Map) {
                              msgText = "📍 Location: ${content['location']['latitude']}, ${content['location']['longitude']}";
                            } 
                            else if (mediaUrl.isNotEmpty) {
                              msgText = content['caption']?.toString() ?? ""; 
                            }
                            else if (content.containsKey('body')) {
                              msgText = content['body']?.toString() ?? "";
                            }
                          } else {
                            msgText = content?.toString() ?? m['messageText']?.toString() ?? "";
                          }

                          if (msgText.trim().isEmpty && mediaUrl.isEmpty) {
                            msgText = "🤖 UNKNOWN STRUCTURE:\n${jsonEncode(content ?? m)}";
                          }

                          String direction = m['direction']?.toString().toLowerCase().trim() ?? '';
                          String sender = m['sender']?.toString().toLowerCase().trim() ?? '';
                          
                          bool isBotPrompt = (content is Map) && (content['type'] == 'template' || (content['interactive'] != null && content['interactive']['type'] != 'button_reply' && content['interactive']['type'] != 'list_reply'));
                          bool isBot = sender.contains('bot') || isBotPrompt;
                          bool isMine = direction.contains('out') || sender.contains('rest') || isBot || m['isOutgoing'] == true;
                          
                          String rawTime = m['createdAt']?.toString() ?? m['created_at']?.toString() ?? m['timestamp']?.toString() ?? "";
                          String formattedClock = _formatMsgTime(rawTime);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Align(
                              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isMine 
                                          ? (isBot ? const Color(0xFFEFF6FF) : const Color(0xFFE8F5E9)) // Bot=Blue, User=Soft Mint Green
                                          : Colors.white, 
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(isMine ? 16 : 4),
                                        bottomRight: Radius.circular(isMine ? 4 : 16),
                                      ),
                                      border: Border.all(
                                        color: isMine 
                                            ? (isBot ? const Color(0xFFDBEAFE) : const Color(0xFFC8E6C9)) 
                                            : const Color(0xFFE2E8F0),
                                        width: 1
                                      ),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 3, offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: _buildMessageBody(msgText, mediaUrl, mediaType, fileName, isMine, isBot), 
                                  ),
                                  if (formattedClock.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Padding(
                                      padding: EdgeInsets.only(right: isMine ? 4 : 0, left: !isMine ? 4 : 0),
                                      child: Text(
                                        formattedClock, 
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)
                                      ),
                                    )
                                  ]
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  // 💬 Ultra-Modern Floating Island Style Input Bar
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.sentiment_satisfied_alt_rounded, color: Color(0xFF64748B), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          hintText: "Type your reply...",
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _isSending ? null : () async { 
                if (_controller.text.trim().isNotEmpty) {
                  setState(() => _isSending = true); 
                  
                  String msg = _controller.text.trim();
                  _controller.clear();
                  
                  try {
                    await _apiService.sendMessage(
                      to: widget.phoneNumber, 
                      text: msg, 
                      restaurantId: widget.restaurantId,
                      phoneNumberId: widget.phoneNumberId, 
                    );
                    await _fetchMessages();
                  } catch (e) {
                    print("Send Message Failure: $e");
                  } finally {
                    if (mounted) setState(() => _isSending = false); 
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isSending ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (!_isSending) BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))
                  ]
                ),
                child: Center(
                  child: _isSending 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}