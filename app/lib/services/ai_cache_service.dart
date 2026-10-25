import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache for AI Insights + chat history.
///
/// Every key is scoped to the signed-in user's uid, and [clearAllForSignOut]
/// wipes AI data on sign-out, so a shared device never shows one account's
/// financial insights or chat to another.
class AiCacheService {
  static const String _kRoot = 'ai_cache';
  static const String legacyChatHistoryKey = 'ai_cfo_chat_history';
  static const List<String> _legacyKeys = [
    'last_ai_sync',
    'ai_metrics_cache',
    legacyChatHistoryKey,
  ];
  static const String _legacyPrefix = 'ai_insights_cache_';

  /// Bump to invalidate every cached insight after a prompt/schema change.
  static const int _schemaVersion = 2;

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'anon';

  static String _key(String name, [String? uid]) =>
      '$_kRoot:${uid ?? _uid}:$name';

  static String chatHistoryKey([String? uid]) => _key('chat_history', uid);

  /// Valid when the local sync is newer than the last data change recorded in
  /// Firestore (`users/{uid}.lastDataUpdate`) and was written by this schema.
  static Future<bool> isCacheValid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_key('schema')) != _schemaVersion) return false;
      final lastSyncMs = prefs.getInt(_key('last_sync')) ?? 0;
      if (lastSyncMs == 0) return false;

      // Hard ceiling so "this month" insights can't go stale forever, even if
      // lastDataUpdate was never written.
      final age = DateTime.now().millisecondsSinceEpoch - lastSyncMs;
      if (age > const Duration(hours: 24).inMilliseconds) return false;
      final synced = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
      final now = DateTime.now();
      if (synced.month != now.month || synced.year != now.year) return false;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final lastDataUpdate = doc.data()?['lastDataUpdate'] as Timestamp?;
      if (lastDataUpdate == null) return true;

      return lastSyncMs >= lastDataUpdate.millisecondsSinceEpoch;
    } catch (e) {
      debugPrint("Error checking AI cache validity: $e");
      return false;
    }
  }

  static Future<void> saveSectionCache(String sectionKey, List<dynamic> parsedInsights) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key('section_$sectionKey'), jsonEncode(parsedInsights));
    } catch (e) {
      debugPrint("Failed to save AI cache for section $sectionKey: $e");
    }
  }

  static Future<void> updateSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // +1s buffer: Firestore's server timestamp can be slightly ahead.
      await prefs.setInt(_key('last_sync'), DateTime.now().millisecondsSinceEpoch + 1000);
      await prefs.setInt(_key('schema'), _schemaVersion);
    } catch (e) {
      debugPrint("Failed to update AI sync timestamp: $e");
    }
  }

  static Future<List<dynamic>?> loadSectionCache(String sectionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key('section_$sectionKey'));
      if (jsonString != null) return jsonDecode(jsonString) as List<dynamic>;
    } catch (e) {
      debugPrint("Failed to load AI cache for section $sectionKey: $e");
    }
    return null;
  }

  /// Clears cached insights for the current user (keeps chat history).
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = '$_kRoot:$_uid:';
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith(prefix) && k != chatHistoryKey()) await prefs.remove(k);
      }
    } catch (e) {
      debugPrint("Failed to clear AI cache: $e");
    }
  }

  /// Removes ALL AI data on this device (every user + legacy unscoped keys).
  /// Call before signing out.
  static Future<void> clearAllForSignOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith('$_kRoot:') ||
            k.startsWith(_legacyPrefix) ||
            _legacyKeys.contains(k)) {
          await prefs.remove(k);
        }
      }
    } catch (e) {
      debugPrint("Failed to clear AI data on sign-out: $e");
    }
  }
}
