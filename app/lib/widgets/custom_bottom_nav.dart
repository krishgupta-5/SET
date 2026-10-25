import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/theme/rx_colors.dart';

/// One destination in [RxTabBar].
class RxTabItem {
  const RxTabItem({required this.icon, required this.label});

  final List<List<dynamic>> icon;
  final String label;
}

/// Floating tab bar: one frosted-glass pill holding all destinations, with
/// the round add button in the centre (Home, Expenses, +, Team, AI CFO).
///
/// Place it in a [Stack] above the page (not in `Scaffold.bottomNavigationBar`)
/// so content scrolls underneath the glass. [RxTabBar.reservedHeight] tells
/// pages how much bottom space to leave clear.
///
/// - Tabs switch instantly; only the active capsule's colour fades (150ms).
///   The active tab is also carried by colour, stroke and label weight.
/// - The add button scales to 0.96 on press over 150ms ease-out, skipped
///   when the OS asks for reduced motion.
/// - Pass `selectedIndex: -1` when the visible page has no tab (Settings).
class RxTabBar extends StatelessWidget {
  const RxTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onAddPressed,
    this.addLabel = 'Add expense',
  }) : assert(items.length == 4, 'Two tabs sit on each side of the add button');

  final List<RxTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onAddPressed;
  final String addLabel;

  static const double barHeight = 64;
  static const double _sideMargin = 16;
  static const double _minBottomMargin = 16;
  static const double _inset = 6;
  static const double _radius = barHeight / 2;

  static double _bottomMargin(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, _minBottomMargin);

  /// Height of the fade above the pill in [RxNavBackdrop].
  static const double fadeHeight = 28;

  /// Height of [RxNavBackdrop], measured from the screen's bottom edge.
  static double backdropHeight(BuildContext context) =>
      _bottomMargin(context) + barHeight + fadeHeight;

  /// Bottom padding for scrollable tab pages, so their last item can scroll
  /// fully clear of the bar and its backdrop.
  static double reservedHeight(BuildContext context) =>
      backdropHeight(context) + 8;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideMargin,
        0,
        _sideMargin,
        _bottomMargin(context),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: rx.navShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: barHeight,
              padding: const EdgeInsets.all(_inset),
              decoration: BoxDecoration(
                color: rx.navGlass,
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: rx.navBorder),
              ),
              child: Row(
                children: [
                  _tab(0),
                  _tab(1),
                  Expanded(
                    child: Center(
                      child: _AddButton(
                        label: addLabel,
                        // Same height as the active capsule, so both sit
                        // concentric inside the pill.
                        size: barHeight - _inset * 2,
                        onPressed: onAddPressed,
                      ),
                    ),
                  ),
                  _tab(2),
                  _tab(3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i) => Expanded(
    child: _TabButton(
      item: items[i],
      selected: i == selectedIndex,
      // Concentric with the pill: outer radius minus the inset.
      radius: _radius - _inset,
      onTap: () {
        if (i != selectedIndex) HapticFeedback.selectionClick();
        onTabSelected(i);
      },
    ),
  );
}

/// Solid page-coloured strip behind [RxTabBar], fading out at its top edge.
///
/// Content scrolling down the page fades into the background before it
/// reaches the bar, so the bar always sits on a clean surface (the look the
/// Expenses tab has when its list is short), on every tab.
class RxNavBackdrop extends StatelessWidget {
  const RxNavBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = context.rx.background;
    final height = RxTabBar.backdropHeight(context);

    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg.withAlpha(0), bg],
            // Fade over the first [fadeHeight] px, solid below.
            stops: [0, RxTabBar.fadeHeight / height],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.radius,
    required this.onTap,
  });

  final RxTabItem item;
  final bool selected;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = selected ? rx.textPrimary : rx.textTertiary;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? rx.navIndicator : rx.navIndicator.withAlpha(0),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: item.icon,
                color: color,
                size: 22,
                // Stroke tracks the label weight: 500 -> 1.6, 700 -> 2.0.
                strokeWidth: selected ? 2.0 : 1.6,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 10.5,
                  height: 1.2,
                  letterSpacing: -0.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  const _AddButton({
    required this.label,
    required this.size,
    required this.onPressed,
  });

  final String label;
  final double size;
  final VoidCallback onPressed;

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 0.96 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: rx.inverse,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedAdd01,
              color: rx.onInverse,
              size: 22,
              strokeWidth: 2.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// What the user picked in [showAddExpenseSheet].
enum AddExpenseAction { scan, manual }

/// Bottom sheet opened by the tab bar's add button.
Future<AddExpenseAction?> showAddExpenseSheet(BuildContext context) {
  final rx = context.rx;
  return showModalBottomSheet<AddExpenseAction>(
    context: context,
    backgroundColor: rx.sheet,
    barrierColor: rx.barrier,
    useSafeArea: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _AddExpenseSheet(),
  );
}

class _AddExpenseSheet extends StatelessWidget {
  const _AddExpenseSheet();

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: rx.textPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 14),
            child: Text(
              'New expense',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: rx.textPrimary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: rx.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: rx.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SheetOption(
                  icon: HugeIcons.strokeRoundedCamera01,
                  title: 'Scan receipt',
                  subtitle: 'Auto-fill the details from a photo',
                  onTap: () => Navigator.pop(context, AddExpenseAction.scan),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 68),
                  child: Divider(height: 1, thickness: 1, color: rx.hairline),
                ),
                _SheetOption(
                  icon: HugeIcons.strokeRoundedPencilEdit02,
                  title: 'Add manually',
                  subtitle: 'Enter the amount and category yourself',
                  onTap: () => Navigator.pop(context, AddExpenseAction.manual),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: rx.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: rx.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: HugeIcon(
                  icon: icon,
                  color: rx.textPrimary,
                  size: 20,
                  strokeWidth: 1.8,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.15,
                        color: rx.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: rx.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                color: rx.textTertiary,
                size: 18,
                strokeWidth: 1.8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
