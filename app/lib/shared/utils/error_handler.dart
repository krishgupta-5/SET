import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:startup_expense_tracker/shared/widgets/error_popup.dart';

class ErrorHandler {
  static void handleAuthError({
    required BuildContext context,
    required FirebaseAuthException error,
    VoidCallback? onRetry,
  }) {
    String message = '';

    switch (error.code) {
      case 'weak-password':
        message =
            'Password is too weak. Please choose a stronger password with at least 6 characters, including uppercase, lowercase, numbers, and special characters.';
        break;

      case 'email-already-in-use':
        message =
            'This email address is already registered. Please try logging in or use a different email address.';
        break;

      case 'user-not-found':
        message =
            'No account found with this email address. Please check your email or sign up for a new account.';
        break;

      case 'wrong-password':
        message =
            'The password you entered is incorrect. Please try again or reset your password.';
        break;

      case 'invalid-email':
        message =
            'The email address you entered is not valid. Please enter a valid email address.';
        break;

      case 'user-disabled':
        message =
            'Your account has been disabled. Please contact support for assistance.';
        break;

      case 'too-many-requests':
        message =
            'Too many unsuccessful login attempts. Please try again later or reset your password.';
        break;

      case 'operation-not-allowed':
        message = 'This sign-in method is not enabled. Please contact support.';
        break;

      case 'account-exists-with-different-credential':
        message =
            'An account already exists with the same email address but different sign-in method.';
        break;

      case 'invalid-credential':
        message =
            'The provided credentials are invalid. Please check your information and try again.';
        break;

      case 'requires-recent-login':
        message =
            'This operation requires recent authentication. Please log in again and try.';
        break;

      default:
        message =
            error.message ??
            'An authentication error occurred. Please try again.';
        break;
    }

    ErrorPopup.showAuth(context: context, message: message);
  }

  static void handleValidationError({
    required BuildContext context,
    required String field,
    required String validationMessage,
    VoidCallback? onFix,
  }) {
    String message = validationMessage;

    switch (validationMessage.toLowerCase()) {
      case 'passwords do not match':
        message =
            'The passwords you entered do not match. Please make sure both passwords are identical.';
        break;

      case 'password must be at least 6 characters':
        message =
            'Password must be at least 6 characters long. Please choose a stronger password.';
        break;

      case 'email is required':
        message = 'Please enter your email address to continue.';
        break;

      case 'password is required':
        message = 'Please enter your password to continue.';
        break;

      case 'invalid email format':
        message =
            'Please enter a valid email address (e.g., name@example.com).';
        break;
    }

    ErrorPopup.showValidation(context: context, message: message);
  }

  static void handleNetworkError({
    required BuildContext context,
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    String message =
        customMessage ??
        'Unable to connect to the server. Please check your internet connection and try again.';

    ErrorPopup.showNetwork(context: context, message: message);
  }

  static void handleServerError({
    required BuildContext context,
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    String message =
        customMessage ??
        'Server is currently unavailable. Please try again in a few moments.';

    ErrorPopup.showServer(context: context, message: message);
  }

  static void handleGeneralError({
    required BuildContext context,
    String? title,
    required String message,
    VoidCallback? onRetry,
    String? actionText,
  }) {
    ErrorPopup.showError(
      context: context,
      title: title ?? 'Error',
      message: message,
    );
  }

  static void handleSuccess({
    required BuildContext context,
    required String message,
    VoidCallback? onAction,
    String? actionText,
  }) {
    ErrorPopup.showSuccess(context: context, message: message);
  }

  static void handleWarning({
    required BuildContext context,
    required String message,
    VoidCallback? onAction,
    String? actionText,
  }) {
    ErrorPopup.showWarning(context: context, message: message);
  }

  static void handleInfo({
    required BuildContext context,
    required String message,
    VoidCallback? onAction,
    String? actionText,
  }) {
    ErrorPopup.showInfo(context: context, message: message);
  }

  static void handleError({
    required BuildContext context,
    required Object error,
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    if (error is FirebaseAuthException) {
      handleAuthError(context: context, error: error, onRetry: onRetry);
    } else if (error.toString().toLowerCase().contains('network') ||
        error.toString().toLowerCase().contains('connection') ||
        error.toString().toLowerCase().contains('timeout')) {
      handleNetworkError(
        context: context,
        customMessage: customMessage,
        onRetry: onRetry,
      );
    } else if (error.toString().toLowerCase().contains('server') ||
        error.toString().toLowerCase().contains('500') ||
        error.toString().toLowerCase().contains('503')) {
      handleServerError(
        context: context,
        customMessage: customMessage,
        onRetry: onRetry,
      );
    } else {
      handleGeneralError(
        context: context,
        message: customMessage ?? error.toString(),
        onRetry: onRetry,
      );
    }
  }
}
