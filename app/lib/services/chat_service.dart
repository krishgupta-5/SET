import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:startup_expense_tracker/services/ai_context_manager.dart';
import 'package:startup_expense_tracker/services/app_config.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';

class ChatService {
  static String get baseUrl =>
      AppConfig.apiUrl;


  /// Builds the user's financial snapshot on-device so the backend always has
  /// context, even if its own Firestore access is unavailable.
  static Future<Map<String, dynamic>> _buildSectionData(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      // Fallback snapshot only (the backend reads Firestore itself). Send the
      // full expense set with doc ids so recurring/salary matching works, and
      // include revenue so net burn is correct.
      final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>?>([
        db.collection('expenses').where('uid', isEqualTo: uid).limit(1000).get(),
        db.collection('companies').where('uid', isEqualTo: uid).limit(1).get(),
        db.collection('teams').where('uid', isEqualTo: uid).get(),
        db.collection('members').where('uid', isEqualTo: uid).get(),
        // Revenue is optional; a missing rule/collection must not drop context.
        db
            .collection('revenue')
            .where('uid', isEqualTo: uid)
            .get()
            .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
      ]);
      List<Map<String, dynamic>> docs(QuerySnapshot<Map<String, dynamic>>? s) =>
          (s?.docs ?? const [])
              .map((d) => {
                    ...(_jsonSafe(d.data()) as Map<String, dynamic>),
                    'id': d.id,
                  })
              .toList();

      final company = docs(results[1]);
      return {
        "expenses": docs(results[0]),
        "revenue": docs(results[4]),
        "company": company.isNotEmpty ? company.first : {},
        "teams": docs(results[2]),
        "members": docs(results[3]),
      };
    } catch (e) {
      debugPrint("ChatService: failed to build client context: $e");
      return {};
    }
  }

  /// Converts Firestore types (Timestamp, GeoPoint, refs) into JSON-encodable values.
  /// Dates are sent as UTC ("...Z") so the backend can shift them to the
  /// user's timezone; local strings without an offset were read as UTC.
  static dynamic _jsonSafe(dynamic v) {
    if (v is Timestamp) return v.toDate().toUtc().toIso8601String();
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    }
    if (v is List) return v.map(_jsonSafe).toList();
    if (v is GeoPoint) return {"lat": v.latitude, "lng": v.longitude};
    if (v is DocumentReference) return v.path;
    return v;
  }

  /// The backend only uses the last 20 turns; sending more just grows the
  /// request (and older builds of the backend rejected > 60 with a 400).
  static const int _maxHistory = 20;

  /// HTTP status the backend returns when it has no data for this user and
  /// wants the on-device snapshot attached.
  static const int _needClientContext = 409;

  @visibleForTesting
  static List<Map<String, dynamic>> trimHistory(
    List<Map<String, dynamic>> history,
  ) {
    final clean = history
        .where((m) => m['role'] != 'error')
        .map((m) => {'role': m['role'], 'text': (m['text'] ?? '').toString()})
        .where((m) => (m['text'] as String).trim().isNotEmpty)
        .toList();
    return clean.length > _maxHistory
        ? clean.sublist(clean.length - _maxHistory)
        : clean;
  }

  /// Auth token + request body. The device snapshot is only attached when
  /// [withSnapshot] is true (the backend reads Firestore itself and asks for
  /// it with a 409 only when it has nothing).
  static Future<(String, Map<String, dynamic>)> _prepare(
    String question,
    List<Map<String, dynamic>> history, {
    required bool withSnapshot,
    bool refreshToken = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const ChatException('Please sign in again to use the AI CFO.');
    }
    final token = await user.getIdToken(refreshToken);
    if (token == null) {
      throw const ChatException('Your session expired. Please sign in again.');
    }
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    return (
      token,
      {
        "question": question,
        "history": trimHistory(history),
        "currencySymbol": CurrencyPreferenceService.getCurrencySymbol(
          currencyCode,
        ),
        "tzOffsetMinutes": DateTime.now().timeZoneOffset.inMinutes,
        if (withSnapshot) "sectionData": await _buildSectionData(user.uid),
      },
    );
  }

  /// Sends a chat message and returns the full answer.
  static Future<String> sendMessage(
    String question,
    List<Map<String, dynamic>> history,
  ) async {
    // A just-saved expense may still be waiting on the invalidate debounce.
    await AiContextManager().flushPending();
    var withSnapshot = false;
    var refreshed = false;
    var (token, requestBody) = await _prepare(
      question,
      history,
      withSnapshot: withSnapshot,
    );

    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      http.Response? res;
      Object? networkError;
      try {
        res = await http
            .post(
              Uri.parse("$baseUrl/chat"),
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer $token",
              },
              body: jsonEncode(requestBody),
            )
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        networkError = e;
      }

      if (networkError == null &&
          res!.statusCode == _needClientContext &&
          !withSnapshot) {
        withSnapshot = true;
        (token, requestBody) = await _prepare(
          question,
          history,
          withSnapshot: true,
        );
        attempt--; // not a failure; resend right away with the snapshot
        continue;
      }

      // A rejected token may just be stale; retry once with a fresh one
      // before telling the user their session expired.
      if (networkError == null && res!.statusCode == 401 && !refreshed) {
        refreshed = true;
        (token, requestBody) = await _prepare(
          question,
          history,
          withSnapshot: withSnapshot,
          refreshToken: true,
        );
        attempt--;
        continue;
      }

      if (networkError != null) {
        if (attempt == maxAttempts) {
          debugPrint('ChatService.sendMessage network error: $networkError');
          throw const ChatException("Couldn't reach the AI service. Check your connection and try again.");
        }
      } else if (res!.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data["response"] ?? "I couldn't process that.";
      } else if (res.statusCode < 500 || attempt == maxAttempts) {
        // Never show raw server bodies to users.
        throw ChatException(
          res.statusCode == 401
              ? 'Your session expired. Please sign in again.'
              : res.statusCode == 429
              ? 'Too many requests. Please wait a moment and try again.'
              : 'The AI service is unavailable right now (${res.statusCode}). Please try again.',
        );
      }

      // Retry 5xx / network errors (Render cold start) with a short backoff.
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
    throw Exception('Connection failed. Please ensure the server is running.');
  }

  /// Streams the user's financial data and yields LLM tokens for a typewriter effect.
  static Stream<String> streamMessage(
    String question,
    List<Map<String, dynamic>> history,
  ) async* {
    // A just-saved expense may still be waiting on the invalidate debounce.
    await AiContextManager().flushPending();
    var withSnapshot = false;
    var refreshed = false;
    var (token, requestBody) = await _prepare(
      question,
      history,
      withSnapshot: withSnapshot,
    );
    final url = Uri.parse("$baseUrl/chat/stream");

    final client = http.Client();
    try {
      http.StreamedResponse? response;
      // Retry once on connection failure / 5xx (Render free-tier cold start).
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final req = http.Request('POST', url)
            ..headers.addAll({
              "Content-Type": "application/json",
              "Authorization": "Bearer $token",
            })
            ..body = jsonEncode(requestBody);
          response = await client.send(req).timeout(const Duration(seconds: 60));
          if (response.statusCode == _needClientContext && !withSnapshot) {
            await response.stream.drain<void>();
            withSnapshot = true;
            (token, requestBody) = await _prepare(
              question,
              history,
              withSnapshot: true,
            );
            attempt--; // not a failure; resend right away with the snapshot
            continue;
          }
          // A rejected token may just be stale; retry once with a fresh one.
          if (response.statusCode == 401 && !refreshed) {
            await response.stream.drain<void>();
            refreshed = true;
            (token, requestBody) = await _prepare(
              question,
              history,
              withSnapshot: withSnapshot,
              refreshToken: true,
            );
            attempt--;
            continue;
          }
          if (response.statusCode < 500 || attempt == 2) break;
        } on ChatException {
          rethrow;
        } on Exception {
          if (attempt == 2) rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
      final res = response!;
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const ChatException('Your session expired. Please sign in again.');
      }
      if (res.statusCode == 429) {
        throw const ChatException('Too many requests. Please wait a moment and try again.');
      }
      if (res.statusCode != 200) {
        throw ChatException('The AI service is unavailable right now (${res.statusCode}). Please try again.');
      }

      // SSE lines can be split across network chunks, so buffer and only
      // parse complete lines. (Splitting each chunk on '\n' dropped tokens.)
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45));

      await for (final line in lines) {
        final content = parseSseLine(line);
        if (content == null) continue;
        if (identical(content, sseDone)) return;
        yield content;
      }
    } on ChatException {
      rethrow;
    } on TimeoutException {
      throw const ChatException('The AI took too long to respond. Please try again.');
    } catch (e) {
      debugPrint('ChatService stream error: $e');
      throw const ChatException("Couldn't reach the AI service. Check your connection and try again.");
    } finally {
      client.close();
    }
  }

  /// Sentinel returned by [parseSseLine] for the `[DONE]` marker.
  static const String sseDone = '\u0000[DONE]';

  /// Parses one complete SSE line. Returns the token text, [sseDone], or null
  /// for keep-alives/empty deltas. Throws [ChatException] for server errors.
  @visibleForTesting
  static String? parseSseLine(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    if (data.isEmpty) return null;
    if (data == '[DONE]') return sseDone;

    final Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      debugPrint('ChatService: skipped malformed SSE line');
      return null;
    }
    if (json is! Map) return null;
    if (json['error'] != null) {
      final err = json['error'];
      throw ChatException(
        err is Map ? (err['message']?.toString() ?? 'AI error') : err.toString(),
      );
    }
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final content = (choices.first as Map)['delta']?['content'];
      if (content is String && content.isNotEmpty) return content;
    }
    return null;
  }
}

/// User-presentable chat failure (message is safe to show in the UI).
class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => message;

}
