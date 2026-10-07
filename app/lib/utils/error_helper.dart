import 'package:flutter/material.dart';
import '../../../utils/data_helpers.dart';

/// Standardized error handling for consistent UX across the app
class ErrorHelper {
  ErrorHelper._();

  /// Show error message in a snackbar
  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show success message in a snackbar
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontFamily: 'Satoshi', color: Colors.black),
        ),
        backgroundColor: const Color(0xFF30D158),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show info message in a snackbar
  static void showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0A84FF),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show warning message in a snackbar
  static void showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontFamily: 'Satoshi', color: Colors.black),
        ),
        backgroundColor: const Color(0xFF9B59B6),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Build error card widget for consistent error display
  static Widget buildErrorCard({
    required String message,
    VoidCallback? onRetry,
    String? retryText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                retryText ?? 'Retry',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build empty state widget for consistent empty data display
  static Widget buildEmptyState({
    required String message,
    IconData? icon,
    VoidCallback? onAction,
    String? actionText,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.inbox_outlined, color: Colors.white38, size: 64),
          const SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (onAction != null && actionText != null) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                actionText,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build loading widget for consistent loading display
  static Widget buildLoadingWidget({String? message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white38,
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Handle and display errors consistently
  static void handleError(
    BuildContext context,
    dynamic error, {
    String? fallbackMessage,
  }) {
    final errorMessage = DataHelpers.getErrorMessage(
      error,
      fallbackMessage ?? 'An unexpected error occurred.',
    );
    showErrorSnackBar(context, errorMessage);

    // Also log to console for debugging
    debugPrint('🚨 Error: $error');
    debugPrint('🚨 Message: $errorMessage');
  }
}
