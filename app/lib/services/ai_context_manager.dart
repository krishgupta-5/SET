import 'dart:async';

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

  static String get baseUrl =>
      dotenv.env['PROD_API_URL'] ?? "https://set-iamf.onrender.com";

  bool _initialized = false;
  Timer? _debounce;

  /// Subscribes to domain events. Safe to call more than once.
  void initListeners() {
    if (_initialized) return;
    _initialized = true;
    EventDispatcher().subscribe<FinancialEvent>((event) {
      // Coalesce bursts (a batch save fires several events / snapshots).
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), _markDataChanged);
    });
  }

  /// Fingerprints of the last-seen live data per source; used by
  /// [reportDataChanged] to ignore the first snapshot and no-op updates.
  final Map<String, String> _fingerprints = {};

  /// Call from live Firestore listeners with a cheap fingerprint of the data
  /// (e.g. doc ids + update times). Triggers invalidation only on real change.
  void reportDataChanged(String source, String fingerprint) {
    final previous = _fingerprints[source];
    _fingerprints[source] = fingerprint;
    if (previous == null || previous == fingerprint) return;
    EventDispatcher().dispatch(FinancialDataChangedEvent(source));
  }

  /// Clears tracked fingerprints (call on sign-out / account switch).
  void reset() {
    _fingerprints.clear();
    _debounce?.cancel();
  }

  Future<void> _markDataChanged() async {
    debugPrint("AiContextManager: financial data changed, invalidating AI context");
    await invalidate();

    // Bumps the timestamp the AI Insights cache checks against.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastDataUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Failed to update lastDataUpdate: $e");
    }
  }

  /// Invalidates the AI business context on the backend.
  /// The next chat request will automatically rebuild it.
  Future<void> invalidate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    if (token == null) return;

    try {
      await http
          .post(
            Uri.parse("$baseUrl/ai/context/invalidate"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Failed to invalidate AI context: $e');
    }
  }
}
