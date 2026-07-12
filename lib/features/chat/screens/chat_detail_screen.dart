import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';

// 🚀 MODULAR IMPORTS
import '../../settings/services/settings_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/date_formatter.dart';
import '../services/chat_api.dart';
import '../services/chat_db.dart';
import '../services/media_service.dart';
import '../widgets/audio_bubble.dart';
import '../widgets/video_bubble.dart';
import '../widgets/chat_input_bar.dart';

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
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _charCount = ValueNotifier<int>(0);

  final Map<String, String> _mediaUrlCache = {};

  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;
  Timer? _expiryRefreshTimer;   // 🚀 ADDED

  bool _isScrolledUp = false;
  int _unreadWhileScrolled = 0;
  int _threadPage = 1;                    // 🚀 ADDED — tracks which page of history we're on
  bool _isLoadingOlder = false;            // 🚀 ADDED — shows spinner at top while fetching
  bool _hasMoreHistory = true;             // 🚀 ADDED — stops fetching once we hit the real beginning

  @override
  void initState() {
    super.initState();
    _loadMediaCache();
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

  // 🚀 ADDED — since the list is reverse:true, "top of history" is the
  // MAX scroll extent, not offset 0. Trigger a load when nearing it.
  if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
      !_isLoadingOlder &&
      _hasMoreHistory) {
    _loadOlderMessages();
  }
});
    _expiryRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) setState(() {});
  });
    widget.syncTrigger.addListener(_onSyncTriggered);
  }

  Future<void> _loadMediaCache() async {
    try {
      final url = Uri.parse(
        '${ApiClient.baseUrl}/api/customer/${widget.phoneNumber}/media?restaurantId=${widget.restaurantId}',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> mediaList = body['media'] ?? [];
        for (var item in mediaList) {
          final String? mediaId = item['mediaId']?.toString();
          if (mediaId != null && mediaId.isNotEmpty) {
            _mediaUrlCache[mediaId] = '${ApiClient.baseUrl}/api/media/$mediaId';
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Media cache load failed: $e");
    }
  }

  String _resolveMediaUrl(dynamic content, String mediaType) {
    if (content is! Map) return '';

    if (content['cloudinary'] != null && content['cloudinary']['url'] != null) {
      return content['cloudinary']['url'].toString();
    }
    if (content['mediaUrl'] != null && content['mediaUrl'].toString().contains('cloudinary')) {
      return content['mediaUrl'].toString();
    }

    String mediaId = '';
    final mediaObj = content[mediaType];
    if (mediaObj is Map) {
      mediaId = mediaObj['id']?.toString() ?? '';
      if (mediaId.isEmpty) mediaId = content['mediaId']?.toString() ?? '';
    }

    if (mediaId.isNotEmpty && _mediaUrlCache.containsKey(mediaId)) {
      return _mediaUrlCache[mediaId]!;
    }
    if (mediaId.isNotEmpty) {
      return '${ApiClient.baseUrl}/api/media/$mediaId';
    }
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
    _audioRecorder.dispose();
    _expiryRefreshTimer?.cancel();
    super.dispose();
  }
  Duration? _sessionRemaining() {
  DateTime? lastInbound;
  for (var m in _messages) {
    bool isOutgoing = m['isOutgoing'] == true || m['direction']?.toString().contains('out') == true;
    if (!isOutgoing) {
      DateTime? t = DateTime.tryParse(m['createdAt'] ?? m['created_at'] ?? m['timestamp'] ?? '');
      if (t != null && (lastInbound == null || t.isAfter(lastInbound))) {
        lastInbound = t;
      }
    }
  }
  if (lastInbound == null) return null; // no inbound message ever

  final expiry = lastInbound.toUtc().add(const Duration(hours: 24));
  final remaining = expiry.difference(DateTime.now().toUtc());
  return remaining; // negative Duration means already expired
}

  String _extractTextForDedup(dynamic m) {
    var content = m['messageContent'];
    if (content is Map) {
      if (content['text'] != null && content['text'] is Map) return content['text']['body']?.toString() ?? "";
      if (content.containsKey('body')) return content['body']?.toString() ?? "";
    }
    return content?.toString() ?? m['messageText']?.toString() ?? m['message_text']?.toString() ?? "";
  }

  Future<void> _fetchMessages({bool isPolling = false}) async {
    if (isPolling && _controller.text.trim().isNotEmpty && _messages.isNotEmpty) return;

    try {
      final localData = await ChatDbService.instance.getThreadForContact(
        widget.restaurantId,
        widget.phoneNumber,
      );

      _processAndDisplayMessages(localData, isPolling);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // 🚀 ADDED — lazy-loads the next page of older history for this contact only,
// triggered when the user scrolls near the top of what's currently loaded.
Future<void> _loadOlderMessages() async {
  if (_isLoadingOlder || !_hasMoreHistory) return;
  setState(() => _isLoadingOlder = true);

  try {
    final nextPage = _threadPage + 1;
    final older = await ChatApi.instance.fetchChatThread(
      widget.restaurantId,
      widget.phoneNumber,
      page: nextPage,
      limit: 50,
    );

    if (older.isEmpty) {
      _hasMoreHistory = false;
    } else {
      for (var msg in older) {
        await ChatDbService.instance.upsertMessage(widget.restaurantId, msg);
      }
      _threadPage = nextPage;

      final localData = await ChatDbService.instance.getThreadForContact(
        widget.restaurantId,
        widget.phoneNumber,
      );
      _processAndDisplayMessages(localData, false);

      if (older.length < 50) _hasMoreHistory = false; // last page was partial — nothing more
    }
  } catch (e) {
    debugPrint("❌ Load older messages failed: $e");
  } finally {
    if (mounted) setState(() => _isLoadingOlder = false);
  }
}

  void _processAndDisplayMessages(List<dynamic> data, bool isPolling) {
    data.sort((a, b) {
      DateTime d1 = DateTime.tryParse(a['createdAt'] ?? a['created_at'] ?? a['timestamp'] ?? '') ?? DateTime.now();
      DateTime d2 = DateTime.tryParse(b['createdAt'] ?? b['created_at'] ?? b['timestamp'] ?? '') ?? DateTime.now();
      return d1.compareTo(d2);
    });

    final filteredData = <dynamic>[];
    final Set<String> seenWamids = {};
    int previousCount = _messages.length;

    for (var m in data) {
      String msgText = _extractTextForDedup(m).trim();
      DateTime msgTime = DateTime.tryParse(m['createdAt'] ?? m['created_at'] ?? m['timestamp'] ?? '') ?? DateTime.now();
      String direction = m['direction']?.toString().toLowerCase().trim() ?? '';
      String sender = m['sender']?.toString().toLowerCase().trim() ?? '';
      bool isOutgoing = m['isOutgoing'] == true || m['is_outgoing'] == true || direction.contains('out') || sender.contains('rest') || sender.contains('bot');

      if (!isOutgoing) {
        String wamid = "";
        if (m['messageContent'] is Map && m['messageContent']['id'] != null) wamid = m['messageContent']['id'].toString();
        if (wamid.isNotEmpty && wamid.startsWith('wamid.')) {
          if (seenWamids.contains(wamid)) continue;
          seenWamids.add(wamid);
        }
      }

      bool isDuplicate = filteredData.any((existingMsg) {
        String existingText = _extractTextForDedup(existingMsg).trim();
        DateTime existingTime = DateTime.tryParse(existingMsg['createdAt'] ?? existingMsg['created_at'] ?? existingMsg['timestamp'] ?? '') ?? DateTime.now();
        bool existingOutgoing = existingMsg['isOutgoing'] == true || existingMsg['direction']?.toString().contains('out') == true;
        return (msgText.isNotEmpty && msgText == existingText && isOutgoing == existingOutgoing && msgTime.difference(existingTime).inSeconds.abs() <= 10);
      });

      if (!isDuplicate) filteredData.add(m);
    }

    if (mounted) {
      final newReversedList = filteredData.reversed.toList();

      if (isPolling && newReversedList.length > previousCount) {
        var newMsgs = newReversedList.sublist(0, newReversedList.length - previousCount);
        int incomingCount = newMsgs.where((m) => !(m['isOutgoing'] == true || m['direction']?.toString().contains('out') == true)).length;

        if (_isScrolledUp && incomingCount > 0) {
          _unreadWhileScrolled += incomingCount;
        } else if (!_isScrolledUp && incomingCount > 0) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          });
        }
      }

      setState(() {
        var optimistics = _messages.where((m) => m['isOptimistic'] == true).toList();
        optimistics.removeWhere((opt) {
          DateTime optTime = DateTime.parse(opt['createdAt']);
          if (DateTime.now().difference(optTime).inMinutes > 2) return true; // clear stale optimistic messages
          return newReversedList.any((real) {
             if (opt['messageType'] != null && real['messageType'] == opt['messageType']) {
                DateTime realTime = DateTime.tryParse(real['createdAt'] ?? real['timestamp'] ?? '') ?? DateTime.now();
                return realTime.difference(optTime).inSeconds.abs() < 15;
             }
             return _extractTextForDedup(real).trim() == (opt['messageText'] ?? '');
          });
        });
        _messages = [...optimistics, ...newReversedList];
        _isLoading = false;
      });
    }
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
    bool isOptimistic,
    bool isFailed,
  ) {
    Color textColor = isMine ? const Color(0xFF0F172A) : const Color(0xFF1E293B);

    // ── OPTIMISTIC / RETRY LOCAL FILE PREVIEW ──
    if (isOptimistic && rawContent is Map && rawContent['localFile'] != null) {
      String localPath = rawContent['localFile'];
      String optimisticCaption = rawContent['caption'] ?? '';
      bool isSending = rawContent['status'] == 'sending';

      Widget previewWidget;
      if (mediaType == 'image') {
        previewWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(localPath), width: 220, fit: BoxFit.cover),
        );
      } else if (mediaType == 'video') {
        previewWidget = Container(
          width: 220, height: 140,
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
          child: const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 48)),
        );
      } else if (mediaType == 'document') {
        previewWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_rounded, size: 28, color: Colors.grey),
              const SizedBox(width: 10),
              Flexible(child: Text(fileName.isNotEmpty ? fileName : "Document", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)))),
            ],
          ),
        );
      } else {
        previewWidget = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFC8E6C9))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mic, color: Colors.teal), SizedBox(width: 8), Text("Voice Note", style: TextStyle(fontWeight: FontWeight.bold))]),
        );
      }

      return Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: isFailed ? 0.4 : (isSending ? 0.6 : 1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                previewWidget,
                if (optimisticCaption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(optimisticCaption, style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500)),
                ]
              ],
            ),
          ),
          if (isSending && !isFailed)
            const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          if (isFailed)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.refresh_rounded, color: Colors.redAccent, size: 32),
            ),
        ],
      );
    }

    final bool isWorkingUrl = mediaUrl.isNotEmpty && (mediaUrl.contains('tym-whatsapp-backend.onrender.com/api/media/') || mediaUrl.contains('cloudinary.com'));

    if (rawContent is Map && rawContent['location'] != null) {
      String lat = (rawContent['location']['latitude'] ?? rawContent['location']['lat'] ?? '0').toString();
      String lng = (rawContent['location']['longitude'] ?? rawContent['location']['lng'] ?? '0').toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("📍 Shared Location", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0, side: const BorderSide(color: Color(0xFFE2E8F0))),
            onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng')),
            icon: const Icon(Icons.map_rounded, size: 16),
            label: const Text("Open in Maps"),
          ),
        ],
      );
    }

    if (mediaType == 'image') {
      if (isWorkingUrl) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _showFullScreenImage(context, mediaUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280, minWidth: 220),
                  child: CachedNetworkImage(
                    imageUrl: mediaUrl,
                    fit: BoxFit.cover,
                    width: 220,
                    placeholder: (context, url) => Container(
                      width: 220, 
                      height: 160, 
                      color: const Color(0xFFF1F5F9), 
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: const [
                          CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)), 
                          SizedBox(height: 8), 
                          Text("Loading image...", style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))
                        ]
                      )
                    ),
                    errorWidget: (context, url, error) => _mediaUnavailableTile(mediaType, fileName, isMine),
                  ),
                ),
              ),
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(text.trim(), style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500)),
            ],
          ],
        );
      }
      return _mediaUnavailableTile(mediaType, fileName, isMine);
    }

    if (mediaType == 'video') {
      if (!isWorkingUrl) {
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Container(width: 220, height: 140, color: const Color(0xFF1E293B), child: const Center(child: Icon(Icons.video_file_rounded, size: 48, color: Colors.white38)))),
            Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle), child: const Icon(Icons.hourglass_empty_rounded, color: Colors.white, size: 32)),
            const Positioned(bottom: 8, left: 8, child: Text("Media unavailable", style: TextStyle(color: Colors.white70, fontSize: 11))),
          ],
        );
      }
      return VideoBubble(mediaUrl: mediaUrl, caption: text);
    }

    if (mediaType == 'audio') {
      if (isWorkingUrl) return AudioBubble(mediaUrl: mediaUrl, isMine: isMine);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: isMine ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle), child: const Icon(Icons.mic_off_rounded, color: Colors.white, size: 22)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text("Voice Note", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))), SizedBox(height: 2), Text("Expired — ask customer to resend", style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))]),
          ],
        ),
      );
    }

    if (mediaType == 'document') {
      return GestureDetector(
        onTap: isWorkingUrl ? () => launchUrl(Uri.parse(mediaUrl), mode: LaunchMode.externalApplication) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_rounded, size: 28, color: isWorkingUrl ? const Color(0xFF3B82F6) : Colors.grey.shade400),
              const SizedBox(width: 10),
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(fileName.isNotEmpty ? fileName : "Document", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))), const SizedBox(height: 2), Text(isWorkingUrl ? "Tap to open" : "Unavailable", style: TextStyle(fontSize: 11, color: isWorkingUrl ? const Color(0xFF64748B) : Colors.red.shade300))])),
              const SizedBox(width: 8),
              Icon(isWorkingUrl ? Icons.download_rounded : Icons.error_outline_rounded, size: 18, color: const Color(0xFF94A3B8)),
            ],
          ),
        ),
      );
    }

    if (text.isNotEmpty) return SelectableText(text.trim(), style: TextStyle(fontSize: 15, color: textColor, height: 1.4, fontWeight: FontWeight.w500));
    return const Text("Unsupported message type", style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic));
  }

  Widget _mediaUnavailableTile(String type, String fileName, bool isMine) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: isMine ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_mediaIconFor(type), size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_mediaLabelFor(type, fileName), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))), const SizedBox(height: 2), const Text("Media expired", style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))]),
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), actions: [IconButton(icon: const Icon(Icons.open_in_new_rounded), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication))]), body: Center(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Text("Failed to load image", style: TextStyle(color: Colors.white))))))));
  }

  Future<void> _retryMessage(Map<String, dynamic> msg) async {
    setState(() => _messages.remove(msg));
    var content = msg['messageContent'];
    if (content is Map && content['localFile'] != null) {
      File file = File(content['localFile']);
      String type = msg['messageType'] ?? '';
      String caption = content['caption'] ?? '';
      String? filename = content['document']?['filename'];
      await _sendMediaFile(file, type, filename: filename, caption: caption);
    } else {
      _controller.text = msg['messageText'] ?? '';
    }
  }

  // ════════════════════════════════════════════════════════════════
  // 🚀 INPUT LOGIC
  // ════════════════════════════════════════════════════════════════
  Future<void> _pickAndSendMedia(String type) async {
    FileType pickType = type == 'image' ? FileType.image : type == 'video' ? FileType.video : type == 'audio' ? FileType.audio : FileType.any;
    final result = await FilePicker.platform.pickFiles(type: pickType);
    if (result == null || result.files.single.path == null) return;

    File file = File(result.files.single.path!);
    final fileName = result.files.single.name;

    // Skip compression on Windows/Linux to prevent UnimplementedError crash
    if (type == 'image') {
      if (!Platform.isWindows && !Platform.isLinux) {
        try {
          final targetPath = file.path.replaceAll(RegExp(r'\.(png|jpg|jpeg)$'), '_compressed.jpg');
          var compressed = await FlutterImageCompress.compressAndGetFile(file.absolute.path, targetPath, quality: 70);
          if (compressed != null) file = File(compressed.path);
        } catch (e) {
          debugPrint("Image compression failed, using original file.");
        }
      }
    }

    String caption = '';
    if (type != 'audio') {
      final inputCaption = await _showCaptionDialog(type);
      if (inputCaption == null) return; 
      caption = inputCaption;
    }

    String finalType = type == 'audio' ? 'document' : type;
    await _sendMediaFile(file, finalType, filename: fileName, caption: caption);
  }

  Future<String?> _showCaptionDialog(String type) async {
    String? caption;
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Send $type', style: const TextStyle(color: Color(0xFF0F172A))),
          content: TextField(
            onChanged: (v) => caption = v,
            decoration: const InputDecoration(hintText: "Add a caption...", focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0F172A)))),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)), onPressed: () => Navigator.pop(context, caption ?? ""), child: const Text("Send", style: TextStyle(color: Colors.white))),
          ],
        );
      },
    );
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _recordPath!);
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    final path = await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) return;
    await _sendMediaFile(File(path), 'audio');
  }

  Future<void> _sendMediaFile(File file, String type, {String? filename, String? caption}) async {
    setState(() => _isSending = true);
    
    String msgId = 'sent_${DateTime.now().millisecondsSinceEpoch}';
    
    setState(() {
      _messages.insert(0, {
        'id': msgId, 
        'isOutgoing': true,
        'createdAt': DateTime.now().toIso8601String(),
        'isOptimistic': true,
        'messageType': type,
        'messageContent': {
           'localFile': file.path,
           'caption': caption ?? '',
           'status': 'sending',
           'document': type == 'document' ? {'filename': filename} : null,
        },
      });
    });

    try {
      final profile = await SettingsApiService.instance.fetchRestaurantProfile(widget.restaurantId);
      final accessToken = profile?['waToken'] ?? '';
      if (accessToken.isEmpty) throw Exception("No Token");

      final success = await MediaService().sendMedia(
        file: file, type: type, to: widget.phoneNumber, restaurantId: widget.restaurantId,
        phoneNumberId: widget.phoneNumberId, accessToken: accessToken, filename: filename, caption: caption,
        messageId: msgId, 
      );

      if (success) {
        setState(() {
          int idx = _messages.indexWhere((m) => m['id'] == msgId);
          if (idx != -1) _messages[idx]['messageContent']['status'] = 'sent';
        });
        await _fetchMessages(); 
      } else {
        throw Exception("Failed delivery");
      }
    } catch (e) {
      setState(() {
        int idx = _messages.indexWhere((m) => m['id'] == msgId);
        if (idx != -1) _messages[idx]['status'] = 'failed';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessage(String text) async {
    setState(() => _isSending = true);
    String optId = 'opt_${DateTime.now().millisecondsSinceEpoch}';
    
    setState(() {
      _messages.insert(0, {
        'id': optId, 
        'messageText': text, 
        'isOutgoing': true, 
        'createdAt': DateTime.now().toIso8601String(), 
        'isOptimistic': true
      });
    });
    
    try {
      await ChatApi.instance.sendMessage(
        to: widget.phoneNumber, 
        text: text, 
        restaurantId: widget.restaurantId, 
        phoneNumberId: widget.phoneNumberId
      );
      await _fetchMessages();
    } catch (e) {
      setState(() {
        int idx = _messages.indexWhere((m) => m['id'] == optId);
        if (idx != -1) _messages[idx]['status'] = 'failed';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                    : _messages.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.forum_outlined, size: 44, color: Color(0xFF94A3B8)), SizedBox(height: 12), Text("No messages in this chat", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))]))
: ListView.builder(
    controller: _scrollController,
    reverse: true,
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    itemCount: _messages.length + (_hasMoreHistory ? 1 : 0),   // 🚀 CHANGED
    itemBuilder: (context, i) {
      // 🚀 ADDED — the extra trailing slot (oldest position) shows the loader
      if (i == _messages.length) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: _isLoadingOlder
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                : const SizedBox.shrink(),
          ),
        );
      }

      final m = _messages[i];
                          final prevM = (i < _messages.length - 1) ? _messages[i + 1] : null;
                          final nextM = (i > 0) ? _messages[i - 1] : null;

                          DateTime currentDt = DateTime.tryParse(m['createdAt'] ?? m['created_at'] ?? m['timestamp'] ?? '')?.toLocal() ?? DateTime.now();
                          DateTime prevDt = prevM != null ? (DateTime.tryParse(prevM['createdAt'] ?? prevM['created_at'] ?? prevM['timestamp'] ?? '')?.toLocal() ?? DateTime.now()) : DateTime(2000);
                          String dateLabel = DateFormatter.getDateSeparator(currentDt, prevDt);

                          var content = m['messageContent'];
                          String msgText = "";
                          String mediaUrl = "";
                          String mediaType = m['messageType'] ?? "";
                          String fileName = "";
                          bool isOptimistic = m['isOptimistic'] == true;
                          bool isFailed = m['status'] == 'failed';

                          if (content is Map) {
                            if (content['image'] != null) mediaType = 'image';
                            else if (content['video'] != null) mediaType = 'video';
                            else if (content['audio'] != null) mediaType = 'audio';
                            else if (content['document'] != null) {
                              mediaType = 'document';
                              fileName = content['document']['filename']?.toString() ?? "Document";
                            }
                            if (mediaType.isNotEmpty) mediaUrl = _resolveMediaUrl(content, mediaType);

                            if (content['text'] != null && content['text'] is Map) msgText = content['text']['body']?.toString() ?? "";
                            else if (content['interactive'] != null && content['interactive'] is Map) {
                              var intObj = content['interactive'];
                              String iType = intObj['type']?.toString() ?? '';
                              if (iType == 'button_reply' && intObj['button_reply'] != null) msgText = "🔘 ${intObj['button_reply']['title'] ?? "Button Clicked"}";
                              else if (iType == 'list_reply' && intObj['list_reply'] != null) msgText = "📋 ${intObj['list_reply']['title'] ?? "List Selected"}";
                              else {
                                String bodyText = intObj['body']?['text']?.toString() ?? "Interactive Menu";
                                String headerText = intObj['header']?['text']?.toString() ?? "";
                                msgText = headerText.isNotEmpty ? "🤖 *$headerText*\n$bodyText" : "🤖 $bodyText";
                              }
                            } else if (content['type'] == 'template') {
                              msgText = "🤖 [WhatsApp Template]";
                              if (content['template'] != null && content['template']['name'] != null) msgText += "\nName: ${content['template']['name']}";
                            } else if (content['location'] != null && content['location'] is Map) {
                              msgText = "📍 Shared Location";
                            } else if (mediaUrl.isNotEmpty || isOptimistic) {
                              msgText = content['caption']?.toString() ?? "";
                            } else if (content.containsKey('body')) {
                              msgText = content['body']?.toString() ?? "";
                            }
                          } else {
                            msgText = content?.toString() ?? m['messageText']?.toString() ?? "";
                          }

                          if (msgText.trim().isEmpty && mediaUrl.isEmpty && mediaType.isEmpty && !isOptimistic) msgText = "Unsupported message type";

                          String direction = m['direction']?.toString().toLowerCase().trim() ?? '';
                          String sender = m['sender']?.toString().toLowerCase().trim() ?? '';
                          bool isBotPrompt = (content is Map) && (content['type'] == 'template' || (content['interactive'] != null && content['interactive']['type'] != 'button_reply' && content['interactive']['type'] != 'list_reply'));
                          bool isBot = sender.contains('bot') || isBotPrompt;
                          bool isMine = direction.contains('out') || sender.contains('rest') || isBot || m['isOutgoing'] == true;

                          bool nextIsMine = nextM != null && (nextM['isOutgoing'] == true || nextM['direction']?.toString().contains('out') == true || nextM['sender']?.toString().contains('rest') == true);
                          bool isGroupedWithNext = nextM != null && isMine == nextIsMine;
                          String formattedClock = DateFormatter.formatMsgTime(m['createdAt']?.toString() ?? m['created_at']?.toString() ?? m['timestamp']?.toString());

                          return Column(
                            children: [
                              if (dateLabel.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.symmetric(vertical: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: Text(dateLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                ),
                              GestureDetector(
                                onLongPress: () {
                                  if (msgText.isNotEmpty) {
                                    Clipboard.setData(ClipboardData(text: msgText));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Message copied"), behavior: SnackBarBehavior.floating));
                                  }
                                },
                                child: Padding(
                                  padding: EdgeInsets.only(top: isGroupedWithNext ? 2 : 6),
                                  child: Align(
                                    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Column(
                                      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            if (isFailed && isOptimistic) _retryMessage(m);
                                          },
                                          child: Container(
                                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isFailed ? const Color(0xFFFEF2F2) : (isMine ? (isBot ? const Color(0xFFEFF6FF) : const Color(0xFFE8F5E9)) : Colors.white),
                                              borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(isMine ? 16 : (isGroupedWithNext ? 16 : 4)), bottomRight: Radius.circular(isMine ? (isGroupedWithNext ? 16 : 4) : 16)),
                                              border: Border.all(color: isFailed ? const Color(0xFFFECACA) : (isMine ? (isBot ? const Color(0xFFDBEAFE) : const Color(0xFFC8E6C9)) : const Color(0xFFE2E8F0)), width: isBot ? 1.5 : 1),
                                            ),
                                            child: _buildMessageBody(msgText, mediaUrl, mediaType, fileName, isMine, isBot, content, isOptimistic, isFailed),
                                          ),
                                        ),
                                        if (formattedClock.isNotEmpty || isOptimistic) ...[
                                          const SizedBox(height: 3),
                                          Padding(
                                            padding: EdgeInsets.only(right: isMine ? 4 : 0, left: !isMine ? 4 : 0),
                                            child: Text(
  isFailed 
    ? "Failed to send - Tap to retry" 
    : (isOptimistic && (content is! Map || content['status'] != 'sent') 
        ? "Sending..." 
        : formattedClock), style: TextStyle(color: isFailed ? Colors.red : const Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)),
                                          ),
                                        ],
                                      ],
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
                    bottom: 16, right: 16,
                    child: FloatingActionButton(mini: true, backgroundColor: Colors.white, onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut), child: Badge(isLabelVisible: _unreadWhileScrolled > 0, label: Text(_unreadWhileScrolled.toString()), child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF0F172A)))),
                  ),
              ],
            ),
          ),
          Builder(
  builder: (context) {
    final remaining = _sessionRemaining();
    if (remaining == null) return const SizedBox.shrink(); // no inbound message ever — nothing to show

    final bool expired = remaining.isNegative;
    final int hours = remaining.abs().inHours;
    final int minutes = remaining.abs().inMinutes.remainder(60);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: expired ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
      child: Row(
        children: [
          Icon(
            expired ? Icons.info_outline_rounded : Icons.access_time_rounded,
            size: 16,
            color: expired ? const Color(0xFFDC2626) : const Color(0xFFD97706),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              expired
                  ? "24-hour session expired — this customer can only be reached with an approved template message."
                  : "Session window: ${hours}h ${minutes}m remaining",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: expired ? const Color(0xFFDC2626) : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  },
),
          ChatInputBar(
            controller: _controller,
            charCount: _charCount,
            isSending: _isSending,
            isRecording: _isRecording,
            onSendText: _sendMessage,
            onSendMedia: _pickAndSendMedia,
            onStartRecording: _startRecording,
            onStopRecording: _stopAndSendRecording,
          ),
        ],
      ),
    );
  }
}