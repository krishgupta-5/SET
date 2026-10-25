import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/telegram_service.dart';
import '../../widgets/rx_pickers.dart';
import '../../widgets/rx_ui.dart';

/// Shared pieces for the member screens: avatar, photo picker, labels.

const Map<String, String> kEmploymentTypes = {
  'full_time': 'Full-time',
  'part_time': 'Part-time',
  'contractor': 'Contractor',
  'intern': 'Intern',
};

String employmentLabel(String? key) =>
    kEmploymentTypes[key] ??
    (key == null || key.isEmpty
        ? 'Full-time'
        : key[0].toUpperCase() + key.substring(1).replaceAll('_', ' '));

/// Telegram file id for a member, including the legacy case where it was
/// stored in `avatarUrl`.
String? memberPhotoId(Map<String, dynamic> m) {
  final tg = m['telegramFileId'] as String?;
  if (tg != null && tg.isNotEmpty) return tg;
  final url = m['avatarUrl'] as String?;
  if (url != null &&
      url.isNotEmpty &&
      !url.startsWith('http') &&
      !url.contains('ui-avatars.com')) {
    return url;
  }
  return null;
}

/// Round member photo with calm, mode-aware initials as the fallback.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.telegramFileId,
    this.avatarUrl,
  });

  final String name;
  final double size;
  final String? telegramFileId;
  final String? avatarUrl;

  factory MemberAvatar.fromData(Map<String, dynamic> m, {double size = 40}) =>
      MemberAvatar(
        name: (m['fullName'] ?? '').toString(),
        size: size,
        telegramFileId: memberPhotoId(m),
        avatarUrl: m['avatarUrl'] as String?,
      );

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Widget _initialsCircle(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: RxCategory.soft(context, name),
    ),
    alignment: Alignment.center,
    child: Text(
      _initials,
      style: TextStyle(
        fontFamily: RxText.family,
        fontSize: size * 0.36,
        fontWeight: FontWeight.w600,
        height: 1,
        color: RxCategory.color(context, name),
      ),
    ),
  );

  Widget _photo(BuildContext context, String url) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      // Pure black/white 10% outline so the photo edge never tints.
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, _, _) => _initialsCircle(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tg = telegramFileId;
    if (tg != null && tg.isNotEmpty) {
      return FutureBuilder<String>(
        future: TelegramService.getImageUrl(tg),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return RxSkeleton(width: size, height: size, radius: 100);
          }
          if (!snap.hasData) return _initialsCircle(context);
          return _photo(context, snap.data!);
        },
      );
    }
    final url = avatarUrl;
    if (url != null &&
        url.startsWith('http') &&
        !url.contains('ui-avatars.com')) {
      return _photo(context, url);
    }
    return _initialsCircle(context);
  }
}

/// Large tappable avatar with a camera badge, for add/edit member.
class MemberPhotoPicker extends StatelessWidget {
  const MemberPhotoPicker({
    super.key,
    required this.name,
    required this.telegramFileId,
    required this.busy,
    required this.onTap,
    this.avatarUrl,
  });

  final String name;
  final String? telegramFileId;
  final String? avatarUrl;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final hasPhoto = (telegramFileId ?? '').isNotEmpty;
    return Column(
      children: [
        RxPressable(
          onTap: busy ? null : onTap,
          semanticLabel: hasPhoto ? 'Change photo' : 'Add photo',
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (hasPhoto || name.trim().isNotEmpty)
                  MemberAvatar(
                    name: name.trim().isEmpty ? '?' : name,
                    size: 96,
                    telegramFileId: telegramFileId,
                    avatarUrl: avatarUrl,
                  )
                else
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: rx.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: rx.hairline),
                      boxShadow: rx.cardShadow,
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedUser,
                      color: rx.textTertiary,
                      size: 36,
                      strokeWidth: 1.5,
                    ),
                  ),
                if (busy)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: rx.barrier,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: rx.inverse,
                      shape: BoxShape.circle,
                      border: Border.all(color: rx.background, width: 3),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCamera01,
                      color: rx.onInverse,
                      size: 14,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasPhoto ? 'Change photo' : 'Add photo',
          style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Camera / gallery sheet, square crop, upload to Telegram.
/// Returns the new file id, or null if cancelled or failed ([onError] runs
/// on failure).
Future<String?> pickMemberPhoto(
  BuildContext context, {
  required VoidCallback onStart,
  required void Function(String message) onError,
}) async {
  FocusScope.of(context).unfocus();
  ImageSource? source;
  await showRxActionSheet(
    context,
    title: 'Photo',
    actions: [
      RxSheetAction(
        icon: HugeIcons.strokeRoundedCamera01,
        label: 'Take photo',
        onTap: () => source = ImageSource.camera,
      ),
      RxSheetAction(
        icon: HugeIcons.strokeRoundedImage01,
        label: 'Choose from gallery',
        onTap: () => source = ImageSource.gallery,
      ),
    ],
  );
  if (source == null || !context.mounted) return null;

  try {
    final image = await ImagePicker().pickImage(
      source: source!,
      imageQuality: 90,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (image == null || !context.mounted) return null;

    final rx = context.rx;
    File file = File(image.path);
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 80,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: rx.surface,
            toolbarWidgetColor: rx.textPrimary,
            backgroundColor: rx.background,
            activeControlsWidgetColor: rx.inverse,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop photo',
            aspectRatioLockEnabled: true,
            minimumAspectRatio: 1.0,
          ),
        ],
      );
      if (cropped == null) return null;
      file = File(cropped.path);
    } catch (e) {
      debugPrint('Error cropping image: $e');
    }

    onStart();
    final fileId = await TelegramService.uploadPhoto(file.path);
    if (fileId == null) {
      onError('Failed to upload photo');
      return null;
    }
    return fileId;
  } catch (e) {
    debugPrint('Error picking image: $e');
    onError('Failed to pick image');
    return null;
  }
}
