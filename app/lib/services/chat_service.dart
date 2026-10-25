import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';

class ChatService {
  static String get baseUrl =>
      dotenv.env['PROD_API_URL'] ?? "https://set-iamf.onrender.com";


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
  static dynamic _jsonSafe(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    }
    if (v is List) return v.map(_jsonSafe).toList();
    if (v is GeoPoint) return {"lat": v.latitude, "lng": v.longitude};
    if (v is DocumentReference) return v.path;
    return v;
  }

  /// Fetches the user's financial data from Firestore and sends it
  /// alongside the chat message so the backend always has context.
  static Future<String> sendMessage(
    String question,
    List<Map<String, dynamic>> history,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please log in.');
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get auth token.');
    }

    // Send on-device data as a fallback in case the backend can't read Firestore.
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(
      currencyCode,
    );
    final sectionData = await _buildSectionData(user.uid);

    final requestBody = {
      "question": question,
      "history": history,
      "sectionData": sectionData,
      "currencySymbol": currencySymbol,
    };

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please log in.');
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get auth token.');
    }

    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(
      currencyCode,
    );
    final sectionData = await _buildSectionData(user.uid);

    final requestBody = {
      "question": question,
      "history": history,
      "sectionData": sectionData,
      "currencySymbol": currencySymbol,
    };

    final request = http.Request('POST', Uri.parse("$baseUrl/chat/stream"));
    request.headers.addAll({
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    request.body = jsonEncode(requestBody);

    final client = http.Client();
    try {
      http.StreamedResponse? response;
      // Retry once on connection failure / 5xx (Render free-tier cold start).
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final req = http.Request('POST', request.url)
            ..headers.addAll(request.headers)
            ..body = request.body;
          response = await client.send(req).timeout(const Duration(seconds: 60));
          if (response.statusCode < 500 || attempt == 2) break;
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
