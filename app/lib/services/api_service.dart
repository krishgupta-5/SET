import 'dart:convert';
import 'dart:developer';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Secure API service for handling external API calls
///
/// This service centralizes API key management and provides a secure
/// way to make external API calls without exposing keys in the client code.
class ApiService {
  ApiService._();

  /// Get Gemini API key securely from environment variables
  static String get _geminiApiKey {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY') {
      throw Exception(
        'Gemini API key not configured. Please set GEMINI_API_KEY in your environment variables.',
      );
    }
    return apiKey;
  }

  /// Get API key for vision calls (exposed securely for vision API usage)
  static String get geminiApiKey => _geminiApiKey;

  /// Make a secure API call to Gemini
  ///
  /// [prompt] - The prompt to send to Gemini
  /// [model] - The Gemini model to use (defaults to gemini-3-flash-preview)
  /// Returns the response text from Gemini
  static Future<String> callGeminiAPI(
    String prompt, {
    String model = 'gemini-3-flash-preview',
  }) async {
    try {
      final apiKey = _geminiApiKey;
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] ??
            'No response received.';
      } else {
        throw Exception(
          'Gemini API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to call Gemini API: $e');
    }
  }

  /// Make a secure vision API call to Gemini with retry logic
  ///
  /// [base64Image] - Base64 encoded image data
  /// [mediaType] - MIME type of the image (e.g., 'image/jpeg')
  /// [prompt] - Text prompt for the vision analysis
  /// [maxRetries] - Maximum number of retry attempts (default: 3)
  /// Returns parsed expense data as Map<String, String>
  static Future<Map<String, String>> extractReceiptData({
    required String base64Image,
    required String mediaType,
    String? prompt,
    int maxRetries = 3,
  }) async {
    final defaultPrompt = '''Look at this receipt/bill image carefully.
Extract the expense information and return ONLY a valid JSON object — no markdown, no explanation, no extra text.

{
  "merchant": "business name only (e.g. Liquor Street)",
  "amount": "GRAND TOTAL as plain decimal e.g. 1139.00 — the final total after all taxes",
  "date": "DD/MM/YYYY — convert any date format you see",
  "category": "one of exactly: marketing | infrastructure | office | software | transport | design | others",
  "description": "one-line summary under 60 chars, NO newlines, e.g. Dinner at Liquor Street"
}

Rules:
- amount = FINAL/GRAND TOTAL, not subtotal
- merchant = business name only, no address or phone number  
- restaurants/cafes/food/drinks → category "others"
- If a field is not visible, use empty string ""
- Return ONLY the JSON object, absolutely nothing else''';

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        log('Gemini Vision API attempt ${attempt + 1}/$maxRetries');

        final response = await _makeGeminiVisionCall(
          base64Image,
          mediaType,
          prompt ?? defaultPrompt,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Extract text from Gemini response structure
          final text =
              data['candidates']?[0]?['content']?['parts']?[0]?['text']
                  as String? ??
              '';

          log('Gemini Vision response: $text');

          // Strip any accidental markdown fences
          final cleaned = text
              .replaceAll(RegExp(r'```json\s*'), '')
              .replaceAll(RegExp(r'```\s*'), '')
              .trim();

          // Extract JSON — try clean parse first, then field-by-field fallback
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
          if (jsonMatch != null) {
            try {
              final Map<String, dynamic> parsed = jsonDecode(
                jsonMatch.group(0)!,
              );
              return parsed.map(
                (k, v) => MapEntry(k, (v ?? '').toString().trim()),
              );
            } catch (_) {
              // JSON truncated/malformed — fall through to regex extraction
            }
          }
          log('Falling back to field-by-field regex extraction');
          return _extractFieldsWithRegex(cleaned);
        } else {
          log('Gemini Vision error ${response.statusCode}: ${response.body}');

          // Show helpful message based on error code
          if (response.statusCode == 400) {
            log('Tip: Check if image is too large or API key is wrong');
          } else if (response.statusCode == 403) {
            log('Tip: API key invalid or Gemini API not enabled');
          } else if (response.statusCode == 429) {
            log('Tip: Rate limit hit — waiting before retry...');
            if (attempt < maxRetries - 1) {
              await Future.delayed(Duration(seconds: (attempt + 1) * 2));
              continue;
            }
          }

          if (attempt == maxRetries - 1) {
            return _emptyResult();
          }
        }
      } catch (e) {
        log('Gemini Vision attempt ${attempt + 1} error: $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
      }
    }

    // All retries failed
    return _emptyResult();
  }

  /// Internal method to make the actual Vision API call
  static Future<http.Response> _makeGeminiVisionCall(
    String base64Image,
    String mediaType,
    String prompt,
  ) async {
    final apiKey = _geminiApiKey;
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$apiKey',
    );

    return await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    // Image data
                    'inline_data': {
                      'mime_type': mediaType,
                      'data': base64Image,
                    },
                  },
                  {
                    // Text prompt
                    'text': prompt,
                  },
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.1, // low = more deterministic/accurate
              'maxOutputTokens': 500,
            },
          }),
        )
        .timeout(const Duration(seconds: 45));
  }

  /// Helper method to extract fields using regex fallback
  static Map<String, String> _extractFieldsWithRegex(String text) {
    String field(String key) {
      final match = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(text);
      return match?.group(1)?.trim() ?? '';
    }

    return {
      'merchant': field('merchant'),
      'amount': field('amount'),
      'date': field('date'),
      'category': field('category'),
      'description': field('description'),
    };
  }

  /// Helper method to return empty result
  static Map<String, String> _emptyResult() => {
    'merchant': '',
    'amount': '',
    'date': '',
    'category': 'others',
    'description': '',
  };

  /// Validate if API key is properly configured
  ///
  /// Returns true if API key is configured, false otherwise
  static bool isApiKeyConfigured() {
    try {
      _geminiApiKey;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get configuration status for debugging
  ///
  /// Returns a map with configuration status
  static Map<String, dynamic> getConfigurationStatus() {
    return {
      'geminiConfigured': isApiKeyConfigured(),
      'hasEnvFile': dotenv.env.isNotEmpty,
      'envVars': dotenv.env.keys.toList(),
    };
  }
}
