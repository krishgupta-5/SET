import 'package:flutter/material.dart';

class CustomBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color? color;

  const CustomBackButton({super.key, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = color ?? (isDark ? Colors.white70 : Colors.black54);

    return GestureDetector(
      onTap: onTap ?? () => Navigator.pop(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, color: textSecondary, size: 16),
            const SizedBox(width: 4),
            Text(
              "Back",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
