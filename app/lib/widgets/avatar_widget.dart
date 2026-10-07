import 'package:flutter/material.dart';

class AvatarWidget extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;
  final Color? backgroundColor;
  final Color? textColor;
  final double fontSize;
  final FontWeight fontWeight;

  const AvatarWidget({
    super.key,
    required this.name,
    this.size = 48.0,
    this.imageUrl,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 16.0,
    this.fontWeight = FontWeight.w600,
  });

  // Generate consistent color based on name
  Color _generateColorFromName(String name) {
    if (backgroundColor != null) return backgroundColor!;

    final int hash = name.hashCode;
    final List<Color> colors = [
      const Color(0xFF0A84FF), // Blue
      const Color(0xFF30D158), // Green
      const Color(0xFFFF9F0A), // Orange
      const Color(0xFFA259FF), // Purple
      const Color(0xFFFF453A), // Red
      const Color(0xFF5AC8FA), // Light Blue
      const Color(0xFFFFCC00), // Yellow
      const Color(0xFFAF52DE), // Violet
    ];

    return colors[hash.abs() % colors.length];
  }

  // Get first letter(s) for avatar
  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else {
      return name[0].toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(name);
    final avatarColor = _generateColorFromName(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor,
        image: imageUrl != null && imageUrl!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {
                  // Fallback to initials if image fails to load
                },
              )
            : null,
      ),
      child: imageUrl == null || imageUrl!.isEmpty
          ? Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  initials,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textColor ?? Colors.white,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    height: 1.0,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
