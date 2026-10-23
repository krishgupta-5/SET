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
      final results = await Future.wait([
        db.collection('expenses').where('uid', isEqualTo: uid)
            .orderBy('Date', descending: true).limit(50).get(),
        db.collection('companies').where('uid', isEqualTo: uid).limit(1).get(),
        db.collection('teams').where('uid', isEqualTo: uid).get(),
        db.collection('members').where('uid', isEqualTo: uid).get(),
      ]);
      List<Map<String, dynamic>> docs(QuerySnapshot<Map<String, dynamic>> s) =>
          s.docs.map((d) => _jsonSafe(d.data()) as Map<String, dynamic>).toList();

      final company = docs(results[1]);
      return {
        "expenses": docs(results[0]),
        "revenue": [],
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
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    if (v is List) return v.map(_jsonSafe).toList();
    if (v is GeoPoint) return {"lat": v.latitude, "lng": v.longitude};
    if (v is DocumentReference) return v.path;
    return v;
  }

  /// Fetches the user's financial data from Firestore and sends it
  /// alongside the chat message so the backend always has context.
  static Future<String> sendMessage(String question, List<Map<String, dynamic>> history) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please log in.');
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get auth token.');
    }

    // Send on-device data as a fallback in case the backend can't read Firestore.
    final currencyCode = await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(currencyCode);
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
        res = await http.post(
          Uri.parse("$baseUrl/chat"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 60));
      } catch (e) {
        networkError = e;
      }

      if (networkError != null) {
        if (attempt == maxAttempts) {
          throw Exception(
            'Connection failed. Please ensure the server is running. Error: $networkError',
          );
        }
      } else if (res!.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data["response"] ?? "I couldn't process that.";
      } else if (res.statusCode < 500 || attempt == maxAttempts) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }

      // Retry 5xx / network errors (Render cold start) with a short backoff.
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
    throw Exception('Connection failed. Please ensure the server is running.');
  }

  /// Streams the user's financial data and yields LLM tokens for a typewriter effect.
  static Stream<String> streamMessage(String question, List<Map<String, dynamic>> history) async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please log in.');
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get auth token.');
    }

    final currencyCode = await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(currencyCode);
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
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Server error (${response.statusCode})');
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;
            if (data.isEmpty) continue;
            
            try {
              final json = jsonDecode(data);
              if (json.containsKey('error')) {
                  throw Exception(json['error']);
              }
              final choices = json['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final content = choices[0]['delta']?['content'];
                if (content != null) {
                  yield content as String;
                }
              }
            } catch (e) {
              if (e is FormatException) {
                debugPrint("ChatService stream parse error (ignored): $e data: $data");
              } else {
                rethrow; // Rethrow explicit API errors
              }
            }
          }
        }
      }
    } catch (e) {
      throw Exception('Connection failed. Error: $e');
    } finally {
      client.close();
    }
  }

}
