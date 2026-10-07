import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../theme/app_theme.dart';

// --- CUSTOM DOTTED DIVIDER WIDGET ---
class DottedDivider extends StatelessWidget {
  final Color color;
  final double height;
  final double dashWidth;

  const DottedDivider({
    super.key,
    required this.color,
    this.height = 1.0,
    this.dashWidth = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: height,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
        );
      },
    );
  }
}

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

class _EditTeamScreenState extends State<EditTeamScreen>
    with SingleTickerProviderStateMixin {
  // 1. CONTROLLERS & STATE
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _budgetController;

  bool _isLoading = false;
  bool _isDeleting = false;

  late String _selectedColor;
  late IconData _selectedIcon;
  String _userCountryCode = '+1'; // Default

  // 2. DATA OPTIONS
  final List<Map<String, dynamic>> _colors = [
    {"name": "Blue", "color": const Color(0xFF0A84FF)},
    {"name": "Orange", "color": const Color(0xFFFF9F0A)},
    {"name": "Purple", "color": const Color(0xFFA259FF)},
    {"name": "Green", "color": const Color(0xFF30D158)},
    {"name": "Red", "color": const Color(0xFFFF453A)},
  ];

  final List<IconData> _icons = [
    Icons.rocket_launch_rounded,
    Icons.code_rounded,
    Icons.palette_rounded,
    Icons.insights_rounded,
    Icons.campaign_rounded,
    Icons.support_agent_rounded,
  ];

  Color get _currentTeamColor {
    final match = _colors.firstWhere(
      (c) => c["name"] == _selectedColor,
      orElse: () => _colors.first,
    );
    return match["color"] as Color;
  }

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);

    // Pre-fill controllers with data from Firebase
    _nameController = TextEditingController(
      text: widget.teamData['teamName'] ?? "",
    );

    // Initialize budget controller with proper formatting
    final budget = widget.teamData['monthlyBudget']?.toDouble() ?? 0.0;
    _budgetController = TextEditingController(
      text: budget > 0 ? budget.toStringAsFixed(2) : "",
    );

    _descController = TextEditingController(
      text: widget.teamData['description'] ?? "",
    );

    _selectedColor = widget.teamData['color'] ?? "Blue";

    // Initialize Icon
    final cp = widget.teamData['iconCodePoint'];
    if (cp != null) {
      final codePoint = cp is int
          ? cp
          : int.tryParse(cp.toString()) ??
                Icons.rocket_launch_rounded.codePoint;

      // Find the matching icon from the known list instead of constructing a non-constant IconData
      _selectedIcon = _icons.firstWhere(
        (icon) => icon.codePoint == codePoint,
        orElse: () => _icons.first,
      );
    } else {
      _selectedIcon = _icons.first;
    }
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

  void _showMinimalToast(String message, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF141416)
        : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final textPrimary = isDark ? Colors.white : const Color(0xFF09090B);
    final statusColor = isError
        ? const Color(0xFFFF375F)
        : const Color(0xFF10B981);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cardColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 16,
      ),
    );
  }

  // --- FIREBASE LOGIC ---

  Future<void> _updateTeam() async {
    FocusScope.of(context).unfocus();

    if (_nameController.text.trim().isEmpty) {
      _showMinimalToast("Please enter a team name.", isError: true);
      return;
    }

    if (_nameController.text.trim().length < 2) {
      _showMinimalToast(
        "Team name must be at least 2 characters long.",
        isError: true,
      );
      return;
    }

    if (_nameController.text.trim().length > 30) {
      _showMinimalToast(
        "Team name must not exceed 30 characters.",
        isError: true,
      );
      return;
    }

    if (_descController.text.trim().isNotEmpty &&
        _descController.text.trim().length > 200) {
      _showMinimalToast(
        "Description must not exceed 200 characters.",
        isError: true,
      );
      return;
    }

    if (_budgetController.text.trim().isEmpty) {
      _showMinimalToast(
        "Please enter a monthly budget for this team.",
        isError: true,
      );
      return;
    }

    final double? budget = CurrencyFormatter.parse(
      _budgetController.text.trim(),
    );
    if (budget == null || budget <= 0) {
      _showMinimalToast(
        "Please enter a valid budget amount greater than 0.",
        isError: true,
      );
      return;
    }

    if (budget > 999999.99) {
      _showMinimalToast("Budget amount is too high.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final double validBudget = CurrencyFormatter.parse(
        _budgetController.text.trim(),
      )!;

      await FirebaseFirestore.instance
          .collection('teams')
          .doc(widget.teamId)
          .update({
            "teamName": _nameController.text.trim(),
            "description": _descController.text.trim(),
            "monthlyBudget": validBudget,
            "color": _selectedColor,
            "iconCodePoint": _selectedIcon.codePoint,
            "iconFontFamily": _selectedIcon.fontFamily,
          });

      if (mounted) {
        Navigator.pop(context);
        _showMinimalToast("Team updated successfully!");
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showMinimalToast(e.message ?? 'Failed to update team', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteTeam() async {
    setState(() => _isDeleting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get companyId — fall back to user.uid if not set
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] ?? user.uid;

      // Get all members in the team
      final membersSnapshot = await FirebaseFirestore.instance
          .collection('members')
          .where('teamId', isEqualTo: widget.teamId)
          .get();

      // Track ACTUAL paid-out amounts
      double totalActualPayouts = 0;

      final batch = FirebaseFirestore.instance.batch();
      final archiveCollection = FirebaseFirestore.instance.collection(
        'archived_payments',
      );

      for (var memberDoc in membersSnapshot.docs) {
        final memberData = memberDoc.data();
        final memberName = memberData['fullName'] ?? 'Unknown';
        final memberId = memberDoc.id;

        // Salary payments are in 'expenses'
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

      // Delete the team document
      batch.delete(
        FirebaseFirestore.instance.collection('teams').doc(widget.teamId),
      );

      // Adjust company expenses
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
        Navigator.of(context).pop(); // pop from edit screen
        Navigator.of(context).pop(); // pop from detail screen back to main list
        _showMinimalToast("Team and all members removed.");
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showMinimalToast(e.message ?? 'Failed to delete team', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showDeleteConfirmation() {
    final TextEditingController confirmController = TextEditingController();
    bool isMatched = false;
    final expectedName = widget.teamData['teamName'] ?? '';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF453A,
                            ).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFFF453A),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "Delete Team?",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "This action cannot be undone. The team and all associated members will be permanently removed from your organization.",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Please type '$expectedName' to confirm.",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: context.isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: TextField(
                        controller: confirmController,
                        onChanged: (value) {
                          setStateDialog(() {
                            isMatched = value.trim() == expectedName;
                          });
                        },
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: expectedName,
                          hintStyle: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.borderColor),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "Cancel",
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: isMatched
                                ? () {
                                    Navigator.pop(context);
                                    _deleteTeam();
                                  }
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isMatched
                                    ? const Color(0xFFFF453A)
                                    : const Color(
                                        0xFFFF453A,
                                      ).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "Delete",
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: isMatched
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF09090B) : const Color(0xFFF1F3F5);
    final cardColor = isDark
        ? const Color(0xFF141416)
        : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E7EB);

    final textPrimary = isDark ? Colors.white : const Color(0xFF09090B);
    final textSecondary = isDark ? Colors.white54 : const Color(0xFF71717A);
    final textTertiary = isDark ? Colors.white38 : const Color(0xFFA1A1AA);

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(textPrimary, textSecondary),

              Expanded(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildCompactHeroSection(textPrimary),
                          const SizedBox(height: 24),

                          // Single Unified Form Card
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: borderColor),
                              boxShadow: isDark
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildTextInput(
                                  label: "Team Name",
                                  placeholder: "e.g. Engineering",
                                  controller: _nameController,
                                  icon: Icons.workspaces_outline,
                                  textInputAction: TextInputAction.next,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  textTertiary: textTertiary,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 24),
                                DottedDivider(color: borderColor),
                                const SizedBox(height: 24),

                                _buildTextInput(
                                  label: "Description",
                                  placeholder: "What does this team do?",
                                  controller: _descController,
                                  icon: Icons.subject_rounded,
                                  maxLines: 3,
                                  textInputAction: TextInputAction.next,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  textTertiary: textTertiary,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 24),
                                DottedDivider(color: borderColor),
                                const SizedBox(height: 24),

                                // Visual Identity Section
                                Text(
                                  "Visual Identity",
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: _colors
                                      .map((c) => _buildColorOption(c))
                                      .toList(),
                                ),
                                const SizedBox(height: 20),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    children: _icons.map((i) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: _buildIconOption(
                                          i,
                                          borderColor,
                                          textSecondary,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),

                                const SizedBox(height: 24),
                                DottedDivider(color: borderColor),
                                const SizedBox(height: 24),

                                _buildTextInput(
                                  label: "Monthly Budget",
                                  placeholder: "e.g. 5000",
                                  controller: _budgetController,
                                  icon: Icons.attach_money_rounded,
                                  isNumber: true,
                                  textInputAction: TextInputAction.done,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  textTertiary: textTertiary,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Delete Team Button
                          GestureDetector(
                            onTap: _showDeleteConfirmation,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFF453A,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFFF453A),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Delete Team",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: Color(0xFFFF453A),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 48),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

              _buildSubmitButton(textPrimary, bgColor, borderColor),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildHeader(Color textPrimary, Color textSecondary) {
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
                  Icon(Icons.arrow_back, color: textSecondary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    "Back",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Balancing the header since delete icon is removed
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildCompactHeroSection(Color textPrimary) {
    return Text(
      "Edit Team",
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: textPrimary,
        fontSize: 28, // Compact Hero
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
      ),
    );
  }

  Widget _buildTextInput({
    required String label,
    required String placeholder,
    required TextEditingController controller,
    required IconData icon,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color borderColor,
    required bool isDark,
    int maxLines = 1,
    bool isNumber = false,
    TextInputAction textInputAction = TextInputAction.done,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: controller,
            textInputAction: textInputAction,
            onTapOutside: (event) => FocusScope.of(context).unfocus(),
            keyboardType: isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: textPrimary,
            maxLines: maxLines,
            minLines: maxLines > 1 ? 3 : 1,
            decoration: InputDecoration(
              icon: (maxLines == 1 && !isNumber)
                  ? Icon(icon, color: textSecondary, size: 18)
                  : null,
              hintText: placeholder,
              hintStyle: TextStyle(
                fontFamily: 'Satoshi',
                color: textTertiary,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              prefixIcon: isNumber
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            CurrencyFormatter.getCurrencySymbol(
                              _userCountryCode,
                            ),
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
              prefixIconConstraints: isNumber
                  ? const BoxConstraints(minWidth: 44, minHeight: 0)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorOption(Map<String, dynamic> colorData) {
    final bool isSelected = _selectedColor == colorData['name'];
    final Color color = colorData['color'];

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() => _selectedColor = colorData['name']);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isSelected ? 0.2 : 0.05),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: color, width: 2)
              : Border.all(color: Colors.transparent),
        ),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  Widget _buildIconOption(
    IconData icon,
    Color borderColor,
    Color textSecondary,
  ) {
    final bool isSelected = _selectedIcon.codePoint == icon.codePoint;
    final activeColor = _currentTeamColor;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() => _selectedIcon = icon);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: activeColor)
              : Border.all(color: borderColor),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : textSecondary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildSubmitButton(
    Color textPrimary,
    Color bgColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _updateTeam,
          style: ElevatedButton.styleFrom(
            backgroundColor: textPrimary,
            foregroundColor: bgColor,
            disabledBackgroundColor: textPrimary.withValues(alpha: 0.5),
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
                    strokeWidth: 2.5,
                    color: bgColor,
                  ),
                )
              : const Text(
                  "Save Changes",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
    );
  }
}
