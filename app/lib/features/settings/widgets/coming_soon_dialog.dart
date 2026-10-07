import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ComingSoonDialog extends StatelessWidget {
  const ComingSoonDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final btnBg = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return Dialog(
      backgroundColor: context.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.upcoming, color: Colors.blue, size: 30),
            ),
            const SizedBox(height: 20),
            Text(
              "Coming Soon!",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "This feature is currently under development and will be available in a future update.",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnBg,
                  foregroundColor: context.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Got it",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
