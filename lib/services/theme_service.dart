import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage user's theme preference (Light vs Dark mode)
/// Handles storing, retrieving, pre-loading from local disk, and updating theme selection
class ThemeService {
  // Private constructor to prevent instantiation
  ThemeService._();

  static const String _prefsKey = 'cached_theme_mode';
  static const String _freshInstallKey = 'has_synced_after_fresh_install';
  static final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Stream of theme changes for UI updates
  static ValueNotifier<ThemeMode> get themeModeNotifier => _themeModeNotifier;

  /// Check if the current theme is dark mode
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// Convert string from Firestore or local prefs to ThemeMode
  static ThemeMode _parseThemeMode(String? modeStr) {
    if (modeStr == 'light') {
      return ThemeMode.light;
    }
    return ThemeMode.dark;
  }

  /// Convert ThemeMode to string for Firestore and local prefs
  static String _themeModeToString(ThemeMode mode) {
    if (mode == ThemeMode.light) {
      return 'light';
    }
    return 'dark';
  }

  /// 1. Initialize local cache synchronously/instantly from SharedPreferences BEFORE runApp
  /// Eliminates the initial dark mode or black screen flash.
  static Future<void> initializeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(_prefsKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final mode = _parseThemeMode(cachedStr);
        _themeModeNotifier.value = mode;
        if (kDebugMode) {
          print(
            'ThemeService: Preloaded cached theme from SharedPreferences: $mode',
          );
        }
      } else {
        // If not locally cached yet, try fetching silently
        _syncFromFirestoreSilently();
      }
    } catch (e) {
      if (kDebugMode) print('ThemeService: Error initializing cache: $e');
    }
  }

  /// 2. Sync silently from Firestore
  static Future<void> _syncFromFirestoreSilently() async {
    try {
      final mode = await getThemePreference();
      if (_themeModeNotifier.value != mode) {
        _themeModeNotifier.value = mode;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _themeModeToString(mode));
    } catch (e) {
      if (kDebugMode) print('ThemeService: Silent sync error: $e');
    }
  }

  /// 3. Sync directly from user profile map when AuthWrapper fetches user document
  static Future<void> syncFromUserData(Map<String, dynamic>? userData) async {
    if (userData == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSyncedAfterInstall = prefs.getBool(_freshInstallKey) ?? false;

      // For the first time login after a fresh install, ALWAYS make the default theme dark only.
      if (!hasSyncedAfterInstall) {
        await prefs.setBool(_freshInstallKey, true);
        if (_themeModeNotifier.value != ThemeMode.dark) {
          _themeModeNotifier.value = ThemeMode.dark;
          if (kDebugMode) {
            print(
              'ThemeService: First login after fresh install -> opening dark mode only',
            );
          }
        }
        await prefs.setString(_prefsKey, 'dark');
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'preferredTheme': 'dark',
          }, SetOptions(merge: true));
        }
        return;
      }

      final preferredTheme = userData['preferredTheme'] as String?;
      if (preferredTheme != null && preferredTheme.isNotEmpty) {
        final mode = _parseThemeMode(preferredTheme);
        if (_themeModeNotifier.value != mode) {
          _themeModeNotifier.value = mode;
          if (kDebugMode) {
            print(
              'ThemeService: Synced theme from user data without flash: $mode',
            );
          }
        }
        // Ensure local disk cache is up to date for next launch
        await prefs.setString(_prefsKey, preferredTheme);
      } else {
        // If preferredTheme is not set, use local cache, or default to dark
        final cachedStr = prefs.getString(_prefsKey) ?? 'dark';
        final mode = _parseThemeMode(cachedStr);
        if (_themeModeNotifier.value != mode) {
          _themeModeNotifier.value = mode;
          if (kDebugMode) {
            print(
              'ThemeService: Using locally cached theme since Firestore is empty: $mode',
            );
          }
        }
        await prefs.setString(_prefsKey, cachedStr);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'preferredTheme': cachedStr,
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      if (kDebugMode) print('ThemeService: Error in syncFromUserData: $e');
    }
  }

  /// Get the current user's preferred theme mode from Firestore
  /// Checks SharedPreferences first, then Firestore, ensuring the notifier is always synced
  static Future<ThemeMode> getThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(_prefsKey);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (cachedStr != null && cachedStr.isNotEmpty) {
          final mode = _parseThemeMode(cachedStr);
          if (_themeModeNotifier.value != mode) {
            _themeModeNotifier.value = mode;
          }
          return mode;
        }
        if (_themeModeNotifier.value != ThemeMode.dark) {
          _themeModeNotifier.value = ThemeMode.dark;
        }
        return ThemeMode.dark;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final userData = doc.data();
        final preferredTheme = userData?['preferredTheme'] as String?;

        final hasSyncedAfterInstall = prefs.getBool(_freshInstallKey) ?? false;
        if (!hasSyncedAfterInstall) {
          await prefs.setBool(_freshInstallKey, true);
          const mode = ThemeMode.dark;
          if (_themeModeNotifier.value != mode) {
            _themeModeNotifier.value = mode;
          }
          await prefs.setString(_prefsKey, 'dark');
          FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'preferredTheme': 'dark',
          }, SetOptions(merge: true));
          return mode;
        }

        if (preferredTheme != null && preferredTheme.isNotEmpty) {
          final mode = _parseThemeMode(preferredTheme);
          await prefs.setString(_prefsKey, preferredTheme);
          if (_themeModeNotifier.value != mode) {
            _themeModeNotifier.value = mode;
          }
          return mode;
        } else {
          // If preferredTheme is not set, use local cache, or default to dark
          final modeStr = cachedStr ?? 'dark';
          final mode = _parseThemeMode(modeStr);
          if (_themeModeNotifier.value != mode) {
            _themeModeNotifier.value = mode;
          }
          await prefs.setString(_prefsKey, modeStr);
          FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'preferredTheme': modeStr,
          }, SetOptions(merge: true));
          return mode;
        }
      }

      // If user doc not found or during first setup, use cached or default to dark
      final modeStr = cachedStr ?? 'dark';
      final mode = _parseThemeMode(modeStr);
      if (_themeModeNotifier.value != mode) {
        _themeModeNotifier.value = mode;
      }
      await prefs.setString(_prefsKey, modeStr);
      try {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'preferredTheme': modeStr,
        }, SetOptions(merge: true));
      } catch (_) {}
      return mode;
    } catch (e) {
      if (kDebugMode) print('ThemeService: Error getting preference: $e');
      return _themeModeNotifier.value;
    }
  }

  /// Get theme preference synchronously (returns cached value)
  static ThemeMode getThemePreferenceSync() {
    return _themeModeNotifier.value;
  }

  /// Initialize the theme preference service
  static Future<void> initialize() async {
    await initializeCache();
  }

  /// Update user's theme preference instantaneously, caching to disk for zero latency
  static Future<bool> updateThemePreference(ThemeMode mode) async {
    try {
      final modeStr = _themeModeToString(mode);
      if (kDebugMode) {
        print('ThemeService: Updating theme preference to: $modeStr');
      }

      // 1. Update the notifier immediately for instant UI feedback
      _themeModeNotifier.value = mode;

      // 2. Save immediately to local disk so next startup uses exact theme on frame 0
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, modeStr);

      // 3. Persist to Firestore asynchronously without blocking UI
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'preferredTheme': modeStr,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return true;
    } catch (e) {
      if (kDebugMode) print('Error updating theme preference: $e');
      return false;
    }
  }

  /// Get theme display name
  static String getThemeDisplayName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
      default:
        return 'Dark Mode';
    }
  }
}
