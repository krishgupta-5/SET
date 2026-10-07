import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiCacheService {
  static const String _kLastAiSync = 'last_ai_sync';
  static const String _kAiInsightsCachePrefix = 'ai_insights_cache_'; // Append section key

  /// Checks if the cached insights are still valid by comparing the local sync timestamp
  /// with the `lastDataUpdate` timestamp in Firestore.
  static Future<bool> isCacheValid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMs = prefs.getInt(_kLastAiSync) ?? 0;
      
      if (lastSyncMs == 0) return false; // Never synced before

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;

      final lastDataUpdate = doc.data()?['lastDataUpdate'] as Timestamp?;
      if (lastDataUpdate == null) {
        // Data has never been explicitly modified since this feature was added
        return true; 
      }

      final lastUpdateMs = lastDataUpdate.millisecondsSinceEpoch;
      
      if (kDebugMode) {
        print("AI Cache Check: localSync=$lastSyncMs, remoteUpdate=$lastUpdateMs");
      }

      // Cache is valid if local sync happened AFTER or AT THE SAME TIME as the last remote data update
      return lastSyncMs >= lastUpdateMs;
    } catch (e) {
      debugPrint("Error checking AI cache validity: $e");
      return false; // Safest to invalidate on error
    }
  }

  /// Saves a specific AI section's JSON string to the local cache.
  static Future<void> saveSectionCache(String sectionKey, List<dynamic> parsedInsights) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(parsedInsights);
      await prefs.setString('$_kAiInsightsCachePrefix$sectionKey', jsonString);
    } catch (e) {
      debugPrint("Failed to save AI cache for section $sectionKey: $e");
    }
  }
  
  /// Marks the current time as the latest AI sync time.
  static Future<void> updateSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Add a slight buffer (1 second) to prevent race conditions where Firestore timestamp is very slightly ahead
      await prefs.setInt(_kLastAiSync, DateTime.now().millisecondsSinceEpoch + 1000);
    } catch (e) {
      debugPrint("Failed to update AI sync timestamp: $e");
    }
  }

  /// Loads a specific AI section's parsed insights from local cache.
  /// Returns null if not found.
  static Future<List<dynamic>?> loadSectionCache(String sectionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_kAiInsightsCachePrefix$sectionKey');
      if (jsonString != null) {
        return jsonDecode(jsonString) as List<dynamic>;
      }
    } catch (e) {
      debugPrint("Failed to load AI cache for section $sectionKey: $e");
    }
    return null;
  }
  
  /// Saves the AI metrics map to the local cache.
  static Future<void> saveMetricsCache(Map<String, dynamic> metrics) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(metrics);
      await prefs.setString('ai_metrics_cache', jsonString);
    } catch (e) {
      debugPrint("Failed to save AI metrics cache: $e");
    }
  }

  /// Loads the AI metrics map from local cache.
  static Future<Map<String, dynamic>?> loadMetricsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('ai_metrics_cache');
      if (jsonString != null) {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Failed to load AI metrics cache: $e");
    }
    return null;
  }
  
  /// Clears the AI cache completely.
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_kAiInsightsCachePrefix) || k == _kLastAiSync || k == 'ai_metrics_cache');
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint("Failed to clear AI cache: $e");
    }
  }
}
