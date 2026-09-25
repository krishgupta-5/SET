import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import '../../../widgets/avatar_widget.dart';
import '../../../theme/app_theme.dart';

class EditMemberScreen extends StatefulWidget {
  final String memberId;
  final Map<String, dynamic> memberData;

  const EditMemberScreen({
    super.key,
    required this.memberId,
    required this.memberData,
  });

  @override
  State<EditMemberScreen> createState() => _EditMemberScreenState();
}

class _EditMemberScreenState extends State<EditMemberScreen> {
  late TextEditingController _nameController;
  late TextEditingController _roleController;
  late TextEditingController _emailController;

  bool _isLoading = false;
  bool _isLoadingTeams = true;

  Map<String, String> _teams = {};
  String? _selectedTeamId;

  // Telegram photo variables
  String? _telegramFileId;

  // Cache for Telegram photos to avoid repeated fetching
  static final Map<String, String> _telegramPhotoCache = {};

  final Map<String, String> _statuses = {
    'Active': 'Active',
    'Paused': 'Paused',
    'Inactive': 'Inactive',
  };

  late String _status;
  late DateTime _joiningDate;

  @override
  void initState() {
    super.initState();

    // Pre-fill with existing member data
    _nameController = TextEditingController(
      text: widget.memberData['fullName'] ?? "",
    );
    _roleController = TextEditingController(
      text: widget.memberData['jobTitle'] ?? "",
    );
    _emailController = TextEditingController(
      text: widget.memberData['email'] ?? "",
    );

    _status = widget.memberData['status'] ?? "Active";
    _selectedTeamId = widget.memberData['teamId'];

    // Initialize Telegram file ID from member data
    _telegramFileId =
        widget.memberData['telegramFileId'] ?? widget.memberData['avatarUrl'];

    if (widget.memberData['joiningDate'] != null &&
        widget.memberData['joiningDate'] is Timestamp) {
      _joiningDate = (widget.memberData['joiningDate'] as Timestamp).toDate();
    } else {
      _joiningDate = DateTime.now();
    }

    _fetchTeams();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _fetchTeams() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('teams')
          .where('uid', isEqualTo: uid)
          .get();

      final Map<String, String> fetchedTeams = {};
      for (var doc in snapshot.docs) {
        fetchedTeams[doc.id] = doc.data()['teamName'] ?? 'Unnamed Team';
      }

      if (mounted) {
        setState(() {
          _teams = fetchedTeams;

          // If the team this member belonged to was deleted, reset to first available
          if (_selectedTeamId != null && !_teams.containsKey(_selectedTeamId)) {
            _selectedTeamId = _teams.isNotEmpty ? _teams.keys.first : null;
          }

          _isLoadingTeams = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching teams: $e");
      if (mounted) setState(() => _isLoadingTeams = false);
    }
  }

  Future<void> _updateMember() async {
    if (_nameController.text.trim().isEmpty) {
      _showErrorSnackBar("Name cannot be empty");
      return;
    }

    if (_nameController.text.trim().length < 2) {
      _showErrorSnackBar("Name must be at least 2 characters long.");
      return;
    }

    if (_nameController.text.trim().length > 50) {
      _showErrorSnackBar("Name must not exceed 50 characters.");
      return;
    }

    if (_emailController.text.trim().isNotEmpty) {
      final emailRegex = RegExp(
        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      );
      if (!emailRegex.hasMatch(_emailController.text.trim())) {
        _showErrorSnackBar("Please enter a valid email address.");
        return;
      }
    }

    if (_roleController.text.trim().length > 100) {
      _showErrorSnackBar("Job title must not exceed 100 characters.");
      return;
    }

    if (_joiningDate.isAfter(DateTime.now())) {
      _showErrorSnackBar("Joining date cannot be in the future.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> updateData = {
        "fullName": _nameController.text.trim(),
        "jobTitle": _roleController.text.trim(),
        "email": _emailController.text.trim(),
        "teamId": _selectedTeamId,
        "status": _status,
        "joiningDate": _joiningDate,
      };

      // Update Telegram file ID if image was changed
      if (_telegramFileId != null &&
          _telegramFileId != widget.memberData['telegramFileId']) {
        updateData["avatarUrl"] = _telegramFileId;
        updateData["telegramFileId"] = _telegramFileId;
      }

      await FirebaseFirestore.instance
          .collection('members')
          .doc(widget.memberId)
          .update(updateData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Profile updated successfully",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFF30D158),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showErrorSnackBar(e.message ?? 'Failed to update profile');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFFFF453A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // --- TELEGRAM IMAGE UPLOAD METHODS ---
  Future<String?> uploadToTelegram(String filePath) async {
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

        // Take highest quality image
        return data['result']['photo'].last['file_id'];
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Error uploading to Telegram: $e');
      return null;
    }
  }

  Future<String> getTelegramImageUrl(String fileId) async {
    // Check cache first
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

      // Cache the result
      _telegramPhotoCache[fileId] = imageUrl;

      return imageUrl;
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
    }
  }

  Future<void> _showImagePicker() async {
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Update Photo",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerOption(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
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
              color: context.appBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Icon(icon, color: context.textPrimary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image != null) {
        final File? croppedFile = await _cropImage(File(image.path));
        if (croppedFile != null) {
          await _uploadImageToTelegram(croppedFile);
        }
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      _showErrorSnackBar("Failed to pick image");
    }
  }

  Future<File?> _cropImage(File sourceFile) async {
    try {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: sourceFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 80,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: context.cardBackground,
            toolbarWidgetColor: context.textPrimary,
            backgroundColor: context.appBackground,
            activeControlsWidgetColor: context.primaryColor,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: true,
            minimumAspectRatio: 1.0,
          ),
        ],
      );
      return croppedFile != null ? File(croppedFile.path) : null;
    } catch (e) {
      debugPrint("Error cropping image: $e");
      return sourceFile;
    }
  }

