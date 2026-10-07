import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as developer;

class AuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Backend rate limiting check
  static Future<bool> isRateLimited(String email) async {
    try {
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

      final rateLimitDoc = await _firestore
          .collection('rate_limits')
          .doc(email.toLowerCase())
          .get();

      if (!rateLimitDoc.exists) {
        return false;
      }

      final data = rateLimitDoc.data() as Map<String, dynamic>;
      final attempts = data['attempts'] as int? ?? 0;
      final lastAttempt = (data['lastAttempt'] as Timestamp?)?.toDate();

      if (attempts >= 5 &&
          lastAttempt != null &&
          lastAttempt.isAfter(fiveMinutesAgo)) {
        return true;
      }

      return false;
    } catch (e) {
      developer.log('Rate limit check error: $e');
      return true; // Fail closed for security
    }
  }

  // Record login attempt for backend rate limiting
  static Future<void> recordLoginAttempt(String email, bool success) async {
    try {
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

      final rateLimitRef = _firestore
          .collection('rate_limits')
          .doc(email.toLowerCase());

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(rateLimitRef);

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          final attempts = data['attempts'] as int? ?? 0;
          final lastAttempt = (data['lastAttempt'] as Timestamp?)?.toDate();

          if (lastAttempt != null && lastAttempt.isBefore(fiveMinutesAgo)) {
            // Reset counter after 5 minutes
            transaction.set(rateLimitRef, {
              'attempts': success ? 0 : 1,
              'lastAttempt': FieldValue.serverTimestamp(),
              'email': email.toLowerCase(),
            });
          } else {
            // Increment counter
            transaction.set(rateLimitRef, {
              'attempts': success ? 0 : attempts + 1,
              'lastAttempt': FieldValue.serverTimestamp(),
              'email': email.toLowerCase(),
            });
          }
        } else {
          // First attempt
          transaction.set(rateLimitRef, {
            'attempts': success ? 0 : 1,
            'lastAttempt': FieldValue.serverTimestamp(),
            'email': email.toLowerCase(),
          });
        }
      });
    } catch (e) {
      developer.log('Record login attempt error: $e');
    }
  }

  // Check if account is locked due to suspicious activity
  static Future<bool> isAccountLocked(String email) async {
    try {
      final accountDoc = await _firestore
          .collection('account_security')
          .doc(email.toLowerCase())
          .get();

      if (!accountDoc.exists) {
        return false;
      }

      final data = accountDoc.data() as Map<String, dynamic>;
      final isLocked = data['isLocked'] as bool? ?? false;
      final lockUntil = (data['lockUntil'] as Timestamp?)?.toDate();

      if (isLocked && lockUntil != null && lockUntil.isAfter(DateTime.now())) {
        return true;
      }

      // Auto-unlock if time expired
      if (isLocked && lockUntil != null && lockUntil.isBefore(DateTime.now())) {
        await _firestore
            .collection('account_security')
            .doc(email.toLowerCase())
            .update({
              'isLocked': false,
              'unlockedAt': FieldValue.serverTimestamp(),
            });
        return false;
      }

      return isLocked;
    } catch (e) {
      developer.log('Account lock check error: $e');
      return false;
    }
  }

  // Lock account temporarily
  static Future<void> lockAccountTemporarily(
    String email,
    Duration duration,
  ) async {
    try {
      await _firestore
          .collection('account_security')
          .doc(email.toLowerCase())
          .set({
            'isLocked': true,
            'lockUntil': Timestamp.fromDate(DateTime.now().add(duration)),
            'lockedAt': FieldValue.serverTimestamp(),
            'reason': 'multiple_failed_attempts',
            'email': email.toLowerCase(),
          }, SetOptions(merge: true));
    } catch (e) {
      developer.log('Lock account error: $e');
    }
  }

  // Enhanced password reset logging
  static Future<void> logPasswordReset({
    required String email,
    required String status,
    String? error,
  }) async {
    try {
      await _firestore.collection('auth_logs').add({
        'type': 'password_reset',
        'status': status, // 'requested', 'success', 'failed'
        'email': email.toLowerCase(),
        'timestamp': FieldValue.serverTimestamp(),
        'userAgent': 'web', // Could be enhanced with actual user agent
        'error': error,
      });
    } catch (e) {
      developer.log('Password reset logging error: $e');
    }
  }

  // Get normalized verification status - now always returns true
  static bool isEmailVerified(User user) {
    return true; // Email verification removed - always return true
  }

  // Force token refresh
  static Future<void> refreshAuthToken() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      developer.log('Token refresh error: $e');
    }
  }

  // Enhanced user session validation
  static Future<bool> isSessionValid() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Force refresh to check token validity
      await user.reload();
      return _auth.currentUser != null;
    } catch (e) {
      developer.log('Session validation error: $e');
      return false;
    }
  }
}
