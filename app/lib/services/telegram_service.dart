import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Centralised Telegram client — replaces the identical copy-pasted
/// `getTelegramImageUrl` / `uploadToTelegram` methods that previously lived
/// in team_screen.dart, team_detail_screen.dart, and add_member_screen.dart.
///
/// Fixes applied:
///   T-06  dotenv.load() is called at most once; the token is cached in memory.
///   T-07  URL cache entries expire after [_urlTtl] hours so stale Telegram
///         file links are never returned after a long session.
///   T-21  Single authoritative implementation instead of 3 identical copies.
class TelegramService {
  TelegramService._(); // Non-instantiable — all members are static.

  static const String _defaultChatId = '-1003885930746';

  /// Telegram file URLs are technically valid for ~24 h. We re-fetch at 6 h
  /// to stay comfortably within the window even after overnight sessions.
  static const Duration _urlTtl = Duration(hours: 6);

  static String? _cachedToken;
  static final Map<String, _CachedUrl> _urlCache = {};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns an HTTPS URL for the Telegram file identified by [fileId].
  ///
  /// Results are cached for [_urlTtl] so repeated widget rebuilds never hit
  /// the Telegram API more than necessary.
  ///
  /// Throws [TelegramFileException] on network errors, timeouts, non-200
  /// responses, `ok: false` (e.g. expired/invalid `file_id`) or a malformed
  /// body. Callers using `FutureBuilder` already render an avatar/placeholder
  /// fallback on error.
  static Future<String> getImageUrl(String fileId) async {
    if (fileId.isEmpty) {
      throw const TelegramFileException('Empty file_id');
    }
    final cached = _urlCache[fileId];
    if (cached != null && !cached.isExpired) return cached.url;

    final token = await _getToken();
    final http.Response res;
    try {
      res = await http
          .get(
            Uri.https('api.telegram.org', '/bot$token/getFile', {
              'file_id': fileId,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw TelegramFileException('Network error: $e');
    }

    if (res.statusCode != 200) {
      // Body may contain the bot token in error links, so don't log it.
      throw TelegramFileException('getFile failed (${res.statusCode})');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      throw const TelegramFileException('Invalid getFile response');
    }

    final result = decoded is Map<String, dynamic> && decoded['ok'] == true
        ? decoded['result']
        : null;
    final path = result is Map<String, dynamic> ? result['file_path'] : null;
    if (path is! String || path.isEmpty) {
      _urlCache.remove(fileId);
      throw const TelegramFileException('File not available');
    }

    final url = 'https://api.telegram.org/file/bot$token/$path';
    _urlCache[fileId] = _CachedUrl(url);
    return url;
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

  /// Uploads an image file to the configured Telegram chat.
  ///
  /// Returns the highest-quality `file_id` on success, or `null` on failure.
  static Future<String?> uploadPhoto(String filePath) async {
    try {
      final token = await _getToken();
      final uri = Uri.parse('https://api.telegram.org/bot$token/sendPhoto');
      final request = http.MultipartRequest('POST', uri)
        ..fields['chat_id'] = _defaultChatId
        ..files.add(await http.MultipartFile.fromPath('photo', filePath));

      final response = await request.send();
      if (response.statusCode != 200) {
        debugPrint('TelegramService: upload failed ${response.statusCode}');
        return null;
      }

      final res = await http.Response.fromStream(response);
      final data = jsonDecode(res.body);
      // The Telegram API returns an array ordered lowest→highest quality.
      final result = data is Map ? data['result'] : null;
      final photos = result is Map ? result['photo'] : null;
      if (photos is! List || photos.isEmpty) return null;
      return photos.last['file_id'] as String?;
    } catch (e) {
      debugPrint('TelegramService: upload error $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Loads and caches the bot token from .env.local.
  ///
  /// dotenv.load() is safe to call repeatedly (it's a no-op if already loaded),
  /// but we cache the extracted value so we avoid the file I/O on every call.
  static Future<String> _getToken() async {
    if (_cachedToken != null) return _cachedToken!;
    try {
      await dotenv.load(fileName: '.env.local');
    } catch (_) {
      // dotenv may throw if called after the app already loaded it — ignore.
    }
    _cachedToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
    if (_cachedToken == null || _cachedToken!.isEmpty) {
      throw Exception('TELEGRAM_BOT_TOKEN not found in .env.local');
    }
    return _cachedToken!;
  }
}

class TelegramFileException implements Exception {
  const TelegramFileException(this.message);
  final String message;

  @override
  String toString() => 'TelegramFileException: $message';
}

/// Private TTL wrapper for cached Telegram file URLs.
class _CachedUrl {
  final String url;
  final DateTime _fetchedAt;

  _CachedUrl(this.url) : _fetchedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(_fetchedAt) > TelegramService._urlTtl;
}