  Future<void> _uploadImageToTelegram(File imageFile) async {
    try {
      setState(() => _isLoading = true);

      final fileId = await uploadToTelegram(imageFile.path);

      if (fileId == null) {
        throw Exception('Failed to upload image to Telegram');
      }

      if (mounted) {
        setState(() {
          _telegramFileId = fileId;
          _isLoading = false;
        });
        debugPrint("Image uploaded to Telegram successfully: $fileId");
      }
    } catch (e) {
      debugPrint("Error uploading image to Telegram: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Failed to upload image to Telegram");
      }
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    // Check for Telegram photo first, then regular avatar
    final String? avatarUrl = widget.memberData['avatarUrl'];

    final String? telegramFileIdFromAvatar =
        (avatarUrl != null &&
            avatarUrl.isNotEmpty &&
            !avatarUrl.startsWith('http') &&
            !avatarUrl.contains('ui-avatars.com'))
        ? avatarUrl
        : null;

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
              // 1. Premium Header
              _buildHeader(context),

              // 2. Scrollable Content
              Expanded(
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
                          fontSize: 28, // Compact Hero
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Avatar Edit
                      Center(
                        child: _buildAvatarUploader(
                          _nameController.text,
                          _telegramFileId ?? telegramFileIdFromAvatar,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Personal Details
                      _buildSectionLabel("PERSONAL DETAILS"),
                      const SizedBox(height: 16),
                      _buildTextInput(
                        "Full Name",
                        "e.g. Sarah Miller",
                        Icons.person_outline,
                        _nameController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _buildTextInput(
                        "Email Address",
                        "sarah@company.com",
                        Icons.email_outlined,
                        _emailController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _buildTextInput(
                        "Job Title",
                        "e.g. Senior Product Designer",
                        Icons.badge_outlined,
                        _roleController,
                        textInputAction: TextInputAction.done,
                      ),

                      const SizedBox(height: 32),

                      // Joining Date
                      _buildSectionLabel("JOINING DATE"),
                      const SizedBox(height: 16),
                      _buildDateSelector(),

                      const SizedBox(height: 32),

                      // Team & Status Selectors
                      _buildSectionLabel("ASSIGNMENT & STATUS"),
                      const SizedBox(height: 16),

                      _isLoadingTeams
                          ? Container(
                              height: 56,
                              decoration: BoxDecoration(
                                color: context.cardBackground,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: context.borderColor),
                                boxShadow: context.cardShadow,
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.textSecondary,
                                ),
                              ),
                            )
                          : _teams.isEmpty
                          ? Text(
                              "No teams found.",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: Colors.redAccent,
                              ),
                            )
                          : _buildSelectField(
                              label: "Team",
                              currentValue: _selectedTeamId,
                              items: _teams,
                              onChanged: (val) {
                                FocusScope.of(context).unfocus();
                                setState(() => _selectedTeamId = val);
                              },
                            ),

                      const SizedBox(height: 16),

                      _buildSelectField(
                        label: "Status",
                        currentValue: _status,
                        items: _statuses,
                        onChanged: (val) {
                          FocusScope.of(context).unfocus();
                          setState(() => _status = val!);
                        },
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              // 3. Bottom Save Button
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

  Widget _buildAvatarUploader(String name, String? telegramId) {
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
                _buildMemberAvatar(name, 100, telegramId),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.appBackground,
                            ),
                          )
                        : Icon(
                            Icons.camera_alt,
                            color: context.appBackground,
                            size: 16,
                          ),
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

  Widget _buildMemberAvatar(String name, double size, String? telegramFileId) {
    if (telegramFileId != null && telegramFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: getTelegramImageUrl(telegramFileId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SizedBox(
              width: size * 0.3,
              height: size * 0.3,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.textSecondary,
              ),
            );
          } else if (snapshot.hasError || !snapshot.hasData) {
            return AvatarWidget(
              name: name,
              size: size,
              imageUrl: null,
              fontSize: size * 0.4,
            );
          } else {
            return ClipOval(
              child: Image.network(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return AvatarWidget(
                    name: name,
                    size: size,
                    imageUrl: null,
                    fontSize: size * 0.4,
                  );
                },
              ),
            );
          }
        },
      );
    } else {
      return AvatarWidget(
        name: name.isNotEmpty ? name : "Member",
        size: size,
        imageUrl: null,
        fontSize: size * 0.4,
      );
    }
  }

  Widget _buildTextInput(
    String hint,
    String placeholder,
    IconData icon,
    TextEditingController controller, {
    TextInputAction textInputAction = TextInputAction.done,
    TextInputType keyboardType = TextInputType.text,
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
        textInputAction: textInputAction,
        keyboardType: keyboardType,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          icon: Icon(icon, color: context.textSecondary, size: 20),
          hintText: placeholder,
          labelText: hint,
          labelStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 13,
          ),
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: TextField(
        readOnly: true,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          icon: Icon(
            Icons.calendar_today,
            color: context.textSecondary,
            size: 20,
          ),
          hintText: "Select joining date",
          labelText: "Joining Date",
          labelStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 13,
          ),
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          suffixIcon: Icon(Icons.calendar_month, color: context.textSecondary),
        ),
        controller: TextEditingController(
          text:
              "${_joiningDate.day}/${_joiningDate.month}/${_joiningDate.year}",
        ),
        onTap: () {
          FocusScope.of(context).unfocus();
          _showShadCalendar();
        },
      ),
    );
  }

  void _showShadCalendar() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Select Joining Date",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: context.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ShadCalendar(
                      selected: _joiningDate,
                      fromMonth: DateTime(_joiningDate.year - 5),
                      toMonth: DateTime(_joiningDate.year + 2, 12),
                      onChanged: (DateTime? date) {
                        if (date != null) {
                          setState(() {
                            _joiningDate = date;
                          });
                          Navigator.pop(context);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.textPrimary,
                          foregroundColor: context.appBackground,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "Done",
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectField({
    required String label,
    required String? currentValue,
    required Map<String, String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ShadSelect<String>(
            placeholder: Text(
              'Select $label',
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textTertiary,
                fontSize: 14,
              ),
            ),
            initialValue: currentValue,
            options: [
              ...items.entries.map(
                (e) => ShadOption(value: e.key, child: Text(e.value)),
              ),
            ],
            selectedOptionBuilder: (context, value) => Text(
              items[value]!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
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
          onPressed: _isLoading ? null : _updateMember,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.textPrimary,
            foregroundColor: context.appBackground,
            disabledBackgroundColor: context.textTertiary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.appBackground,
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
