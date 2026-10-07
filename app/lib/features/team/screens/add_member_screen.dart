import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/telegram_service.dart'; // T-06/T-07/T-21
import '../../../theme/app_theme.dart';

class AddMemberScreen extends StatefulWidget {
  final String teamId;

  const AddMemberScreen({super.key, required this.teamId});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen>
    with SingleTickerProviderStateMixin {
  // 1. CONTROLLERS & STATE
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _costController;

  bool _isLoading = false;

  String _userCountryCode = '+1'; // Default to USD

  // T-07/T-21: Telegram cache moved to TelegramService (6-hour TTL)

  // 2. DATA LISTS
  // T-23: _selectedTeamId removed — always equalled widget.teamId with no UI to
  // change it. All references now use widget.teamId directly.

  final Map<String, String> types = {
    'full_time': 'Full-time',
    'part_time': 'Part-time',
    'contractor': 'Contractor',
    'intern': 'Intern',
  };

  String _employmentType = "full_time";
  DateTime _joiningDate = DateTime.now();
  String? _telegramFileId;

  @override
  void initState() {
    super.initState();

    // Get currency preference synchronously for instant display
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    // Listen for currency changes
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);

    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _jobTitleController = TextEditingController();
    _costController = TextEditingController();

    // (T-23: _selectedTeamId assignment removed — use widget.teamId directly)
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _nameController.dispose();
    _emailController.dispose();
    _jobTitleController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      setState(() {
        _userCountryCode =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
    }
  }

  // --- FIREBASE LOGIC ---

  Future<void> _saveMember() async {
    // Basic Validation
    if (_nameController.text.trim().isEmpty) {
      _showErrorSnackBar("Please enter member's name.");
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

    if (_jobTitleController.text.trim().length > 100) {
      _showErrorSnackBar("Job title must not exceed 100 characters.");
      return;
    }

    // Monthly cost is now mandatory
    if (_costController.text.trim().isEmpty) {
      _showErrorSnackBar(
        "Monthly cost is required. Please enter the member's monthly cost.",
      );
      return;
    }

    final double? cost = CurrencyFormatter.parse(_costController.text.trim());
    if (cost == null || cost < 0) {
      _showErrorSnackBar("Please enter a valid monthly cost.");
      return;
    }

    // Allow much higher amounts (up to 99 million)
    if (cost > 99999999.99) {
      _showErrorSnackBar(
        "Monthly cost amount is too high. Maximum allowed is 99,999,999.99",
      );
      return;
    }

    if (_joiningDate.isAfter(DateTime.now())) {
      _showErrorSnackBar("Joining date cannot be in the future.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final double cost = CurrencyFormatter.parse(_costController.text.trim())!;

      await FirebaseFirestore.instance.collection('members').add({
        "uid": FirebaseAuth.instance.currentUser!.uid,
        "teamId": widget.teamId,
        "fullName": _nameController.text.trim(),
        "email": _emailController.text.trim(),
        "jobTitle": _jobTitleController.text.trim(),
        "joiningDate": _joiningDate,
        "employmentType": _employmentType,
        "monthlyCost": cost,
        // T-15: 'salary' mirrors 'monthlyCost'. Both fields are kept in sync
        // by adjust_salary_screen._updateSalary(). monthlyCost is the canonical
        // value used for all financial calculations.
        "salary": cost,
        "createdAt": FieldValue.serverTimestamp(),
        // T-14: avatarUrl is intentionally left empty when the photo is stored
        // via Telegram. Use telegramFileId to fetch the resolved HTTPS URL.
        // (Historically avatarUrl held the raw fileId — now distinct fields.)
        "avatarUrl": "",
        "telegramFileId": _telegramFileId ?? "",
        "status": "Active",
      });

      debugPrint("Member added successfully with teamId: ${widget.teamId}");

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Member added successfully!",
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
        _showErrorSnackBar(e.message ?? 'Failed to add member');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  Future<void> _showImagePicker() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard if open
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
              "Upload Photo",
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

      // T-21: Use TelegramService.uploadPhoto — single implementation
      final fileId = await TelegramService.uploadPhoto(imageFile.path);

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
              // 1. Header
              _buildHeader(context),

              // 2. Scrollable Form
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        "Add Member",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 28, // Compact Hero
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // --- AVATAR UPLOADER ---
                      Center(child: _buildAvatarUploader()),
                      const SizedBox(height: 40),

                      // --- PERSONAL DETAILS ---
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
                        _jobTitleController,
                        textInputAction: TextInputAction.done,
                      ),

                      const SizedBox(height: 32),

                      // --- JOINING DATE ---
                      _buildSectionLabel("JOINING DATE"),
                      const SizedBox(height: 16),
                      _buildDateSelector(),

                      const SizedBox(height: 32),

                      // --- TEAM INFO ---
                      _buildSectionLabel("TEAM ASSIGNMENT"),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.group,
                              color: context.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Member will be added to current team",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Automatic team assignment",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: const Color(0xFF30D158),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // --- EMPLOYMENT TYPE ---
                      _buildSelectField(
                        label: "Employment Type",
                        currentValue: _employmentType,
                        items: types,
                        onChanged: (val) {
                          FocusScope.of(context).unfocus();
                          setState(() => _employmentType = val!);
                        },
                      ),

                      const SizedBox(height: 32),

                      // --- COMPENSATION ---
                      _buildSectionLabel("COMPENSATION"),
                      const SizedBox(height: 16),
                      _buildSalaryInput(),
                      const SizedBox(height: 8),
                      Text(
                        "This amount will be added to your monthly burn rate.",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              // 3. Save Button
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

  // Avatar Uploader with Telegram functionality
  Widget _buildAvatarUploader() {
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
                if (_telegramFileId != null)
                  FutureBuilder<String>(
                    future: TelegramService.getImageUrl(_telegramFileId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return CircularProgressIndicator(
                          color: context.textSecondary,
                          strokeWidth: 2,
                        );
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return Icon(
                          Icons.person,
                          color: context.textTertiary,
                          size: 48,
                        );
                      }
                      return ClipOval(
                        child: Image.network(
                          snapshot.data!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.person,
                              color: context.textTertiary,
                              size: 48,
                            );
                          },
                        ),
                      );
                    },
                  )
                else
                  Icon(Icons.person, color: context.textTertiary, size: 48),
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
            _telegramFileId != null
                ? "Photo uploaded to Telegram"
                : "Upload Photo",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: _telegramFileId != null
                  ? const Color(0xFF30D158)
                  : context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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

  Widget _buildSalaryInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF30D158).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              CurrencyFormatter.getCurrencySymbol(_userCountryCode),
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: const Color(0xFF30D158),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "MONTHLY COST",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                TextField(
                  controller: _costController,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (event) => FocusScope.of(context).unfocus(),
                  keyboardType: TextInputType.text,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: "0.00",
                    hintStyle: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textTertiary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        _buildSectionLabel(label),
        const SizedBox(height: 8),
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
          onPressed: _isLoading ? null : _saveMember,
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
                  "Add Member",
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
