import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';
import '../team_widgets.dart';

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
  bool _isUploading = false;
  bool _isLoadingTeams = true;

  Map<String, String> _teams = {};
  String? _selectedTeamId;
  String? _telegramFileId;

  static const _statuses = ['Active', 'Paused', 'Inactive'];

  late String _status;
  late DateTime _joiningDate;

  @override
  void initState() {
    super.initState();
    final m = widget.memberData;
    _nameController = TextEditingController(text: m['fullName'] ?? "")
      ..addListener(() => setState(() {}));
    _roleController = TextEditingController(text: m['jobTitle'] ?? "");
    _emailController = TextEditingController(text: m['email'] ?? "");

    _status = m['status'] ?? "Active";
    if (!_statuses.contains(_status)) _status = 'Active';
    _selectedTeamId = m['teamId'];
    _telegramFileId = memberPhotoId(m);
    _joiningDate = m['joiningDate'] is Timestamp
        ? (m['joiningDate'] as Timestamp).toDate()
        : DateTime.now();

    _fetchTeams();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _error(String message) => showRxToast(context, message, isError: true);

  Future<void> _fetchTeams() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('teams')
          .where('uid', isEqualTo: uid)
          .get();
      final Map<String, String> fetched = {
        for (var doc in snapshot.docs)
          doc.id: (doc.data()['teamName'] ?? 'Unnamed Team').toString(),
      };
      if (mounted) {
        setState(() {
          _teams = fetched;
          // The member's team was deleted: fall back to the first one.
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
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) return _error("Name cannot be empty");
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
    if (_roleController.text.trim().length > 100) {
      return _error("Job title must not exceed 100 characters.");
    }
    if (_joiningDate.isAfter(DateTime.now())) {
      return _error("Joining date cannot be in the future.");
    }

    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> updateData = {
        "fullName": name,
        "jobTitle": _roleController.text.trim(),
        "email": email,
        "teamId": _selectedTeamId,
        "status": _status,
        "joiningDate": _joiningDate,
      };
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
        showRxToast(context, "Profile updated");
      }
    } on FirebaseException catch (e) {
      if (mounted) _error(e.message ?? 'Failed to update profile');
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
              const RxTopBar(title: 'Edit member'),
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
                          avatarUrl: widget.memberData['avatarUrl'] as String?,
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
                            controller: _roleController,
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
                          if (_isLoadingTeams)
                            const RxSkeleton(height: 52, radius: 14)
                          else
                            RxSelectField<String>(
                              label: 'Team',
                              value: _selectedTeamId,
                              placeholder: 'No teams',
                              icon: HugeIcons.strokeRoundedUserGroup,
                              options: [
                                for (final e in _teams.entries)
                                  RxOption(e.key, e.value),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedTeamId = v),
                            ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Text(
                              'Status',
                              style: RxText.label(
                                context,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          RxSegmented<String>(
                            options: {for (final s in _statuses) s: s},
                            value: _status,
                            onChanged: (v) => setState(() => _status = v),
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
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Save changes',
                  loading: _isLoading,
                  onTap: _isUploading ? null : _updateMember,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
