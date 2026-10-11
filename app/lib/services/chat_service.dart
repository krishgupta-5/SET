import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';

class ChatService {
  static String get baseUrl =>
      dotenv.env['PROD_API_URL'] ?? "https://set-iamf.onrender.com";

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

    // Backend fetches the context itself; we send empty dictionary
    final currencyCode = await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(currencyCode);

    final requestBody = {
      "question": question,
      "history": history,
      "sectionData": {},
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

    final requestBody = {
      "question": question,
      "history": history,
      "sectionData": {},
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
