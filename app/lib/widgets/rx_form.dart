import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'rx_ui.dart';

/// Form building blocks for the redesign: text inputs, buttons, a sticky
/// bottom action bar, segmented choices, toasts and a confirm dialog.
/// Visual only; screens keep their own validation and data logic.

// ---------------------------------------------------------------------------
// Text input
// ---------------------------------------------------------------------------

/// Labelled text input. Same 52px shell as [RxSelectField] / [RxDateField]
/// so mixed forms line up.
class RxTextInput extends StatelessWidget {
  const RxTextInput({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.prefixText,
    this.suffix,
    this.helper,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.enabled = true,
    this.autofocus = false,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final List<List<dynamic>>? icon;

  /// Shown before the text, e.g. a currency symbol.
  final String? prefixText;
  final Widget? suffix;

  /// Small line under the field.
  final String? helper;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool enabled;
  final bool autofocus;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Red border + this message under the field (replaces [helper]).
  final String? errorText;

  /// Decimal number pad with digits and one separator only.
  static final List<TextInputFormatter> money = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final multi = maxLines > 1;

    final field = Container(
      constraints: BoxConstraints(minHeight: multi ? 96 : 52),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: multi ? 4 : 0),
      decoration: BoxDecoration(
        color: enabled ? rx.surface : rx.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        // Inputs keep a visible boundary (3:1 non-text contrast).
        border: Border.all(
          color: errorText != null
              ? rx.negative
              : rx.textPrimary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: multi
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: multi ? 14 : 0),
              child: HugeIcon(
                icon: icon!,
                color: rx.textSecondary,
                size: 19,
                strokeWidth: 1.7,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (prefixText != null) ...[
            Text(
              prefixText!,
              style: RxText.body(context, color: rx.textSecondary),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofocus: autofocus,
              obscureText: obscure,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              textInputAction: multi
                  ? TextInputAction.newline
                  : textInputAction,
              textCapitalization: textCapitalization,
              maxLines: obscure ? 1 : maxLines,
              // Never above maxLines (e.g. a 2-line address field).
              minLines: obscure ? 1 : (maxLines < 3 ? maxLines : 3),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              cursorColor: rx.textPrimary,
              style: RxText.body(
                context,
                color: enabled ? rx.textPrimary : rx.textSecondary,
              ).copyWith(fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: multi ? 12 : 15),
                hintText: hint,
                hintStyle: RxText.body(
                  context,
                  color: rx.textTertiary,
                ).copyWith(fontWeight: FontWeight.w400),
              ),
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: 8), suffix!],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label!,
              style: RxText.label(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        field,
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              errorText!,
              style: RxText.caption(context, color: rx.negative),
            ),
          )
        else if (helper != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(helper!, style: RxText.caption(context)),
          ),
      ],
    );
  }
}

