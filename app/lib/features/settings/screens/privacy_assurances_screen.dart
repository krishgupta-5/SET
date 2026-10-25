import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

class PrivacyAssurancesScreen extends StatelessWidget {
  const PrivacyAssurancesScreen({super.key});

  // Copy unchanged from the previous version of this screen.
  static const _items = [
    (
      HugeIcons.strokeRoundedLockPassword,
      'Zero-knowledge encryption',
      'Your data is encrypted on your device before it reaches our servers. Only you hold the keys.',
    ),
    (
      HugeIcons.strokeRoundedViewOffSlash,
      'No ad tracking',
      'We do not sell, rent, or share your personal data with advertisers or third parties.',
    ),
    (
      HugeIcons.strokeRoundedDatabase,
      'Data residency',
      'All your financial records are stored in enterprise-grade data centers within your region (India).',
    ),
    (
      HugeIcons.strokeRoundedDelete02,
      'Right to erasure',
      'Delete your account and every single byte of your data is permanently wiped from our backups instantly.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Privacy'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.paddingOf(context).bottom + 32,
                  ),
                  children: [
                    RxReveal.index(
                      0,
                      child: Column(
                        children: [
                          const RxEmptyArt(
                            icon: HugeIcons.strokeRoundedShield01,
                            scene: RxArtScene.shield,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Your data belongs to you',
                            textAlign: TextAlign.center,
                            style: RxText.title(context).copyWith(fontSize: 24),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Financial privacy is a basic right. Here is how we handle your information.',
                            textAlign: TextAlign.center,
                            style: RxText.caption(
                              context,
                            ).copyWith(fontSize: 14, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        children: [
                          const RxSectionHeader(title: 'How we protect it'),
                          RxCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < _items.length; i++) ...[
                                  if (i > 0) const RxDivider(indent: 52),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        RxIconTile(
                                          icon: _items[i].$1,
                                          size: 38,
                                          iconSize: 19,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _items[i].$2,
                                                style: RxText.body(context),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                _items[i].$3,
                                                style: RxText.caption(
                                                  context,
                                                ).copyWith(height: 1.45),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    RxReveal.index(
                      2,
                      child: Center(
                        child: RxPill(
                          label: 'SOC2 compliant · ISO 27001 certified',
                          dot: true,
                          foreground: rx.positive,
                          background: rx.positiveSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
