import 'package:flutter/material.dart';

enum ErrorType {
  validation,
  network,
  authentication,
  server,
  general,
  success,
  warning,
  info,
}

class ErrorPopup {
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required ErrorType type,
    Duration? duration,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ErrorPopupWidget(
        title: title,
        message: message,
        type: type,
        onDismiss: () => overlayEntry.remove(),
        duration: duration ?? _getDurationForType(type),
      ),
    );

    overlay.insert(overlayEntry);
  }

  static Duration _getDurationForType(ErrorType type) {
    switch (type) {
      case ErrorType.success:
      case ErrorType.info:
        return const Duration(seconds: 3);
      case ErrorType.warning:
        return const Duration(seconds: 4);
      case ErrorType.validation:
      case ErrorType.network:
      case ErrorType.authentication:
      case ErrorType.server:
      case ErrorType.general:
        return const Duration(seconds: 5);
    }
  }

  static void showError({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    show(
      context: context,
      title: title,
      message: message,
      type: ErrorType.general,
    );
  }

  static void showValidation({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Validation Error',
      message: message,
      type: ErrorType.validation,
    );
  }

  static void showNetwork({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Network Error',
      message: message,
      type: ErrorType.network,
    );
  }

  static void showAuth({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Authentication Error',
      message: message,
      type: ErrorType.authentication,
    );
  }

  static void showServer({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Server Error',
      message: message,
      type: ErrorType.server,
    );
  }

  static void showSuccess({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Success',
      message: message,
      type: ErrorType.success,
    );
  }

  static void showWarning({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Warning',
      message: message,
      type: ErrorType.warning,
    );
  }

  static void showInfo({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Info',
      message: message,
      type: ErrorType.info,
    );
  }
}

class _ErrorPopupWidget extends StatefulWidget {
  final String title;
  final String message;
  final ErrorType type;
  final VoidCallback onDismiss;
  final Duration duration;

  const _ErrorPopupWidget({
    required this.title,
    required this.message,
    required this.type,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_ErrorPopupWidget> createState() => _ErrorPopupWidgetState();
}

class _ErrorPopupWidgetState extends State<_ErrorPopupWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutBack,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Auto dismiss after duration
    if (widget.duration.inMilliseconds > 0) {
      Future.delayed(widget.duration, () {
        if (mounted) {
          _dismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: _getStatusColor(),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.message,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (widget.type) {
      case ErrorType.success:
        return Colors.greenAccent; // FIXED: Green for success
      case ErrorType.warning:
        return Colors.orangeAccent;
      case ErrorType.info:
        return Colors.lightBlueAccent;
      case ErrorType.validation:
      case ErrorType.network:
      case ErrorType.authentication:
      case ErrorType.server:
      case ErrorType.general:
        return Colors.redAccent; // FIXED: Red for errors
    }
  }
}