/// Big centred amount entry, like Add Expense. Number pad only.
class RxAmountInput extends StatelessWidget {
  const RxAmountInput({
    super.key,
    required this.controller,
    required this.symbol,
    this.label,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String symbol;
  final String? label;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Column(
      children: [
        if (label != null) ...[
          Text(label!, style: RxText.label(context)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: RxTextInput.money,
          textAlign: TextAlign.center,
          onChanged: onChanged,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          cursorColor: rx.textPrimary,
          style: RxText.hero(context, size: 48),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            hintText: '0',
            hintStyle: RxText.hero(context, size: 48, color: rx.textTertiary),
            prefixText: '$symbol ',
            prefixStyle: RxText.value(
              context,
              size: 28,
              color: rx.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum RxButtonStyle { primary, secondary, destructive }

/// Full-width 52px button. Shows a spinner and ignores taps while [loading].
class RxButton extends StatelessWidget {
  const RxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.style = RxButtonStyle.primary,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onTap;
  final List<List<dynamic>>? icon;
  final bool loading;
  final RxButtonStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final enabled = onTap != null && !loading;
    final (bg, fg) = switch (style) {
      RxButtonStyle.primary => (rx.inverse, rx.onInverse),
      RxButtonStyle.secondary => (rx.surfaceMuted, rx.textPrimary),
      RxButtonStyle.destructive => (rx.negativeSoft, rx.negative),
    };

    return RxPressable(
      onTap: enabled ? onTap : null,
      semanticLabel: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      HugeIcon(
                        icon: icon!,
                        color: fg,
                        size: 19,
                        strokeWidth: 2,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: RxText.body(
                        context,
                        color: fg,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Sticky footer for a form's main action. Sits above the keyboard and the
/// gesture bar, on the page colour with a hairline on top.
class RxBottomBar extends StatelessWidget {
  const RxBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: rx.background,
        border: Border(top: BorderSide(color: rx.hairline)),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Choices
// ---------------------------------------------------------------------------

/// Segmented control. Switches instantly (frequent action, no animation).
class RxSegmented<T> extends StatelessWidget {
  const RxSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// value -> label
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: rx.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: e.key == value,
                label: e.value,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (e.key == value) return;
                    HapticFeedback.selectionClick();
                    onChanged(e.key);
                  },
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // Inner radius = outer (14) - padding (3).
                      borderRadius: BorderRadius.circular(11),
                      color: e.key == value ? rx.surface : Colors.transparent,
                      boxShadow: e.key == value && !isDark
                          ? const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          RxText.label(
                            context,
                            color: e.key == value
                                ? rx.textPrimary
                                : rx.textSecondary,
                          ).copyWith(
                            fontWeight: e.key == value
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings-style row with a trailing switch.
class RxSwitchRow extends StatelessWidget {
  const RxSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RxText.body(context)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: RxText.caption(context)),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: rx.inverse,
            activeThumbColor: rx.onInverse,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feedback
// ---------------------------------------------------------------------------

/// One toast style app-wide: floating, surface-coloured, icon + message.
void showRxToast(BuildContext context, String message, {bool isError = false}) {
  final rx = context.rx;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          HugeIcon(
            icon: isError
                ? HugeIcons.strokeRoundedAlert02
                : HugeIcons.strokeRoundedCheckmarkCircle02,
            color: isError ? rx.negative : rx.positive,
            size: 18,
            strokeWidth: 2,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: RxText.body(context))),
        ],
      ),
      backgroundColor: rx.surface,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: rx.hairline),
      ),
      elevation: 6,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Themed confirm dialog. Resolves true when confirmed.
///
/// Centred card with a tinted icon badge, title, message and two buttons.
/// Scales up from 0.94 and fades in (220ms ease-out); reduced motion fades
/// only. [destructive] tints it red; pass [icon] to override the badge.
Future<bool> showRxConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  List<List<dynamic>>? icon,
}) async {
  final rx = context.rx;
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel,
    barrierColor: rx.barrier,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      final reduce = MediaQuery.disableAnimationsOf(ctx);
      return FadeTransition(
        opacity: curved,
        child: reduce
            ? child
            : ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(curved),
                child: child,
              ),
      );
    },
    pageBuilder: (ctx, _, _) => _RxConfirmCard(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
    ),
  );
  return result ?? false;
}

class _RxConfirmCard extends StatelessWidget {
  const _RxConfirmCard({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final List<List<dynamic>>? icon;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (badgeBg, badgeFg) = destructive
        ? (rx.negativeSoft, rx.negative)
        : (rx.surfaceMuted, rx.textPrimary);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Material(
              color: rx.surface,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: dark ? rx.hairline : Colors.transparent,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Badge with a soft ring around it.
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: badgeBg.withValues(alpha: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: badgeBg,
                        ),
                        alignment: Alignment.center,
                        child: HugeIcon(
                          icon:
                              icon ??
                              (destructive
                                  ? HugeIcons.strokeRoundedAlert02
                                  : HugeIcons.strokeRoundedHelpCircle),
                          color: badgeFg,
                          size: 22,
                          strokeWidth: 1.9,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: RxText.heading(
                        context,
                      ).copyWith(fontSize: 18, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: RxText.caption(
                        context,
                      ).copyWith(fontSize: 14, height: 1.45),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: RxButton(
                            label: cancelLabel,
                            height: 48,
                            style: RxButtonStyle.secondary,
                            onTap: () => Navigator.pop(context, false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RxButton(
                            label: confirmLabel,
                            height: 48,
                            style: destructive
                                ? RxButtonStyle.destructive
                                : RxButtonStyle.primary,
                            onTap: () => Navigator.pop(context, true),
                          ),
                        ),
                      ],
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
}

/// Label/value row for read-only detail cards.
class RxDetailRow extends StatelessWidget {
  const RxDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(label, style: RxText.label(context)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: RxText.body(context, color: valueColor),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passwords
// ---------------------------------------------------------------------------

/// [RxTextInput] for passwords, with its own show/hide toggle.
class RxPasswordInput extends StatefulWidget {
  const RxPasswordInput({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<RxPasswordInput> createState() => _RxPasswordInputState();
}

class _RxPasswordInputState extends State<RxPasswordInput> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxTextInput(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      icon: HugeIcons.strokeRoundedLockPassword,
      obscure: _obscure,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.none,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      suffix: Semantics(
        button: true,
        label: _obscure ? 'Show password' : 'Hide password',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _obscure = !_obscure),
          child: SizedBox(
            width: 40,
            height: 44,
            child: Center(
              child: HugeIcon(
                icon: _obscure
                    ? HugeIcons.strokeRoundedViewOffSlash
                    : HugeIcons.strokeRoundedView,
                color: rx.textSecondary,
                size: 19,
                strokeWidth: 1.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live checklist of password rules. Each row ticks green when met.
class RxPasswordChecklist extends StatelessWidget {
  const RxPasswordChecklist({super.key, required this.rules});

  /// label -> met
  final Map<String, bool> rules;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in rules.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.value ? rx.positive : Colors.transparent,
                      border: Border.all(
                        color: e.value ? rx.positive : rx.textTertiary,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: e.value
                        ? HugeIcon(
                            icon: HugeIcons.strokeRoundedTick02,
                            color: rx.surface,
                            size: 12,
                            strokeWidth: 3,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    e.key,
                    style: RxText.caption(
                      context,
                      color: e.value ? rx.textPrimary : rx.textSecondary,
                    ).copyWith(fontSize: 13.5),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
