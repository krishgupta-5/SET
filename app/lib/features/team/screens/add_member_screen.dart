import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';
import '../team_widgets.dart';

class AddMemberScreen extends StatefulWidget {
  final String teamId;

  const AddMemberScreen({super.key, required this.teamId});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _costController;

  bool _isLoading = false;
  bool _isUploading = false;
  String _userCountryCode = '+1';

  String _employmentType = "full_time";
  DateTime _joiningDate = DateTime.now();
  String? _telegramFileId;

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _nameController = TextEditingController()
      ..addListener(() => setState(() {}));
    _emailController = TextEditingController();
    _jobTitleController = TextEditingController();
    _costController = TextEditingController();
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

  void _error(String message) => showRxToast(context, message, isError: true);

  // --- FIREBASE LOGIC (unchanged) ---

  Future<void> _saveMember() async {
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) return _error("Please enter member's name.");
    if (name.length < 2) {
      return _error("Name must be at least 2 characters long.");
    }
    if (name.length > 50) return _error("Name must not exceed 50 characters.");
    if (email.isNotEmpty &&
        !RegExp(
          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        ).hasMatch(email)) {
      return _error("Please enter a valid email address.");
    }
    if (_jobTitleController.text.trim().length > 100) {
      return _error("Job title must not exceed 100 characters.");
    }
    if (_costController.text.trim().isEmpty) {
      return _error(
        "Monthly cost is required. Please enter the member's monthly cost.",
      );
    }
    final double? cost = CurrencyFormatter.parse(_costController.text.trim());
    if (cost == null || cost < 0) {
      return _error("Please enter a valid monthly cost.");
    }
    if (cost > 99999999.99) {
      return _error(
        "Monthly cost amount is too high. Maximum allowed is 99,999,999.99",
      );
    }
    if (_joiningDate.isAfter(DateTime.now())) {
      return _error("Joining date cannot be in the future.");
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('members').add({
        "uid": FirebaseAuth.instance.currentUser!.uid,
        "teamId": widget.teamId,
        "fullName": name,
        "email": email,
        "jobTitle": _jobTitleController.text.trim(),
        "joiningDate": _joiningDate,
        "employmentType": _employmentType,
        "monthlyCost": cost,
        // 'salary' mirrors 'monthlyCost'; monthlyCost is canonical.
        "salary": cost,
        "createdAt": FieldValue.serverTimestamp(),
        // Photos live on Telegram; avatarUrl stays empty.
        "avatarUrl": "",
        "telegramFileId": _telegramFileId ?? "",
        "status": "Active",
      });
      if (mounted) {
        Navigator.pop(context);
        showRxToast(context, "Member added");
      }
    } on FirebaseException catch (e) {
      if (mounted) _error(e.message ?? 'Failed to add member');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final id = await pickMemberPhoto(
      context,
      onStart: () => setState(() => _isUploading = true),
      onError: (m) {
        if (mounted) _error(m);
      },
    );
    if (!mounted) return;
    setState(() {
      _isUploading = false;
      if (id != null) _telegramFileId = id;
    });
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final symbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Add member'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    RxReveal.index(
                      0,
                      child: Center(
                        child: MemberPhotoPicker(
                          name: _nameController.text,
                          telegramFileId: _telegramFileId,
                          busy: _isUploading,
                          onTap: _pickPhoto,
                        ),
                      ),
                    ),
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
                            hint: 'e.g. Sarah Miller',
                            icon: HugeIcons.strokeRoundedUser,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _emailController,
                            label: 'Email',
                            hint: 'sarah@company.com (optional)',
                            icon: HugeIcons.strokeRoundedMail01,
                            keyboardType: TextInputType.emailAddress,
                            textCapitalization: TextCapitalization.none,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _jobTitleController,
                            label: 'Job title',
                            hint: 'e.g. Product Designer',
                            icon: HugeIcons.strokeRoundedBriefcase01,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
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
                          const RxSectionHeader(title: 'Employment'),
                          RxSelectField<String>(
                            label: 'Type',
                            value: _employmentType,
                            icon: HugeIcons.strokeRoundedBriefcase01,
                            options: [
                              for (final e in kEmploymentTypes.entries)
                                RxOption(e.key, e.value),
                            ],
                            onChanged: (v) =>
                                setState(() => _employmentType = v),
                          ),
                          const SizedBox(height: 16),
                          RxDateField(
                            label: 'Joining date',
                            value: _joiningDate,
                            lastDate: DateTime.now(),
                            onChanged: (d) => setState(() => _joiningDate = d),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Compensation'),
                          RxTextInput(
                            controller: _costController,
                            label: 'Monthly salary',
                            hint: '0',
                            prefixText: symbol,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: RxTextInput.money,
                            textInputAction: TextInputAction.done,
                            helper: 'Added to your monthly burn',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Add member',
                  icon: HugeIcons.strokeRoundedUserAdd01,
                  loading: _isLoading,
                  onTap: _isUploading ? null : _saveMember,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
