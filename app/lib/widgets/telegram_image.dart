import 'package:flutter/material.dart';

import '../services/telegram_service.dart';

/// Shows a stored image through the authenticated backend proxy.
/// Use instead of `Image.network(telegramUrl)`, which needed the bot token.
class TelegramImage extends StatelessWidget {
  const TelegramImage(
    this.fileId, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  final String fileId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: TelegramService.downloadBytes(fileId),
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => error ?? _box(Icons.broken_image),
          );
        }
        if (snap.hasError) return error ?? _box(Icons.broken_image);
        return placeholder ??
            SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
      },
    );
  }

  Widget _box(IconData icon) => SizedBox(
    width: width,
    height: height,
    child: Center(child: Icon(icon, color: Colors.grey)),
  );
}
