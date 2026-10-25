import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_ui.dart';

/// "Coming soon" dialog. Pass a [scene] that matches the feature (e.g. a
/// lock for access control, stars for rating); the default is a rocket.
class ComingSoonDialog extends StatelessWidget {
  const ComingSoonDialog({
    super.key,
    this.scene = RxArtScene.rocket,
    this.title = 'Coming soon',
    this.message =
        "We're still building this. It'll arrive in a future update.",
  });

  final RxArtScene scene;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Dialog(
      backgroundColor: rx.sheet,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RxEmptyArt(
              icon: HugeIcons.strokeRoundedRocket01,
              scene: scene,
              scale: 0.85,
            ),
            const SizedBox(height: 12),
            Text(title, style: RxText.heading(context).copyWith(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: RxText.caption(
                context,
              ).copyWith(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            RxButton(
              label: 'Got it',
              height: 46,
              style: RxButtonStyle.secondary,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
