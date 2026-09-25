import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';

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

class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen>
    with SingleTickerProviderStateMixin {
  // 1. CONTROLLERS & STATE
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _budgetController;

  bool _isLoading = false;

  String _selectedColor = "Blue";
  IconData _selectedIcon = Icons.rocket_launch_rounded;
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

    _nameController = TextEditingController();
    _descController = TextEditingController();
    _budgetController = TextEditingController();
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

  // 3. FIREBASE UPLOAD LOGIC
  Future<void> _createTeam() async {
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
      final id = const Uuid().v4();
      final double validBudget = CurrencyFormatter.parse(
        _budgetController.text.trim(),
      )!;

      await FirebaseFirestore.instance.collection('teams').doc(id).set({
        "uid": FirebaseAuth.instance.currentUser!.uid,
        "teamName": _nameController.text.trim(),
        "description": _descController.text.trim(),
        "monthlyBudget": validBudget,
        "color": _selectedColor,
        "iconCodePoint": _selectedIcon.codePoint,
        "iconFontFamily": _selectedIcon.fontFamily,
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        _showMinimalToast("Team created successfully!");
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showMinimalToast(e.message ?? 'Failed to create team', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: _icons
                                      .map(
                                        (i) => _buildIconOption(
                                          i,
                                          borderColor,
                                          textSecondary,
                                        ),
                                      )
                                      .toList(),
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
          const SizedBox(width: 44), // Balances the header alignment
        ],
      ),
    );
  }

  Widget _buildCompactHeroSection(Color textPrimary) {
    return Text(
      "Create Team",
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
    final bool isSelected = _selectedIcon == icon;
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
          onPressed: _isLoading ? null : _createTeam,
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
                  "Create Team",
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
