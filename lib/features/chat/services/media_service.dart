import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'chat_db.dart';

class MediaService {
  static const String _cloudName = 'vmr1cn49';
  static const String _uploadPreset = 'whatsapp';

  Future<String?> uploadToCloudinary(File file, String resourceType) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['secure_url']?.toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> sendMediaToMeta({
    required String to,
    required String type,
    required String cloudinaryUrl,
    required String phoneNumberId,
    required String accessToken,
    String? filename,
    String? caption,
  }) async {
    final url = 'https://graph.facebook.com/v19.0/$phoneNumberId/messages';
    final Map<String, dynamic> mediaObject = {"link": cloudinaryUrl};
    
    if (caption != null && caption.isNotEmpty && type != 'audio') {
      mediaObject["caption"] = caption;
    }
    if (type == 'document' && filename != null) {
      mediaObject["filename"] = filename;
    }

    final payload = {
      "messaging_product": "whatsapp",
      "to": to,
      "type": type,
      type: mediaObject,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendMedia({
    required File file,
    required String type,
    required String to,
    required String restaurantId,
    required String phoneNumberId,
    required String accessToken,
    String? filename,
    String? caption,
    String? messageId,
  }) async {
    final String cloudinaryResourceType = (type == 'document' || type == 'audio') ? 'raw' : type;
    
    final cloudinaryUrl = await uploadToCloudinary(file, cloudinaryResourceType);
    if (cloudinaryUrl == null) return false;

    final metaSuccess = await sendMediaToMeta(
      to: to,
      type: type,
      cloudinaryUrl: cloudinaryUrl,
      phoneNumberId: phoneNumberId,
      accessToken: accessToken,
      filename: filename,
      caption: caption,
    );
    if (!metaSuccess) return false;

    String msgId = messageId ?? "sent_${DateTime.now().millisecondsSinceEpoch}";
    final Map<String, dynamic> typeObject = {
      "id": msgId,
      if (type == 'document' && filename != null) "filename": filename,
    };

    // 🚀 Use the new Modular Chat DB Service
    await ChatDbService.instance.upsertMessage(restaurantId, {
      'id': msgId,
      'customerNumber': to,
      'direction': 'outbound',
      'isOutgoing': true,
      'messageType': type,
      'messageContent': {
        type: typeObject,
        "caption": caption ?? "",
        "cloudinary": {"url": cloudinaryUrl},
      },
      'status': 'sent',
      'createdAt': DateTime.now().toIso8601String(),
    });

    return true;
  }
}