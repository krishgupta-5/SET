import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../widgets/rx_ui.dart';

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

/// Top banner: themed card with a tinted icon badge, title, message, a
/// close button and a thin bar that runs down until it auto-dismisses.
/// Slides down + fades in; tap, swipe up or press x to dismiss.
class _ErrorPopupWidgetState extends State<_ErrorPopupWidget>
    with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _in,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );

  bool _dismissing = false;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _in.forward();
    if (widget.duration.inMilliseconds > 0) {
      _timer.forward().whenComplete(() {
        if (mounted) _dismiss();
      });
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _timer.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _timer.stop();
    _in.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final (fg, bg, icon) = _style(rx);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          final v = _curve.value;
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, reduce ? 0 : (-24 * (1 - v)) + _drag),
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: Semantics(
            liveRegion: true,
            label: '${widget.title}. ${widget.message}',
            child: GestureDetector(
              onTap: _dismiss,
              // Swipe up to dismiss.
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < 0 || _drag < 0) {
                  setState(() => _drag = (_drag + d.delta.dy).clamp(-80, 0));
                }
              },
              onVerticalDragEnd: (_) {
                if (_drag < -24) {
                  _dismiss();
                } else {
                  setState(() => _drag = 0);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: rx.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: rx.hairline),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.45 : 0.07),
                      blurRadius: 24,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: HugeIcon(
                              icon: icon,
                              color: fg,
                              size: 19,
                              strokeWidth: 1.9,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _title(),
                                    style: RxText.heading(
                                      context,
                                    ).copyWith(fontSize: 14.5),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.message,
                                    style: RxText.caption(
                                      context,
                                    ).copyWith(fontSize: 13, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: 'Dismiss',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _dismiss,
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: Center(
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedCancel01,
                                    color: rx.textTertiary,
                                    size: 16,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Time left before auto-dismiss.
                    AnimatedBuilder(
                      animation: _timer,
                      builder: (_, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 1 - _timer.value,
                          child: Container(
                            height: 3,
                            color: fg.withValues(alpha: 0.55),
                          ),
                        ),
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

  /// Sentence-case titles ("Authentication Error" -> "Authentication error").
  String _title() {
    final t = widget.title;
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  (Color, Color, List<List<dynamic>>) _style(RxColors rx) {
    switch (widget.type) {
      case ErrorType.success:
        return (
          rx.positive,
          rx.positiveSoft,
          HugeIcons.strokeRoundedCheckmarkCircle02,
        );
      case ErrorType.warning:
        return (rx.warning, rx.warningSoft, HugeIcons.strokeRoundedAlert02);
      case ErrorType.info:
        return (
          rx.textPrimary,
          rx.surfaceMuted,
          HugeIcons.strokeRoundedInformationCircle,
        );
      case ErrorType.network:
        return (
          rx.negative,
          rx.negativeSoft,
          HugeIcons.strokeRoundedWifiDisconnected01,
        );
      case ErrorType.authentication:
        return (
          rx.negative,
          rx.negativeSoft,
          HugeIcons.strokeRoundedSquareLock02,
        );
      case ErrorType.validation:
        return (rx.warning, rx.warningSoft, HugeIcons.strokeRoundedEdit02);
      case ErrorType.server:
      case ErrorType.general:
        return (
          rx.negative,
          rx.negativeSoft,
          HugeIcons.strokeRoundedAlertCircle,
        );
    }
  }
}
