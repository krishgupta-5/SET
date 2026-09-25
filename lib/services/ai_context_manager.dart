import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:startup_expense_tracker/models/domain_events.dart';
import 'package:startup_expense_tracker/services/event_dispatcher.dart';

/// Manages the lifecycle of the AI Context for the user.
/// Keeps the AI decoupled from raw data operations.
class AiContextManager {
  static final AiContextManager _instance = AiContextManager._internal();
  factory AiContextManager() => _instance;
  AiContextManager._internal();

  static String get baseUrl {
    if (kReleaseMode) {
      return "https://your-production-url.com";
    }
    return Platform.isIOS ? "http://127.0.0.1:8000" : "http://10.0.2.2:8000";
  }

  /// Subscribes to domain events. Should be called once during app initialization.
  void initListeners() {
    EventDispatcher().subscribe<FinancialEvent>((event) {
      debugPrint("AiContextManager received FinancialEvent. Invalidating context...");
      invalidate();
    });
  }

  /// Invalidates the AI business context on the backend.
  /// The next chat request will automatically rebuild it.
  Future<void> invalidate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final token = await user.getIdToken();
    if (token == null) return;

    try {
      await http.post(
        Uri.parse("$baseUrl/ai/context/invalidate"),
        headers: {
          "Authorization": "Bearer $token",
        },
      );
      debugPrint("AI Context invalidated successfully.");
    } catch (e) {
      debugPrint('Failed to invalidate AI context: $e');
    }
  }
}
