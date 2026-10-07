import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:startup_expense_tracker/models/domain_events.dart';
import 'package:startup_expense_tracker/services/event_dispatcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Manages the lifecycle of the AI Context for the user.
/// Keeps the AI decoupled from raw data operations.
class AiContextManager {
  static final AiContextManager _instance = AiContextManager._internal();
  factory AiContextManager() => _instance;
  AiContextManager._internal();

  static String get baseUrl {
    if (kReleaseMode) {
      return dotenv.env['PROD_API_URL'] ?? "https://your-production-url.com";
    }
    return Platform.isIOS ? "http://127.0.0.1:8000" : "http://10.0.2.2:8000";
  }

  /// Subscribes to domain events. Should be called once during app initialization.
  void initListeners() {
    EventDispatcher().subscribe<FinancialEvent>((event) async {
      debugPrint("AiContextManager received FinancialEvent. Invalidating context...");
      
      // 1. Invalidate backend context
      await invalidate();
      
      // 2. Mark local data as changed in Firestore to bust frontend caches
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'lastDataUpdate': FieldValue.serverTimestamp(),
          });
          debugPrint("Updated lastDataUpdate timestamp for frontend cache invalidation.");
        } catch (e) {
          debugPrint("Failed to update lastDataUpdate: $e");
          // If the doc doesn't exist or misses the field, use set with merge
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'lastDataUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
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
