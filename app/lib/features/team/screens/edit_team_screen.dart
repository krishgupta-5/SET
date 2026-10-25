import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import '../team_style.dart';

class EditTeamScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> teamData;

  const EditTeamScreen({
    super.key,
    required this.teamId,
    required this.teamData,
  });

  @override
  State<EditTeamScreen> createState() => _EditTeamScreenState();
}

class _EditTeamScreenState extends State<EditTeamScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _budgetController;

  bool _isLoading = false;
  bool _isDeleting = false;

  late String _selectedColor;
  late IconData _selectedIcon;
  String _userCountryCode = '+1';

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);

    _nameController = TextEditingController(
      text: widget.teamData['teamName'] ?? "",
    );
    final budget = (widget.teamData['monthlyBudget'] as num?)?.toDouble() ?? 0;
    _budgetController = TextEditingController(
      text: budget > 0 ? budget.toStringAsFixed(2) : "",
    );
    _descController = TextEditingController(
      text: widget.teamData['description'] ?? "",
    );
    _selectedColor = widget.teamData['color'] ?? "Blue";
    _selectedIcon = TeamStyle.icon(widget.teamData);
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _nameController.dispose();
    _descController.dispose();
    _budgetController.dispose();
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

  void _toast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

  // --- FIREBASE LOGIC (unchanged) ---

  Future<void> _updateTeam() async {
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();

    if (name.isEmpty) return _toast("Please enter a team name.", isError: true);
    if (name.length < 2) {
      return _toast(
        "Team name must be at least 2 characters long.",
        isError: true,
      );
    }
    if (name.length > 30) {
      return _toast("Team name must not exceed 30 characters.", isError: true);
    }
    if (desc.length > 200) {
      return _toast(
        "Description must not exceed 200 characters.",
        isError: true,
      );
    }
    if (_budgetController.text.trim().isEmpty) {
      return _toast(
        "Please enter a monthly budget for this team.",
        isError: true,
      );
    }
    final double? budget = CurrencyFormatter.parse(
      _budgetController.text.trim(),
    );
    if (budget == null || budget <= 0) {
      return _toast(
        "Please enter a valid budget amount greater than 0.",
        isError: true,
      );
    }
    if (budget > 999999.99) {
      return _toast("Budget amount is too high.", isError: true);
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('teams')
          .doc(widget.teamId)
          .update({
            "teamName": name,
            "description": desc,
            "monthlyBudget": budget,
            "color": _selectedColor,
            "iconCodePoint": _selectedIcon.codePoint,
            "iconFontFamily": _selectedIcon.fontFamily,
          });
      if (mounted) {
        Navigator.pop(context);
        _toast("Team updated");
      }
    } on FirebaseException catch (e) {
      if (mounted) _toast(e.message ?? 'Failed to update team', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTeam() async {
    setState(() => _isDeleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] ?? user.uid;

      final membersSnapshot = await FirebaseFirestore.instance
          .collection('members')
          .where('teamId', isEqualTo: widget.teamId)
          .get();

      double totalActualPayouts = 0;
      final batch = FirebaseFirestore.instance.batch();
      final archiveCollection = FirebaseFirestore.instance.collection(
        'archived_payments',
      );

      for (var memberDoc in membersSnapshot.docs) {
        final memberData = memberDoc.data();
        final memberName = memberData['fullName'] ?? 'Unknown';
        final memberId = memberDoc.id;

        final expensesSnapshot = await FirebaseFirestore.instance
            .collection('expenses')
            .where('uid', isEqualTo: user.uid)
            .where('memberId', isEqualTo: memberId)
            .where('Category', isEqualTo: 'salary')
            .get();

        for (var expenseDoc in expensesSnapshot.docs) {
          final expenseData = Map<String, dynamic>.from(expenseDoc.data());
          final paidAmount = (expenseData['Amount'] as num?)?.toDouble() ?? 0.0;
          totalActualPayouts += paidAmount;

          expenseData['originalMemberId'] = memberId;
          expenseData['originalMemberName'] = memberName;
          expenseData['originalTeamId'] = widget.teamId;
          expenseData['archivedAt'] = FieldValue.serverTimestamp();
          expenseData['archiveReason'] = 'team_deleted';

          batch.set(archiveCollection.doc(), expenseData);
          batch.delete(expenseDoc.reference);
        }
        batch.delete(memberDoc.reference);
      }

      batch.delete(
        FirebaseFirestore.instance.collection('teams').doc(widget.teamId),
      );

      if (totalActualPayouts > 0) {
        final companyRef = FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId);
        batch.update(companyRef, {
          "totalExpenses": FieldValue.increment(-totalActualPayouts),
        });
      }

      await batch.commit();

      if (mounted) {
        Navigator.of(context).pop(); // edit screen
        Navigator.of(context).pop(); // detail screen, back to the list
        _toast("Team and all members removed");
      }
    } on FirebaseException catch (e) {
      if (mounted) _toast(e.message ?? 'Failed to delete team', isError: true);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  /// Type-the-name confirmation, since deleting also removes members.
  void _showDeleteConfirmation() {
    final rx = context.rx;
    final confirmController = TextEditingController();
    final expectedName = (widget.teamData['teamName'] ?? '').toString();

    showDialog(
      context: context,
      barrierColor: rx.barrier,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          final matched = confirmController.text.trim() == expectedName;
          return Dialog(
            backgroundColor: rx.sheet,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RxIconTile(
                    icon: HugeIcons.strokeRoundedDelete02,
                    size: 40,
                    iconSize: 20,
                    background: rx.negativeSoft,
                    foreground: rx.negative,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Delete team?',
                    style: RxText.heading(dialogContext).copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This removes the team and all its members. Their salary payments are archived. This can\'t be undone.',
                    style: RxText.caption(
                      dialogContext,
                    ).copyWith(fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  RxTextInput(
                    controller: confirmController,
                    label: 'Type "$expectedName" to confirm',
                    hint: expectedName,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: RxButton(
                          label: 'Cancel',
                          height: 46,
                          style: RxButtonStyle.secondary,
                          onTap: () => Navigator.pop(dialogContext),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RxButton(
                          label: 'Delete',
                          height: 46,
                          style: RxButtonStyle.destructive,
                          onTap: matched
                              ? () {
                                  Navigator.pop(dialogContext);
                                  _deleteTeam();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(confirmController.dispose);
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
              const RxTopBar(title: 'Edit team'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    RxReveal.index(
                      0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Details'),
                          RxTextInput(
                            controller: _nameController,
                            label: 'Team name',
                            hint: 'e.g. Engineering',
                            icon: HugeIcons.strokeRoundedUserGroup,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _descController,
                            label: 'Description',
                            hint: 'What does this team do? (optional)',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _budgetController,
                            label: 'Monthly budget',
                            hint: '0',
                            prefixText: symbol,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: RxTextInput.money,
                            textInputAction: TextInputAction.done,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Look'),
                          RxCard(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                            child: TeamIdentityPicker(
                              colorName: _selectedColor,
                              icon: _selectedIcon,
                              onColor: (c) {
                                FocusScope.of(context).unfocus();
                                setState(() => _selectedColor = c);
                              },
                              onIcon: (i) {
                                FocusScope.of(context).unfocus();
                                setState(() => _selectedIcon = i);
                              },
                            ),
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
                          const RxSectionHeader(title: 'Danger zone'),
                          RxCard(
                            onTap: _isDeleting ? null : _showDeleteConfirmation,
                            semanticLabel: 'Delete team',
                            child: Row(
                              children: [
                                RxIconTile(
                                  icon: HugeIcons.strokeRoundedDelete02,
                                  size: 40,
                                  iconSize: 19,
                                  background: rx.negativeSoft,
                                  foreground: rx.negative,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Delete team',
                                        style: RxText.body(
                                          context,
                                          color: rx.negative,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Removes the team and its members',
                                        style: RxText.caption(context),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isDeleting)
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: rx.negative,
                                    ),
                                  ),
                              ],
                            ),
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
                  onTap: _isDeleting ? null : _updateTeam,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
