import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:startup_expense_tracker/services/app_config.dart';
import 'package:http/http.dart' as http;

/// File storage client. All Telegram access goes through the backend
/// (`/files/upload`, `/files/{id}`), so the bot token never ships in the app.
///
/// Images are shown with [imageUrl] + [authHeaders] (pass both to
/// `Image.network`) or fetched as bytes with [downloadBytes].
class TelegramService {
  TelegramService._();

  static String get _baseUrl =>
      AppConfig.apiUrl;

  static Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const TelegramFileException('Not signed in');
    final token = await user.getIdToken();
    if (token == null) throw const TelegramFileException('No auth token');
    return token;
  }

  /// Authorization header for requests to [imageUrl].
  static Future<Map<String, String>> authHeaders() async => {
    'Authorization': 'Bearer ${await _token()}',
  };

  /// Backend URL for a stored file. Requires [authHeaders].
  static String imageUrl(String fileId) =>
      '$_baseUrl/files/${Uri.encodeComponent(fileId)}';

  /// Kept for existing call sites: returns the proxied URL for [fileId].
  /// Use with `Image.network(url, headers: await authHeaders())`.
  static Future<String> getImageUrl(String fileId) async {
    if (fileId.isEmpty) {
      throw const TelegramFileException('Empty file_id');
    }
    return imageUrl(fileId);
  }

  /// Like [getImageUrl] but returns null instead of throwing.
  static Future<String?> tryGetImageUrl(String fileId) async {
    try {
      return await getImageUrl(fileId);
    } catch (e) {
      debugPrint('TelegramService: $e');
      return null;
    }
  }

  static final Map<String, Uint8List> _bytesCache = {};

  /// Downloads a stored file (owner-checked by the backend). Cached in memory.
  static Future<Uint8List> downloadBytes(String fileId) async {
    final cached = _bytesCache[fileId];
    if (cached != null) return cached;
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse(imageUrl(fileId)), headers: await authHeaders())
          .timeout(const Duration(seconds: 60));
    } on TelegramFileException {
      rethrow;
    } catch (e) {
      throw TelegramFileException('Network error: $e');
    }
    if (res.statusCode == 404) {
      throw const TelegramFileException('File not available');
    }
    if (res.statusCode != 200) {
      throw TelegramFileException('Download failed (${res.statusCode})');
    }
    if (_bytesCache.length > 40) _bytesCache.clear();
    return _bytesCache[fileId] = res.bodyBytes;
  }

  /// Uploads an image as a photo. Returns the `file_id`, or null on failure.
  static Future<String?> uploadPhoto(String filePath) async {
    final r = await uploadFile(filePath, asPhoto: true);
    return r?.fileId;
  }

  /// Uploads any file. Images go as photos unless [asPhoto] is false.
  static Future<UploadedFile?> uploadFile(
    String filePath, {
    bool asPhoto = true,
  }) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final name = filePath.split(Platform.pathSeparator).last;
      final res = await http
          .post(
            Uri.parse('$_baseUrl/files/upload'),
            headers: {
              ...await authHeaders(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'data': base64Encode(bytes),
              'fileName': name,
              'mimeType': mimeFor(name),
              'asPhoto': asPhoto,
            }),
          )
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) {
        debugPrint('TelegramService: upload failed ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final id = data['fileId'] as String?;
      if (id == null || id.isEmpty) return null;
      return UploadedFile(
        fileId: id,
        fileName: (data['fileName'] as String?) ?? name,
        isImage: data['isImage'] == true,
      );
    } catch (e) {
      debugPrint('TelegramService: upload error $e');
      return null;
    }
  }

  static String mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return const {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
          'gif': 'image/gif',
          'heic': 'image/heic',
          'pdf': 'application/pdf',
          'txt': 'text/plain',
          'csv': 'text/csv',
          'doc': 'application/msword',
          'docx':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'xls': 'application/vnd.ms-excel',
          'xlsx':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        }[ext] ??
        'application/octet-stream';
  }
}

class UploadedFile {
  const UploadedFile({
    required this.fileId,
    required this.fileName,
    required this.isImage,
  });
  final String fileId;
  final String fileName;
  final bool isImage;
}

class TelegramFileException implements Exception {
  const TelegramFileException(this.message);
  final String message;

  @override
  String toString() => 'TelegramFileException: $message';
}
