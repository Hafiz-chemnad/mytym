import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';

class ChatDetailScreen extends StatefulWidget {
  final String phoneNumber;
  final String restaurantId;
  final String phoneNumberId;
  final ValueNotifier<int> syncTrigger;

  const ChatDetailScreen({
    super.key,
    required this.phoneNumber,
    required this.restaurantId,
    required this.phoneNumberId,
    required this.syncTrigger,
  });

  @override
  _ChatDetailScreenState createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _charCount = ValueNotifier<int>(0);

  // 🚀 Media cache: mediaId → working proxy URL
  // Populated once from /api/customer/{phone}/media on open
  final Map<String, String> _mediaUrlCache = {};

  static const String _baseUrl = "https://tym-whatsapp-backend.onrender.com";

  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  bool _isScrolledUp = false;
  int _unreadWhileScrolled = 0;

  @override
  void initState() {
    super.initState();
    _loadMediaCache(); // 🚀 Pre-load all mediaIds for this customer
    _fetchMessages();

    _controller.addListener(() {
      _charCount.value = _controller.text.length;
    });

    _scrollController.addListener(() {
      if (_scrollController.offset > 300 && !_isScrolledUp) {
        setState(() => _isScrolledUp = true);
      } else if (_scrollController.offset <= 300 && _isScrolledUp) {
        setState(() {
          _isScrolledUp = false;
          _unreadWhileScrolled = 0;
        });
      }
    });

    widget.syncTrigger.addListener(_onSyncTriggered);
  }

  // 🚀 KEY FIX: Load all mediaIds for this customer upfront
  // GET /api/customer/{customerNumber}/media returns { media: [{type, mediaId, mimeType, timestamp}] }
  // We store mediaId → proxy URL so any message can look up its working URL instantly
  Future<void> _loadMediaCache() async {
    try {
      final url = Uri.parse(
        '$_baseUrl/api/customer/${widget.phoneNumber}/media?restaurantId=${widget.restaurantId}',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> mediaList = body['media'] ?? [];
        for (var item in mediaList) {
          final String? mediaId = item['mediaId']?.toString();
          if (mediaId != null && mediaId.isNotEmpty) {
            // Build the proxy URL — backend will stream the actual file
            _mediaUrlCache[mediaId] = '$_baseUrl/api/media/$mediaId';
          }
        }
        if (mounted)
        print(
          "✅ Media cache loaded: ${_mediaUrlCache.length} items for ${widget.phoneNumber}",
        );
      }
    } catch (e) {
      print("❌ Media cache load failed: $e");
    }
  }

  // 🚀 Resolve mediaId → working URL
  // Priority: cache (from /api/customer/media) → proxy URL directly → empty
  String _resolveMediaUrl(dynamic content, String mediaType) {
    if (content is! Map) return '';

    // Step 1: Check Cloudinary (always works, never expires)
    if (content['cloudinary'] != null && content['cloudinary']['url'] != null) {
      return content['cloudinary']['url'].toString();
    }
    if (content['mediaUrl'] != null &&
        content['mediaUrl'].toString().contains('cloudinary')) {
      return content['mediaUrl'].toString();
    }

    // Step 2: Extract mediaId from the media type object
    String mediaId = '';
    final mediaObj =
        content[mediaType]; // content['audio'], content['image'] etc.
    if (mediaObj is Map) {
      mediaId = mediaObj['id']?.toString() ?? '';
      // If no id in the sub-object, check top level
      if (mediaId.isEmpty) mediaId = content['mediaId']?.toString() ?? '';
    }

    // Step 3: If we have the mediaId in our cache, use the proxy URL
    if (mediaId.isNotEmpty && _mediaUrlCache.containsKey(mediaId)) {
      return _mediaUrlCache[mediaId]!;
    }

    // Step 4: Build proxy URL directly even if not in cache yet
    // The /api/media/{mediaId} might still work for recent messages (< 5 min)
    if (mediaId.isNotEmpty) {
      return '$_baseUrl/api/media/$mediaId';
    }

    // Step 5: Last resort - raw url from content (will likely be expired Meta link)
    if (mediaObj is Map && mediaObj['url'] != null) {
      return mediaObj['url'].toString();
    }
    if (content['mediaUrl'] != null) {
      return content['mediaUrl'].toString();
    }

    return '';
  }

  void _onSyncTriggered() {
    _fetchMessages(isPolling: true);
  }

