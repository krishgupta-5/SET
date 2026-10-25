import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'company_details_screen.dart';
import 'edit_profile_screen.dart';
import 'statements_screen.dart';
import 'change_password.dart';
import 'privacy_assurances_screen.dart';
import 'budget_settings_screen.dart';
import 'set_password.dart';
import 'add_funding_screen.dart';
import 'category_settings_screen.dart';
import 'manage_recurring_payments_screen.dart';
import '../widgets/coming_soon_dialog.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/telegram_service.dart';
import '../../../services/theme_service.dart';
import '../../../widgets/custom_bottom_nav.dart' show RxTabBar;
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedCurrency = '+1';
  bool _isLoading = false;
  bool _isThemeLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedCurrency = CurrencyPreferenceService.getCurrencyPreferenceSync();
    _loadCurrencyPreference();
    _loadThemePreference();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      setState(() {
        _selectedCurrency =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
    }
  }

  Future<void> _loadCurrencyPreference() async {
    setState(() => _isLoading = true);
    try {
      final currency = await CurrencyPreferenceService.getCurrencyPreference();
      if (mounted) {
        setState(() {
          _selectedCurrency = currency;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      await ThemeService.getThemePreference();
    } catch (_) {}
  }

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  void _comingSoon({
    RxArtScene scene = RxArtScene.rocket,
    String title = 'Coming soon',
    String? message,
  }) => showDialog(
    context: context,
    builder: (_) => message == null
        ? ComingSoonDialog(scene: scene, title: title)
        : ComingSoonDialog(scene: scene, title: title, message: message),
  );

  // --- PREFERENCES (logic unchanged) ---

  Future<void> _updateTheme(ThemeMode mode) async {
    if (ThemeService.themeModeNotifier.value == mode) return;
    setState(() => _isThemeLoading = true);
    try {
      final success = await ThemeService.updateThemePreference(mode);
      if (!mounted) return;
      if (!success) {
        showRxToast(context, 'Failed to update theme', isError: true);
      }
    } catch (_) {
      if (mounted) showRxToast(context, 'Error updating theme', isError: true);
    } finally {
      if (mounted) setState(() => _isThemeLoading = false);
    }
  }

  Future<void> _showCurrencySelector() async {
    final currencies = CurrencyPreferenceService.getAvailableCurrencies();
    final picked = await showRxSelectSheet<String>(
      context,
      title: 'Currency',
      selected: _selectedCurrency,
      options: [
        for (final c in currencies)
          RxOption(c['code']!, c['name']!, subtitle: c['symbol']),
      ],
    );
    if (picked != null && picked != _selectedCurrency) {
      await _updateCurrency(picked);
    }
  }

  Future<void> _updateCurrency(String currencyCode) async {
    setState(() => _isLoading = true);
    try {
      final success = await CurrencyPreferenceService.updateCurrencyPreference(
        currencyCode,
      );
      if (!mounted) return;
      if (success) {
        showRxToast(
          context,
          'Currency set to ${CurrencyPreferenceService.getCurrencyDisplayName(currencyCode)}',
        );
      } else {
        showRxToast(context, 'Failed to update currency', isError: true);
      }
    } catch (_) {
      if (mounted) {
        showRxToast(context, 'Error updating currency', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showRxConfirm(
      context,
      title: 'Log out?',
      message: 'You can sign back in any time with the same account.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (ok) await FirebaseAuth.instance.signOut();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Container(
        color: rx.background,
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              RxTabBar.reservedHeight(context),
            ),
            children: [
              RxReveal.index(
                0,
                child: const RxTabHeader(
                  label: 'Account and preferences',
                  title: 'Settings',
                ),
              ),
              const SizedBox(height: 20),
              RxReveal.index(1, child: _buildProfileCard()),
              const SizedBox(height: 28),
              RxReveal.index(
                2,
                child: _group('Company', [
                  _tile(
                    icon: HugeIcons.strokeRoundedBuilding03,
                    title: 'Company details',
                    subtitle: 'Name, address and structure',
                    onTap: () => _push(const CompanyDetailsScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedMoneyReceive01,
                    title: 'Add funding',
                    subtitle: 'Record a new round or top-up',
                    onTap: () => _push(const AddFundingScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedTag01,
                    title: 'Expense categories',
                    subtitle: 'Choose the categories you use',
                    onTap: () => _push(const CategorySettingsScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedWallet03,
                    title: 'Budgets',
                    subtitle: 'Monthly limit per category',
                    onTap: () => _push(const BudgetSettingsScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedRepeat,
                    title: 'Recurring payments',
                    subtitle: 'Subscriptions and salaries',
                    onTap: () => _push(const ManageRecurringPaymentsScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedFileDownload,
                    title: 'Statements',
                    subtitle: 'Download expense reports',
                    onTap: () => _push(const ExpensesExportScreen()),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              RxReveal.index(3, child: _buildPreferences()),
              const SizedBox(height: 28),
              RxReveal.index(
                4,
                child: _group('Security and privacy', [
                  _tile(
                    icon: HugeIcons.strokeRoundedKey01,
                    title: 'Set password',
                    subtitle: 'For accounts that sign in with Google',
                    onTap: () => _push(const SetPasswordScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedLockPassword,
                    title: 'Change password',
                    onTap: () => _push(const ChangePasswordScreen()),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedUserShield01,
                    title: 'Data access',
                    subtitle: 'Team permissions',
                    badge: 'Soon',
                    onTap: () => _comingSoon(
                      scene: RxArtScene.lock,
                      title: 'Access control is coming',
                      message:
                          'Soon you can choose what each teammate can see and edit.',
                    ),
                  ),
                  _tile(
                    icon: HugeIcons.strokeRoundedShield01,
                    title: 'Privacy',
                    subtitle: 'How we protect your data',
                    onTap: () => _push(const PrivacyAssurancesScreen()),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              RxReveal.index(
                5,
                child: _group('Support', [
                  _tile(
                    icon: HugeIcons.strokeRoundedStar,
                    title: 'Rate RunwayX',
                    subtitle: 'Tell us how we are doing',
                    badge: 'Soon',
                    onTap: () => _comingSoon(
                      scene: RxArtScene.star,
                      title: 'Ratings open soon',
                      message:
                          "Once we're on the Play Store you can rate RunwayX right from here.",
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              RxReveal.index(
                6,
                child: RxCard(
                  onTap: _logout,
                  semanticLabel: 'Log out',
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  child: Row(
                    children: [
                      RxIconTile(
                        icon: HugeIcons.strokeRoundedLogout03,
                        size: 38,
                        iconSize: 19,
                        background: rx.negativeSoft,
                        foreground: rx.negative,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Log out',
                        style: RxText.body(context, color: rx.negative),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'RunwayX · Version 1.0.2 (402)',
                  style: RxText.micro(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- PROFILE ---

  Widget _buildProfileCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final rx = context.rx;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection("companies")
              .doc(user.uid)
              .snapshots(),
          builder: (context, companySnap) {
            String name = user.displayName ?? 'User';
            String email = user.email ?? '';
            String? company;
            String? photoId;

            if (userSnap.hasData && userSnap.data!.exists) {
              final d = userSnap.data!.data() as Map<String, dynamic>;
              name = d['name'] ?? name;
              email = d['email'] ?? email;
              photoId = d['profileImageFileId'] as String?;
            }
            // Owner name on the company wins, as before.
            if (companySnap.hasData && companySnap.data!.exists) {
              final d = companySnap.data!.data() as Map<String, dynamic>;
              name = d['Owner Name'] ?? name;
              company = (d['Company Name'] ?? d['companyName'])?.toString();
            }

            return RxCard(
              onTap: () => _push(const EditProfileScreen()),
              semanticLabel: 'Edit profile, $name',
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(
                children: [
                  _avatar(name, photoId),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RxText.heading(context).copyWith(fontSize: 17),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (company != null && company.isNotEmpty) company,
                            if (email.isNotEmpty) email,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RxText.caption(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: rx.surfaceMuted,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Edit',
                      style: RxText.label(
                        context,
                        color: rx.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _avatar(String name, String? photoId) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const size = 56.0;

    Widget initials() {
      final parts = name.trim().split(RegExp(r'\s+'));
      final text = parts.isEmpty || parts.first.isEmpty
          ? '?'
          : parts.length > 1
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: rx.surfaceMuted,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: RxText.value(context, size: 19, color: rx.textSecondary),
        ),
      );
    }

    if (photoId == null || photoId.isEmpty) return initials();
    return FutureBuilder<String>(
      future: TelegramService.getImageUrl(photoId),
      builder: (context, snap) {
        if (!snap.hasData) return initials();
        return Container(
          width: size,
          height: size,
          // Neutral 10% outline so the photo edge never tints.
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
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initials(),
            ),
          ),
        );
      },
    );
  }

  // --- PREFERENCES ---

  Widget _buildPreferences() {
    final rx = context.rx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RxSectionHeader(title: 'Preferences'),
        RxCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Theme switches in place: two options don't need a sheet.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    const RxIconTile(
                      icon: HugeIcons.strokeRoundedPaintBoard,
                      size: 38,
                      iconSize: 19,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Appearance', style: RxText.body(context)),
                    ),
                    if (_isThemeLoading)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: rx.textSecondary,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 150,
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeService.themeModeNotifier,
                        builder: (context, mode, _) => RxSegmented<ThemeMode>(
                          options: const {
                            ThemeMode.light: 'Light',
                            ThemeMode.dark: 'Dark',
                          },
                          value: mode == ThemeMode.dark
                              ? ThemeMode.dark
                              : ThemeMode.light,
                          onChanged: _updateTheme,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const RxDivider(indent: 64),
              _tile(
                icon: HugeIcons.strokeRoundedMoneyExchange01,
                title: 'Currency',
                subtitle: CurrencyPreferenceService.getCurrencyDisplayName(
                  _selectedCurrency,
                ),
                onTap: _showCurrencySelector,
                trailing: _isLoading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: rx.textSecondary,
                        ),
                      )
                    : Text(
                        CurrencyPreferenceService.getCurrencySymbol(
                          _selectedCurrency,
                        ),
                        style: RxText.value(
                          context,
                          size: 16,
                          color: rx.textSecondary,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- BUILDING BLOCKS ---

  Widget _group(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RxSectionHeader(title: title),
        RxCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const RxDivider(indent: 64),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required List<List<dynamic>> icon,
    required String title,
    String? subtitle,
    String? badge,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final rx = context.rx;
    return RxPressable(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            RxIconTile(icon: icon, size: 38, iconSize: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: RxText.body(context)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RxText.caption(context),
                    ),
                  ],
                ],
              ),
            ),
            if (badge != null) ...[
              RxPill(
                label: badge,
                foreground: rx.textSecondary,
                background: rx.surfaceMuted,
              ),
              const SizedBox(width: 6),
            ],
            if (trailing != null) ...[trailing, const SizedBox(width: 6)],
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: rx.textTertiary,
              size: 18,
              strokeWidth: 1.8,
            ),
          ],
        ),
      ),
    );
  }
}
