import 'package:flutter/material.dart';

import '../../widgets/rx_ui.dart';

/// One place for how a team looks: its colour and icon, shared by every
/// team screen so the tab, detail and forms always agree.
class TeamStyle {
  TeamStyle._();

  /// Stored colour names (unchanged in Firestore) -> palette slot.
  static const colorNames = ['Blue', 'Orange', 'Purple', 'Green', 'Red'];

  static Color color(BuildContext context, String? name) {
    final key = switch ((name ?? 'blue').toLowerCase()) {
      'orange' => 'meals',
      'purple' => 'software',
      'green' => 'office',
      'red' => 'marketing',
      _ => 'servers', // blue
    };
    return RxCategory.color(context, key);
  }

  static Color soft(BuildContext context, String? name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return color(context, name).withValues(alpha: isDark ? 0.16 : 0.10);
  }

  /// Icons offered when creating or editing a team. Their code points are
  /// what gets stored, so keep the order and members stable.
  static const icons = <IconData>[
    Icons.rocket_launch_rounded,
    Icons.code_rounded,
    Icons.palette_rounded,
    Icons.insights_rounded,
    Icons.campaign_rounded,
    Icons.support_agent_rounded,
  ];

  /// Icon for a stored team, matching the saved code point when possible.
  static IconData icon(Map<String, dynamic> data) {
    final dynamic cp = data['iconCodePoint'];
    final int? codePoint = cp is int ? cp : int.tryParse('${cp ?? ''}');
    if (codePoint == null) return icons.first;
    for (final i in icons) {
      if (i.codePoint == codePoint) return i;
    }
    // Older teams saved a few other Material icons.
    switch (codePoint) {
      case 0xe3af:
        return Icons.work_outline_rounded;
      case 0xe0af:
        return Icons.business_rounded;
      case 0xe7fd:
        return Icons.group_outlined;
      case 0xe226:
        return Icons.code_rounded;
      case 0xe86c:
        return Icons.design_services_outlined;
      case 0xe85d:
        return Icons.computer_rounded;
      case 0xe53b:
        return Icons.build_outlined;
      case 0xe251:
        return Icons.lightbulb_outline_rounded;
      case 0xe7f1:
        return Icons.trending_up_rounded;
      case 0xe8b6:
        return Icons.people_outline_rounded;
      default:
        return icons.first;
    }
  }
}

/// Rounded tile with the team's icon on its soft colour.
class TeamIconTile extends StatelessWidget {
  const TeamIconTile({
    super.key,
    required this.icon,
    required this.colorName,
    this.size = 44,
  });

  final IconData icon;
  final String? colorName;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: TeamStyle.soft(context, colorName),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: TeamStyle.color(context, colorName),
        size: size * 0.48,
      ),
    );
  }
}

/// Colour + icon picker used by Create Team and Edit Team.
class TeamIdentityPicker extends StatelessWidget {
  const TeamIdentityPicker({
    super.key,
    required this.colorName,
    required this.icon,
    required this.onColor,
    required this.onIcon,
  });

  final String colorName;
  final IconData icon;
  final ValueChanged<String> onColor;
  final ValueChanged<IconData> onIcon;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final active = TeamStyle.color(context, colorName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Colour', style: RxText.label(context)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final name in TeamStyle.colorNames)
              Semantics(
                button: true,
                selected: name == colorName,
                label: name,
                child: GestureDetector(
                  onTap: () => onColor(name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TeamStyle.soft(context, name),
                      border: Border.all(
                        color: name == colorName
                            ? TeamStyle.color(context, name)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: TeamStyle.color(context, name),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Icon', style: RxText.label(context)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final i in TeamStyle.icons)
              Semantics(
                button: true,
                selected: i == icon,
                child: GestureDetector(
                  onTap: () => onIcon(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: i == icon
                          ? TeamStyle.soft(context, colorName)
                          : rx.surfaceMuted,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: i == icon ? active : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      i,
                      size: 20,
                      color: i == icon ? active : rx.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