  @override
  void dispose() {
    widget.syncTrigger.removeListener(_onSyncTriggered);
    _controller.dispose();
    _scrollController.dispose();
    _charCount.dispose();
    super.dispose();
  }

  String _extractTextForDedup(dynamic m) {
    var content = m['messageContent'];
    if (content is Map) {
      if (content['text'] != null && content['text'] is Map)
        return content['text']['body']?.toString() ?? "";
      if (content.containsKey('body')) return content['body']?.toString() ?? "";
    }
    return content?.toString() ??
        m['messageText']?.toString() ??
        m['message_text']?.toString() ??
        "";
  }

  Future<void> _fetchMessages({bool isPolling = false}) async {
    if (isPolling && _controller.text.trim().isNotEmpty && _messages.isNotEmpty)
      return;

    try {
      final localData = await DatabaseHelper.instance.getThreadForContact(
        widget.restaurantId,
        widget.phoneNumber,
      );

      if (isPolling) {
        _apiService.syncMessagesBackground(widget.restaurantId).then((_) async {
          final freshData = await DatabaseHelper.instance.getThreadForContact(
            widget.restaurantId,
            widget.phoneNumber,
          );
          if (mounted && freshData.length > _messages.length) {
            _processAndDisplayMessages(freshData, isPolling);
            // 🚀 Reload media cache when new messages arrive (they may have new mediaIds)
            _loadMediaCache();
          }
        });
      }

      _processAndDisplayMessages(localData, isPolling);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processAndDisplayMessages(List<dynamic> data, bool isPolling) {
    data.sort((a, b) {
      DateTime d1 =
          DateTime.tryParse(
            a['createdAt'] ?? a['created_at'] ?? a['timestamp'] ?? '',
          ) ??
          DateTime.now();
      DateTime d2 =
          DateTime.tryParse(
            b['createdAt'] ?? b['created_at'] ?? b['timestamp'] ?? '',
          ) ??
          DateTime.now();
      return d1.compareTo(d2);
    });

    final filteredData = <dynamic>[];
    final Set<String> seenWamids = {};
    int previousCount = _messages.length;

    for (var m in data) {
      String msgText = _extractTextForDedup(m).trim();
      DateTime msgTime =
          DateTime.tryParse(
            m['createdAt'] ?? m['created_at'] ?? m['timestamp'] ?? '',
          ) ??
          DateTime.now();

      String direction = m['direction']?.toString().toLowerCase().trim() ?? '';
      String sender = m['sender']?.toString().toLowerCase().trim() ?? '';
      bool isOutgoing =
          m['isOutgoing'] == true ||
          m['is_outgoing'] == true ||
          direction.contains('out') ||
          sender.contains('rest') ||
          sender.contains('bot');

      if (!isOutgoing) {
        String wamid = "";
        if (m['messageContent'] is Map && m['messageContent']['id'] != null)
          wamid = m['messageContent']['id'].toString();
        if (wamid.isNotEmpty && wamid.startsWith('wamid.')) {
          if (seenWamids.contains(wamid))
            continue;
          else
            seenWamids.add(wamid);
        }
      }

      bool isDuplicate = filteredData.any((existingMsg) {
        String existingText = _extractTextForDedup(existingMsg).trim();
        DateTime existingTime =
            DateTime.tryParse(
              existingMsg['createdAt'] ??
                  existingMsg['created_at'] ??
                  existingMsg['timestamp'] ??
                  '',
            ) ??
            DateTime.now();
        bool existingOutgoing =
            existingMsg['isOutgoing'] == true ||
            existingMsg['direction']?.toString().contains('out') == true;
        return (msgText.isNotEmpty &&
            msgText == existingText &&
            isOutgoing == existingOutgoing &&
            msgTime.difference(existingTime).inSeconds.abs() <= 10);
      });

      if (!isDuplicate) filteredData.add(m);
    }

    if (mounted) {
      final newReversedList = filteredData.reversed.toList();

      if (isPolling && newReversedList.length > previousCount) {
        var newMsgs = newReversedList.sublist(
          0,
          newReversedList.length - previousCount,
        );
        int incomingCount = newMsgs
            .where(
              (m) =>
                  !(m['isOutgoing'] == true ||
                      m['direction']?.toString().contains('out') == true),
            )
            .length;

        if (_isScrolledUp && incomingCount > 0) {
          _unreadWhileScrolled += incomingCount;
        } else if (!_isScrolledUp && incomingCount > 0) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients)
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
          });
        }
      }

