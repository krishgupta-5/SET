import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:startup_expense_tracker/services/app_config.dart';
import 'package:http/http.dart' as http;

/// Receipt OCR client.
///
/// The Gemini key used to live in the app bundle. Now the image is sent to
/// the backend (`POST /receipts/scan`, Firebase ID token required), which
/// calls Gemini server-side. The public API is unchanged.
class ApiService {
  ApiService._();

  static String get _baseUrl =>
      AppConfig.apiUrl;

  /// Extracts merchant / amount / date / category / description from a
  /// receipt image. Never throws; returns empty fields on failure.
  static Future<Map<String, String>> extractReceiptData({
    required String base64Image,
    required String mediaType,
    String? prompt, // kept for compatibility; the prompt now lives server-side
    int maxRetries = 2,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _emptyResult();

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final token = await user.getIdToken();
        final res = await http
            .post(
              Uri.parse('$_baseUrl/receipts/scan'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'image': base64Image, 'mimeType': mediaType}),
            )
            .timeout(const Duration(seconds: 60));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            return {
              for (final k in _fields)
                k: (data[k] ?? (k == 'category' ? 'others' : ''))
                    .toString()
                    .trim(),
            };
          }
          return _emptyResult();
        }
        log('Receipt scan failed: HTTP ${res.statusCode}');
        // Retry only on server errors / rate limit (cold start, busy).
        if (res.statusCode < 500 && res.statusCode != 429) break;
      } on TimeoutException {
        log('Receipt scan timed out (attempt $attempt)');
      } catch (e) {
        log('Receipt scan error (attempt $attempt): $e');
      }
      if (attempt < maxRetries) {
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
    return _emptyResult();
  }

  static const _fields = [
    'merchant',
    'amount',
    'date',
    'category',
    'description',
  ];

  static Map<String, String> _emptyResult() => {
    'merchant': '',
    'amount': '',
    'date': '',
    'category': 'others',
    'description': '',
  };

  /// Scanning is configured server-side; the app only needs to be signed in.
  static bool isApiKeyConfigured() => FirebaseAuth.instance.currentUser != null;
}
