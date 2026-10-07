import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class ModernNavBar extends StatelessWidget {
  final Function(int) onTabSelected;
  final int selectedIndex;

  const ModernNavBar({
    super.key,
    required this.onTabSelected,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Solid Color Palette
    final backgroundColor = isDark
        ? const Color(0xFF141416)
        : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final shadowColor = isDark
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.08);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(
                0,
                HugeIcons.strokeRoundedHome11,
                HugeIcons.strokeRoundedHome11,
                "Home",
                isDark,
              ),
              _buildNavItem(
                1,
                HugeIcons.strokeRoundedUserGroup,
                HugeIcons.strokeRoundedUserGroup,
                "Team",
                isDark,
              ),
              _buildNavItem(
                2,
                HugeIcons.strokeRoundedInvoice01,
                HugeIcons.strokeRoundedInvoice01,
                "Expenses",
                isDark,
              ),
              _buildNavItem(
                3,
                HugeIcons.strokeRoundedMagicWand01,
                HugeIcons.strokeRoundedMagicWand01,
                "AI",
                isDark,
              ),
              _buildNavItem(
                4,
                HugeIcons.strokeRoundedSettings01,
                HugeIcons.strokeRoundedSettings01,
                "Settings",
                isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    dynamic activeIcon,
    dynamic inactiveIcon,
    String label,
    bool isDark,
  ) {
    final bool isSelected = selectedIndex == index;

    // Dynamic high-contrast colors based on theme
    final activeBgColor = isDark ? Colors.white : const Color(0xFF09090B);
    final activeTextColor = isDark ? Colors.black : Colors.white;
    final inactiveIconColor = isDark ? Colors.white54 : const Color(0xFFA1A1AA);

    return GestureDetector(
      onTap: () => onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: HugeIcon(
                icon: isSelected ? activeIcon : inactiveIcon,
                key: ValueKey<bool>(isSelected),
                color: isSelected ? activeTextColor : inactiveIconColor,
                size: 20,
              ),
            ),
            // Smoothly expands width and fades text to prevent layout jumps
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: isSelected ? null : 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: isSelected ? 1.0 : 0.0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: activeTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