      setState(() {
        var optimistics = _messages
            .where((m) => m['isOptimistic'] == true)
            .toList();
        optimistics.removeWhere(
          (opt) => newReversedList.any(
            (real) => _extractTextForDedup(real).trim() == opt['messageText'],
          ),
        );
        _messages = [...optimistics, ...newReversedList];
        _isLoading = false;
      });
    }
  }

  String _formatMsgTime(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";
    try {
      DateTime date = DateTime.parse(rawDate).toLocal();
      String period = date.hour >= 12 ? "PM" : "AM";
      int hour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);
      String minute = date.minute.toString().padLeft(2, '0');
      return "$hour:$minute $period";
    } catch (e) {
      return "";
    }
  }

  String _getDateSeparator(DateTime current, DateTime previous) {
    if (current.year == previous.year &&
        current.month == previous.month &&
        current.day == previous.day)
      return "";
    final now = DateTime.now();
    if (current.year == now.year &&
        current.month == now.month &&
        current.day == now.day)
      return "Today";
    final yesterday = now.subtract(const Duration(days: 1));
    if (current.year == yesterday.year &&
        current.month == yesterday.month &&
        current.day == yesterday.day)
      return "Yesterday";
    return DateFormat('d MMM yyyy').format(current);
  }

  // ════════════════════════════════════════════════════════════════
  // 🚀 MESSAGE BODY BUILDER
  // ════════════════════════════════════════════════════════════════
  Widget _buildMessageBody(
    String text,
    String mediaUrl,
    String mediaType,
    String fileName,
    bool isMine,
    bool isBot,
    dynamic rawContent,
  ) {
    final bool isWorkingUrl =
        mediaUrl.isNotEmpty &&
        (mediaUrl.contains('tym-whatsapp-backend.onrender.com/api/media/') ||
            mediaUrl.contains('cloudinary.com'));


    Color textColor = isMine
        ? const Color(0xFF0F172A)
        : const Color(0xFF1E293B);

    // ── LOCATION ──────────────────────────────────────────────────
    if (rawContent is Map && rawContent['location'] != null) {
      String lat =
          (rawContent['location']['latitude'] ??
                  rawContent['location']['lat'] ??
                  '0')
              .toString();
      String lng =
          (rawContent['location']['longitude'] ??
                  rawContent['location']['lng'] ??
                  '0')
              .toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📍 Shared Location",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            onPressed: () => launchUrl(
              Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
              ),
            ),
            icon: const Icon(Icons.map_rounded, size: 16),
            label: const Text("Open in Maps"),
          ),
        ],
      );
    }

    // ── IMAGE ──────────────────────────────────────────────────────
    if (mediaType == 'image') {
      if (isWorkingUrl) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _showFullScreenImage(context, mediaUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.cover,
                  width: 220,
                  loadingBuilder: (c, child, progress) => progress == null
                      ? child
                      : Container(
                          width: 220,
                          height: 160,
                          color: const Color(0xFFF1F5F9),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0F172A),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Loading image...",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                  errorBuilder: (c, e, s) =>
                      _mediaUnavailableTile(mediaType, fileName, isMine),
                ),
              ),
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                text.trim(),
                style: TextStyle(
                  fontSize: 15,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );
      }
      // No working URL for image
      return _mediaUnavailableTile(mediaType, fileName, isMine);
    }

    // ── VIDEO ──────────────────────────────────────────────────────
    if (mediaType == 'video') {
      return GestureDetector(
        onTap: isWorkingUrl
            ? () => launchUrl(
                Uri.parse(mediaUrl),
                mode: LaunchMode.externalApplication,
              )
            : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 220,
                height: 140,
                color: const Color(0xFF1E293B),
                child: const Center(
                  child: Icon(
                    Icons.video_file_rounded,
                    size: 48,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isWorkingUrl ? Colors.black54 : Colors.black26,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWorkingUrl
                    ? Icons.play_arrow_rounded
                    : Icons.hourglass_empty_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Text(
                isWorkingUrl
                    ? (text.isNotEmpty ? text : "Tap to play")
                    : "Media unavailable",
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    // ── AUDIO / VOICE NOTE ─────────────────────────────────────────
    if (mediaType == 'audio') {
      if (isWorkingUrl) {
        return GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(mediaUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isMine ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isMine
                    ? const Color(0xFFA7F3D0)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                // Waveform bars (visual only)
                Row(
                  children: List.generate(20, (i) {
                    final heights = [
                      6.0,
                      10.0,
                      16.0,
                      22.0,
                      14.0,
                      20.0,
                      8.0,
                      18.0,
                      24.0,
                      12.0,
                      22.0,
                      16.0,
                      10.0,
                      20.0,
                      14.0,
                      8.0,
                      18.0,
                      24.0,
                      12.0,
                      6.0,
                    ];
                    return Container(
                      width: 3,
                      height: heights[i],
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        );
      }

      // Audio mediaId exists but /api/media returned 500 (expired token on backend)
      // Show a clear "unavailable" tile instead of a broken button
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_off_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Voice Note",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  "Expired — ask customer to resend",
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ── DOCUMENT ───────────────────────────────────────────────────
    if (mediaType == 'document') {
      return GestureDetector(
        onTap: isWorkingUrl
            ? () => launchUrl(
                Uri.parse(mediaUrl),
                mode: LaunchMode.externalApplication,
              )
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_rounded,
                size: 28,
                color: isWorkingUrl
                    ? const Color(0xFF3B82F6)
                    : Colors.grey.shade400,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.isNotEmpty ? fileName : "Document",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isWorkingUrl ? "Tap to open" : "Unavailable",
                      style: TextStyle(
                        fontSize: 11,
                        color: isWorkingUrl
                            ? const Color(0xFF64748B)
                            : Colors.red.shade300,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isWorkingUrl
                    ? Icons.download_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      );
    }

    // ── PLAIN TEXT ─────────────────────────────────────────────────
    if (mediaUrl.isEmpty && mediaType.isEmpty) {
      return SelectableText(
        text.trim(),
        style: TextStyle(
          fontSize: 15,
          color: textColor,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    // ── FALLBACK (unknown/unsupported type) ────────────────────────
    if (text.isNotEmpty) {
      return SelectableText(
        text.trim(),
        style: TextStyle(
          fontSize: 15,
          color: textColor,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return const Text(
      "Unsupported message type",
      style: TextStyle(
        fontSize: 13,
        color: Color(0xFF94A3B8),
        fontStyle: FontStyle.italic,
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────
  Widget _mediaUnavailableTile(String type, String fileName, bool isMine) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_mediaIconFor(type), size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mediaLabelFor(type, fileName),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                "Media expired",
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _mediaIconFor(String type) {
    if (type == 'image') return Icons.image_rounded;
    if (type == 'video') return Icons.video_library_rounded;
    if (type == 'audio') return Icons.keyboard_voice_rounded;
    if (type == 'document') return Icons.description_rounded;
    return Icons.attach_file_rounded;
  }

  String _mediaLabelFor(String type, String fileName) {
    if (type == 'image') return "Image";
    if (type == 'video') return "Video";
    if (type == 'audio') return "Voice Note";
    if (type == 'document') return fileName.isNotEmpty ? fileName : "Document";
    return "Attachment";
  }

  void _showFullScreenImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Text(
                  "Failed to load image",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 🚀 BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _isLoading && _messages.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0F172A),
                        ),
                      )
                    : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.forum_outlined,
                              size: 44,
                              color: Color(0xFF94A3B8),
                            ),
                            SizedBox(height: 12),
                            Text(
                              "No messages in this chat",
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];

                          final prevM = (i < _messages.length - 1)
                              ? _messages[i + 1]
                              : null;
                          final nextM = (i > 0) ? _messages[i - 1] : null;

                          DateTime currentDt =
                              DateTime.tryParse(
                                m['createdAt'] ??
                                    m['created_at'] ??
                                    m['timestamp'] ??
                                    '',
                              )?.toLocal() ??
                              DateTime.now();
                          DateTime prevDt = prevM != null
                              ? (DateTime.tryParse(
                                      prevM['createdAt'] ??
                                          prevM['created_at'] ??
                                          prevM['timestamp'] ??
                                          '',
                                    )?.toLocal() ??
                                    DateTime.now())
                              : DateTime(2000);

                          String dateLabel = _getDateSeparator(
                            currentDt,
                            prevDt,
                          );

                          var content = m['messageContent'];
                          String msgText = "";
                          String mediaUrl = "";
                          String mediaType = "";
                          String fileName = "";
                          bool isOptimistic = m['isOptimistic'] == true;
                          bool isFailed = m['status'] == 'failed';

                          if (content is Map) {
                            // ── Detect media type first ──
                            if (content['image'] != null) {
                              mediaType = 'image';
                            } else if (content['video'] != null) {
                              mediaType = 'video';
                            } else if (content['audio'] != null) {
                              mediaType = 'audio';
                            } else if (content['document'] != null) {
                              mediaType = 'document';
                              fileName =
                                  content['document']['filename']?.toString() ??
                                  "Document";
                            }

                            // ── Resolve the best available URL ──
                            if (mediaType.isNotEmpty) {
                              mediaUrl = _resolveMediaUrl(content, mediaType);
                            }

                            // ── Extract text ──
                            if (content['text'] != null &&
                                content['text'] is Map) {
                              msgText =
                                  content['text']['body']?.toString() ?? "";
                            } else if (content['interactive'] != null &&
                                content['interactive'] is Map) {
                              var intObj = content['interactive'];
                              String iType = intObj['type']?.toString() ?? '';
                              if (iType == 'button_reply' &&
                                  intObj['button_reply'] != null) {
                                msgText =
                                    "🔘 " +
                                    (intObj['button_reply']['title']
                                            ?.toString() ??
                                        "Button Clicked");
                              } else if (iType == 'list_reply' &&
                                  intObj['list_reply'] != null) {
                                msgText =
                                    "📋 " +
                                    (intObj['list_reply']['title']
                                            ?.toString() ??
                                        "List Selected");
                              } else {
                                String bodyText =
                                    intObj['body']?['text']?.toString() ??
                                    "Interactive Menu";
                                String headerText =
                                    intObj['header']?['text']?.toString() ?? "";
                                msgText = headerText.isNotEmpty
                                    ? "🤖 *$headerText*\n$bodyText"
                                    : "🤖 $bodyText";
                              }
                            } else if (content['type'] == 'template') {
                              msgText = "🤖 [WhatsApp Template]";
                              if (content['template'] != null &&
                                  content['template']['name'] != null) {
                                msgText +=
                                    "\nName: ${content['template']['name']}";
                              }
                            } else if (content['location'] != null &&
                                content['location'] is Map) {
                              msgText = "📍 Shared Location";
                            } else if (mediaUrl.isNotEmpty) {
                              msgText = content['caption']?.toString() ?? "";
                            } else if (content.containsKey('body')) {
                              msgText = content['body']?.toString() ?? "";
                            }
                          } else {
                            msgText =
                                content?.toString() ??
                                m['messageText']?.toString() ??
                                "";
                          }

                          if (msgText.trim().isEmpty &&
                              mediaUrl.isEmpty &&
                              mediaType.isEmpty) {
                            msgText = "Unsupported message type";
                          }

                          String direction =
                              m['direction']?.toString().toLowerCase().trim() ??
                              '';
                          String sender =
                              m['sender']?.toString().toLowerCase().trim() ??
                              '';
                          bool isBotPrompt =
                              (content is Map) &&
                              (content['type'] == 'template' ||
                                  (content['interactive'] != null &&
                                      content['interactive']['type'] !=
                                          'button_reply' &&
                                      content['interactive']['type'] !=
                                          'list_reply'));
                          bool isBot = sender.contains('bot') || isBotPrompt;
                          bool isMine =
                              direction.contains('out') ||
                              sender.contains('rest') ||
                              isBot ||
                              m['isOutgoing'] == true;

                          bool nextIsMine =
                              nextM != null &&
                              (nextM['isOutgoing'] == true ||
                                  nextM['direction']?.toString().contains(
                                        'out',
                                      ) ==
                                      true ||
                                  nextM['sender']?.toString().contains(
                                        'rest',
                                      ) ==
                                      true);
                          bool isGroupedWithNext =
                              nextM != null && isMine == nextIsMine;

                          String rawTime =
                              m['createdAt']?.toString() ??
                              m['created_at']?.toString() ??
                              m['timestamp']?.toString() ??
                              "";
                          String formattedClock = _formatMsgTime(rawTime);

                          return Column(
                            children: [
                              if (dateLabel.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Text(
                                    dateLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),

                              GestureDetector(
                                onLongPress: () {
                                  if (msgText.isNotEmpty) {
                                    Clipboard.setData(
                                      ClipboardData(text: msgText),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Message copied"),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    top: isGroupedWithNext ? 2 : 6,
                                  ),
                                  child: Align(
                                    alignment: isMine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Opacity(
                                      opacity: isOptimistic
                                          ? (isFailed ? 1.0 : 0.6)
                                          : 1.0,
                                      child: Column(
                                        crossAxisAlignment: isMine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.72,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isFailed
                                                  ? const Color(0xFFFEF2F2)
                                                  : (isMine
                                                        ? (isBot
                                                              ? const Color(
                                                                  0xFFEFF6FF,
                                                                )
                                                              : const Color(
                                                                  0xFFE8F5E9,
                                                                ))
                                                        : Colors.white),
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(
                                                  16,
                                                ),
                                                topRight: const Radius.circular(
                                                  16,
                                                ),
                                                bottomLeft: Radius.circular(
                                                  isMine
                                                      ? 16
                                                      : (isGroupedWithNext
                                                            ? 16
                                                            : 4),
                                                ),
                                                bottomRight: Radius.circular(
                                                  isMine
                                                      ? (isGroupedWithNext
                                                            ? 16
                                                            : 4)
                                                      : 16,
                                                ),
                                              ),
                                              border: Border.all(
                                                color: isFailed
                                                    ? const Color(0xFFFECACA)
                                                    : (isMine
                                                          ? (isBot
                                                                ? const Color(
                                                                    0xFFDBEAFE,
                                                                  )
                                                                : const Color(
                                                                    0xFFC8E6C9,
                                                                  ))
                                                          : const Color(
                                                              0xFFE2E8F0,
                                                            )),
                                                width: isBot ? 1.5 : 1,
                                              ),
                                            ),
                                            child: _buildMessageBody(
                                              msgText,
                                              mediaUrl,
                                              mediaType,
                                              fileName,
                                              isMine,
                                              isBot,
                                              content,
                                            ),
                                          ),
                                          if (formattedClock.isNotEmpty ||
                                              isOptimistic) ...[
                                            const SizedBox(height: 3),
                                            Padding(
                                              padding: EdgeInsets.only(
                                                right: isMine ? 4 : 0,
                                                left: !isMine ? 4 : 0,
                                              ),
                                              child: Text(
                                                isFailed
                                                    ? "Failed to send"
                                                    : (isOptimistic
                                                          ? "Sending..."
                                                          : formattedClock),
                                                style: TextStyle(
                                                  color: isFailed
                                                      ? Colors.red
                                                      : const Color(0xFF94A3B8),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                if (_isScrolledUp)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () => _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: Badge(
                        isLabelVisible: _unreadWhileScrolled > 0,
                        label: Text(_unreadWhileScrolled.toString()),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _charCount,
              builder: (context, count, child) {
                if (count == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6, right: 60),
                  child: Text(
                    "$count / 4096",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: count > 4000
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF94A3B8),
                    ),
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
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            maxLines: 4,
                            minLines: 1,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              hintText: "Type your reply...",
                              hintStyle: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
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
                  valueListenable: _charCount,
                  builder: (context, count, child) {
                    bool canSend = count > 0 && !_isSending;
                    return GestureDetector(
                      onTap: canSend
                          ? () async {
                              setState(() => _isSending = true);
                              String msg = _controller.text.trim();
                              _controller.clear();

                              String optId =
                                  'opt_${DateTime.now().millisecondsSinceEpoch}';
                              setState(() {
                                _messages.insert(0, {
                                  'id': optId,
                                  'messageText': msg,
                                  'isOutgoing': true,
                                  'createdAt': DateTime.now().toIso8601String(),
                                  'isOptimistic': true,
                                });
                              });

                              try {
                                await _apiService.sendMessage(
                                  to: widget.phoneNumber,
                                  text: msg,
                                  restaurantId: widget.restaurantId,
                                  phoneNumberId: widget.phoneNumberId,
                                );
                                await _fetchMessages();
                              } catch (e) {
                                setState(() {
                                  int idx = _messages.indexWhere(
                                    (m) => m['id'] == optId,
                                  );
                                  if (idx != -1)
                                    _messages[idx]['status'] = 'failed';
                                });
                              } finally {
                                if (mounted) setState(() => _isSending = false);
                              }
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: canSend
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                            boxShadow: [
                              if (canSend)
                                BoxShadow(
                                  color: const Color(
                                    0xFF0F172A,
                                  ).withOpacity(0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                            ],
                          ),
                          child: Center(
                            child: _isSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
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
