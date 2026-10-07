import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import '../../../theme/app_theme.dart';

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

  // Cache for Telegram photos to avoid repeated fetching
  static final Map<String, String> _telegramPhotoCache = {};

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
  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF30D158),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

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

  Future<String> getTelegramImageUrl(String fileId) async {
    if (_telegramPhotoCache.containsKey(fileId)) {
      return _telegramPhotoCache[fileId]!;
    }

    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final res = await http.get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/getFile?file_id=$fileId",
        ),
      );

      final data = jsonDecode(res.body);
      final path = data['result']['file_path'];

      final imageUrl = "https://api.telegram.org/file/bot$botToken/$path";

      _telegramPhotoCache[fileId] = imageUrl;

      return imageUrl;
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          "Edit Profile",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Center(child: _buildAvatarUploader()),
                        const SizedBox(height: 40),

                        _buildSectionLabel("PERSONAL DETAILS"),
                        const SizedBox(height: 16),
                        _buildInputGroup(
                          "Full Name",
                          _nameController,
                          Icons.person_outline,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        _buildInputGroup(
                          "Email Address",
                          _emailController,
                          Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          readOnly: true,
                        ),

                        const SizedBox(height: 32),

                        _buildSectionLabel("CONTACT INFO"),
                        const SizedBox(height: 16),
                        _buildPhoneInputGroup(),
                        const SizedBox(height: 16),
                        _buildInputGroup(
                          "Location",
                          _locationController,
                          Icons.location_on_outlined,
                          textInputAction: TextInputAction.done,
                        ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back,
                    color: context.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Back",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: context.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildAvatarUploader() {
    final badgeBg = context.isDarkMode ? Colors.white : Colors.black;
    final badgeIcon = context.isDarkMode ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: _showImagePicker,
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: context.cardBackground,
              shape: BoxShape.circle,
              border: Border.all(color: context.borderColor, width: 1),
              boxShadow: context.cardShadow,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildProfileAvatarForUploader(),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      shape: BoxShape.circle,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: badgeIcon,
                            ),
                          )
                        : Icon(Icons.camera_alt, color: badgeIcon, size: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Update Photo",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatarForUploader() {
    if (_profileImageFileId != null && _profileImageFileId!.isNotEmpty) {
      return FutureBuilder<String>(
        future: getTelegramImageUrl(_profileImageFileId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SizedBox(
              width: 100 * 0.3,
              height: 100 * 0.3,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.iconSecondary,
              ),
            );
          } else if (snapshot.hasError || !snapshot.hasData) {
            return _buildDefaultAvatarForUploader();
          } else {
            return ClipOval(
              child: Image.network(
                snapshot.data!,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultAvatarForUploader();
                },
              ),
            );
          }
        },
      );
    }

    return _buildDefaultAvatarForUploader();
  }

  Widget _buildDefaultAvatarForUploader() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.cardBackground,
        boxShadow: context.cardShadow,
      ),
      child: Icon(Icons.person, size: 40, color: context.iconSecondary),
    );
  }

  void _showImagePicker() async {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _buildImagePickerSheet(),
    );
  }

  Widget _buildImagePickerSheet() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Profile Photo",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.glassBackgroundStrong,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Icon(
                      Icons.close,
                      color: context.iconSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImagePickerOption(
                  Icons.camera_alt,
                  "Camera",
                  () => _pickImage(ImageSource.camera),
                ),
                _buildImagePickerOption(
                  Icons.photo_library,
                  "Gallery",
                  () => _pickImage(ImageSource.gallery),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerOption(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    final effectiveColor = color ?? context.textPrimary;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: effectiveColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: effectiveColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: effectiveColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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
      setState(() => _isLoading = false);
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

  Widget _buildInputGroup(
    String hint,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.done,
    bool readOnly = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        readOnly: readOnly,
        canRequestFocus: !readOnly,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: readOnly ? context.textTertiary : context.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: context.textPrimary,
        decoration: InputDecoration(
          icon: Icon(icon, color: context.iconSecondary, size: 20),
          labelText: hint,
          labelStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 13,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildPhoneInputGroup() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              _showCountryCodePicker();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.transparent,
              child: Row(
                children: [
                  Text(
                    "$_selectedFlag $_selectedCountryCode",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: context.iconSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 24,
            width: 1,
            color: context.borderColor,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onTapOutside: (event) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: context.textPrimary,
              decoration: InputDecoration(
                labelText: "Phone Number",
                labelStyle: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCountryCodePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: context.borderColor),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Country Code",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.close,
                          color: context.iconSecondary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(color: context.borderColor, height: 1),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _countryCodes.length,
                    itemBuilder: (context, index) {
                      final country = _countryCodes[index];
                      final isSelected =
                          _selectedCountryCode == country["code"];

                      return ListTile(
                        onTap: () {
                          setState(() {
                            _selectedCountryCode = country["code"]!;
                            _selectedFlag = country["flag"]!;
                          });
                          Navigator.pop(context);
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        leading: Text(
                          country["flag"]!,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          country["name"]!,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: isSelected
                                ? context.textPrimary
                                : context.textSecondary,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: Text(
                          country["code"]!,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: isSelected
                                ? context.textPrimary
                                : context.textTertiary,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveButton() {
    final btnBg = context.isDarkMode ? Colors.white : Colors.black;
    final btnText = context.isDarkMode ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appBackground,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: btnBg,
            foregroundColor: btnText,
            disabledBackgroundColor: context.textTertiary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: btnText,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  "Save Changes",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
