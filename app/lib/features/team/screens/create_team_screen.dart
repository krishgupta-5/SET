import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:uuid/uuid.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import '../team_style.dart';

class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _budgetController;

  bool _isLoading = false;
  String _selectedColor = "Blue";
  IconData _selectedIcon = TeamStyle.icons.first;
  String _userCountryCode = '+1';

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _nameController = TextEditingController()..addListener(_onPreview);
    _descController = TextEditingController();
    _budgetController = TextEditingController()..addListener(_onPreview);
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

  void _onPreview() => setState(() {});

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

  Future<void> _createTeam() async {
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
      final id = const Uuid().v4();
      await FirebaseFirestore.instance.collection('teams').doc(id).set({
        "uid": FirebaseAuth.instance.currentUser!.uid,
        "teamName": name,
        "description": desc,
        "monthlyBudget": budget,
        "color": _selectedColor,
        "iconCodePoint": _selectedIcon.codePoint,
        "iconFontFamily": _selectedIcon.fontFamily,
        "createdAt": FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        _toast("Team created");
      }
    } on FirebaseException catch (e) {
      if (mounted) _toast(e.message ?? 'Failed to create team', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
              const RxTopBar(title: 'New team'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    RxReveal.index(0, child: _buildPreview(symbol)),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
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
                            helper:
                                'Team spend and salaries are tracked against this',
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
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Create team',
                  icon: HugeIcons.strokeRoundedAdd01,
                  loading: _isLoading,
                  onTap: _createTeam,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live preview of the card as it will appear on the Team tab.
  Widget _buildPreview(String symbol) {
    final rx = context.rx;
    final name = _nameController.text.trim();
    final budget = CurrencyFormatter.parse(_budgetController.text.trim());
    return RxCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TeamIconTile(icon: _selectedIcon, colorName: _selectedColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Team name' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.body(
                    context,
                    color: name.isEmpty ? rx.textTertiary : rx.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text('No members yet', style: RxText.caption(context)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                budget != null && budget > 0
                    ? CurrencyFormatter.formatByCountryCompact(
                        budget,
                        _userCountryCode,
                      )
                    : '${symbol}0',
                style: RxText.amount(context),
              ),
              Text('per month', style: RxText.micro(context)),
            ],
          ),
        ],
      ),
    );
  }
}
