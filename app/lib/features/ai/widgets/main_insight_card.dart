import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import 'ai_widgets.dart';

/// The headline briefing. The primary insight writes itself in word by
/// word; the supporting text fades up once it finishes.
class MainInsightCard extends StatefulWidget {
  final Map<String, dynamic>? mainData;

  const MainInsightCard({super.key, required this.mainData});

  @override
  State<MainInsightCard> createState() => _MainInsightCardState();
}

class _MainInsightCardState extends State<MainInsightCard> {
  bool _typed = false;

  @override
  void didUpdateWidget(covariant MainInsightCard old) {
    super.didUpdateWidget(old);
    if (old.mainData?['primary_insight'] !=
        widget.mainData?['primary_insight']) {
      _typed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final data = widget.mainData;

    if (data == null) return const SizedBox.shrink();

    if (data.containsKey('error')) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedAlert02,
          title: "Couldn't prepare your briefing",
          message: 'Pull down to try again in a moment',
        ),
      );
    }

    final primary = (data['primary_insight'] ?? 'No insight available.')
        .toString();
    final description = (data['description'] ?? '').toString();
    final impact = (data['high_impact_summary'] ?? '').toString().trim();

    // Gradient hairline around the card marks it as the main read.
    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            rx.accent.withValues(alpha: dark ? 0.7 : 0.9),
            const Color(0xFF4FD1C5).withValues(alpha: dark ? 0.35 : 0.5),
            rx.hairline,
          ],
        ),
        boxShadow: rx.cardShadow,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: rx.surface,
          borderRadius: BorderRadius.circular(22.8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                rx.accent.withValues(alpha: dark ? 0.08 : 0.10),
                rx.surface,
              ),
              rx.surface,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AiChip(label: 'TODAY\'S BRIEFING'),
                const Spacer(),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedQuoteDown,
                  color: rx.textTertiary,
                  size: 20,
                  strokeWidth: 1.6,
                ),
              ],
            ),
            const SizedBox(height: 14),
            AiTypewriter(
              key: ValueKey(primary),
              text: primary,
              delay: const Duration(milliseconds: 250),
              style: RxText.heading(context).copyWith(
                fontSize: 19,
                height: 1.4,
                letterSpacing: -0.2,
                color: rx.textPrimary,
              ),
              onDone: () {
                if (mounted && !_typed) setState(() => _typed = true);
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_typed
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          RxReveal(
                            offset: 6,
                            child: Text(
                              description,
                              style:
                                  RxText.body(
                                    context,
                                    color: rx.textSecondary,
                                  ).copyWith(
                                    fontWeight: FontWeight.w400,
                                    height: 1.5,
                                  ),
                            ),
                          ),
                        ],
                        if (impact.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          RxReveal(
                            delay: const Duration(milliseconds: 120),
                            offset: 6,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                              decoration: BoxDecoration(
                                color: rx.warningSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedFlash,
                                    color: rx.warning,
                                    size: 16,
                                    strokeWidth: 2,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      impact,
                                      style: RxText.caption(
                                        context,
                                        color: rx.warning,
                                      ).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
