import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/telegram_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  final uid = FirebaseAuth.instance.currentUser!.uid;
  final String email = FirebaseAuth.instance.currentUser!.email!;

  bool _isLoading = false;

  // Profile image variables
  String? _profileImageFileId;


  // Country Code State
  String _selectedCountryCode = "+1";
  String _selectedFlag = "🇺🇸";

  final List<Map<String, String>> _countryCodes = [
    {"code": "+1", "flag": "🇺🇸", "name": "United States"},
    {"code": "+91", "flag": "🇮🇳", "name": "India"},
    {"code": "+44", "flag": "🇬🇧", "name": "United Kingdom"},
    {"code": "+61", "flag": "🇦🇺", "name": "Australia"},
    {"code": "+81", "flag": "🇯🇵", "name": "Japan"},
    {"code": "+49", "flag": "🇩🇪", "name": "Germany"},
    {"code": "+33", "flag": "🇫🇷", "name": "France"},
    {"code": "+971", "flag": "🇦🇪", "name": "United Arab Emirates"},
    {"code": "+65", "flag": "🇸🇬", "name": "Singapore"},
  ];

  @override
  void initState() {
    super.initState();
    loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // --- UNIFIED MINIMAL TOAST ---
  void _showMinimalToast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

  Future<void> loadUserProfile() async {
    try {
      final companySnapshot = await FirebaseFirestore.instance
          .collection("companies")
          .doc(uid)
          .get();

      final userSnapshot = await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .get();

      if (!mounted) return;
      setState(() {
        _nameController.text = '';
        _phoneController.text = '';
        _locationController.text = '';
        _emailController.text = email;

        if (companySnapshot.exists) {
          final companyData = companySnapshot.data()!;
          _nameController.text = companyData["Owner Name"] ?? '';

          String fullMobileNumber = companyData["Mobile Number"] ?? '';
          if (fullMobileNumber.isNotEmpty) {
            int spaceIndex = fullMobileNumber.indexOf(' ');
            if (spaceIndex != -1) {
              String countryCode = fullMobileNumber.substring(0, spaceIndex);
              String phoneNumber = fullMobileNumber
                  .substring(spaceIndex + 1)
                  .trim();

              for (var country in _countryCodes) {
                if (country["code"] == countryCode) {
                  _selectedCountryCode = countryCode;
                  _selectedFlag = country["flag"]!;
                  break;
                }
              }
              _phoneController.text = phoneNumber;
            } else {
              _phoneController.text = fullMobileNumber;
            }
          }

          _locationController.text = companyData["Country Location"] ?? '';
        }

        if (userSnapshot.exists && _nameController.text.isEmpty) {
          final userData = userSnapshot.data()!;
          _nameController.text = userData['name'] ?? '';
          _phoneController.text = userData['phone'] ?? '';
          _locationController.text = userData['location'] ?? '';
        }

        if (userSnapshot.exists) {
          final userData = userSnapshot.data()!;
          _profileImageFileId = userData['profileImageFileId'];
          _emailController.text = userData['email'] ?? email;
        }
      });
    } catch (e) {
      log('Profile data fetch error: $e');
    }
  }

  Future<String> getTelegramImageUrl(String fileId) =>
      TelegramService.getImageUrl(fileId);

  Future<void> _handleSave() async {
    FocusScope.of(context).unfocus();

    if (_nameController.text.trim().isEmpty) {
      _showMinimalToast("Name cannot be empty", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(
        _nameController.text.trim(),
      );

      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "name": _nameController.text.trim(),
        "phone": _phoneController.text.trim(),
        "location": _locationController.text.trim(),
        "profileImageFileId": _profileImageFileId,
        "uid": uid,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final String fullMobileNumber =
          "$_selectedCountryCode ${_phoneController.text.trim()}";
      await FirebaseFirestore.instance.collection("companies").doc(uid).set({
        "Owner Name": _nameController.text.trim(),
        "Mobile Number": fullMobileNumber,
        "Country Location": _locationController.text.trim(),
        "profileImageFileId": _profileImageFileId,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        _showMinimalToast("Profile updated successfully!");
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showMinimalToast(
          "Error updating profile: ${e.toString()}",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image == null) return;

      setState(() => _isLoading = true);

      final fileId = await _uploadToTelegram(image.path);

      if (fileId != null) {
        setState(() {
          _profileImageFileId = fileId;
        });
        _showMinimalToast("Profile photo updated successfully!");
      } else {
        _showMinimalToast("Failed to upload photo", isError: true);
      }
    } catch (e) {
      _showMinimalToast("Error uploading photo: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _uploadToTelegram(String filePath) async {
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final uri = Uri.parse("https://api.telegram.org/bot$botToken/sendPhoto");

      var request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = '-1003885930746';

      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      final response = await request.send();

      if (response.statusCode == 200) {
        final res = await http.Response.fromStream(response);
        final data = jsonDecode(res.body);

        return data['result']['photo'].last['file_id'];
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Error uploading to Telegram: $e');
      return null;
    }
  }

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
              const RxTopBar(title: 'Edit profile'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    RxReveal.index(0, child: Center(child: _buildAvatar())),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Personal details'),
                          RxTextInput(
                            controller: _nameController,
                            label: 'Full name',
                            hint: 'Your name',
                            icon: HugeIcons.strokeRoundedUser,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _emailController,
                            label: 'Email',
                            icon: HugeIcons.strokeRoundedMail01,
                            enabled: false,
                            helper: 'Your sign-in email can\'t be changed here',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Contact'),
                          RxTextInput(
                            controller: _phoneController,
                            label: 'Phone',
                            hint: 'Mobile number',
                            keyboardType: TextInputType.phone,
                            suffix: null,
                            prefixText: null,
                            icon: null,
                            textCapitalization: TextCapitalization.none,
                          ).withCountryCode(
                            context,
                            flag: _selectedFlag,
                            code: _selectedCountryCode,
                            onTap: _showCountryCodePicker,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _locationController,
                            label: 'Location',
                            hint: 'City, country',
                            icon: HugeIcons.strokeRoundedLocation01,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Save changes',
                  loading: _isLoading,
                  onTap: _handleSave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const size = 96.0;

    Widget placeholder() => Container(
      width: size,
      height: size,
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
    );

    Widget photo() {
      final id = _profileImageFileId;
      if (id == null || id.isEmpty) return placeholder();
      return FutureBuilder<String>(
        future: getTelegramImageUrl(id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const RxSkeleton(width: size, height: size, radius: 100);
          }
          if (!snap.hasData) return placeholder();
          return Container(
            width: size,
            height: size,
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
                snap.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder(),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        RxPressable(
          onTap: _isLoading ? null : _showImagePicker,
          semanticLabel: 'Change photo',
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                photo(),
                if (_isLoading)
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
          'Change photo',
          style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _showImagePicker() {
    FocusScope.of(context).unfocus();
    showRxActionSheet(
      context,
      title: 'Profile photo',
      actions: [
        RxSheetAction(
          icon: HugeIcons.strokeRoundedCamera01,
          label: 'Take photo',
          onTap: () => _pickImage(ImageSource.camera),
        ),
        RxSheetAction(
          icon: HugeIcons.strokeRoundedImage01,
          label: 'Choose from gallery',
          onTap: () => _pickImage(ImageSource.gallery),
        ),
        if (_profileImageFileId != null && _profileImageFileId!.isNotEmpty)
          RxSheetAction(
            icon: HugeIcons.strokeRoundedDelete02,
            label: 'Remove photo',
            subtitle: 'Saved when you tap Save changes',
            destructive: true,
            onTap: () => setState(() => _profileImageFileId = null),
          ),
      ],
    );
  }

  void _showCountryCodePicker() async {
    final picked = await showRxSelectSheet<String>(
      context,
      title: 'Country code',
      selected: _selectedCountryCode,
      options: [
        for (final c in _countryCodes)
          RxOption(
            c['code']!,
            '${c['flag']}  ${c['name']}',
            subtitle: c['code'],
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final c = _countryCodes.firstWhere((e) => e['code'] == picked);
    setState(() {
      _selectedCountryCode = picked;
      _selectedFlag = c['flag']!;
    });
  }
}

/// Phone field: a tappable country code chip in front of [RxTextInput].
extension on RxTextInput {
  Widget withCountryCode(
    BuildContext context, {
    required String flag,
    required String code,
    required VoidCallback onTap,
  }) {
    final rx = context.rx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label ?? '',
            style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Row(
          children: [
            RxPressable(
              onTap: onTap,
              semanticLabel: 'Country code $code',
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: rx.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: rx.textPrimary.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    Text(flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(code, style: RxText.body(context)),
                    const SizedBox(width: 2),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowDown01,
                      color: rx.textSecondary,
                      size: 16,
                      strokeWidth: 1.9,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RxTextInput(
                controller: controller,
                hint: hint,
                keyboardType: keyboardType,
                textCapitalization: TextCapitalization.none,
                icon: HugeIcons.strokeRoundedCall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
