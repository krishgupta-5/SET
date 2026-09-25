import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'company_details_screen.dart';
import 'edit_profile_screen.dart';
import 'statements_screen.dart';
import 'change_password.dart';
import 'privacy_assurances_screen.dart';
import 'budget_settings_screen.dart';
import '../widgets/coming_soon_dialog.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/theme_service.dart';
import '../../../theme/app_theme.dart';
import 'set_password.dart';
import 'add_funding_screen.dart';
import 'category_settings_screen.dart';
import 'manage_recurring_payments_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Cache for Telegram photos to avoid repeated fetching
  static final Map<String, String> _telegramPhotoCache = {};

  // Telegram photo fetching methods with caching
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

  String _selectedCurrency = '+1';
  bool _isLoading = false;

  ThemeMode _selectedTheme = ThemeService.getThemePreferenceSync();
  bool _isThemeLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedCurrency = CurrencyPreferenceService.getCurrencyPreferenceSync();
    _selectedTheme = ThemeService.getThemePreferenceSync();
    _loadCurrencyPreference();
    _loadThemePreference();

    // Listen for currency and theme changes
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      if (kDebugMode) print('Currency changed listener triggered');
      setState(() {
        _selectedCurrency =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
        if (kDebugMode) {
          print('Updated _selectedCurrency to: $_selectedCurrency');
        }
      });
    }
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _selectedTheme = ThemeService.getThemePreferenceSync();
      });
    }
  }

  Future<void> _loadCurrencyPreference() async {
    if (kDebugMode) print('Settings: Loading currency preference');
    setState(() => _isLoading = true);
    try {
      final currency = await CurrencyPreferenceService.getCurrencyPreference();
      if (kDebugMode) print('Settings: Loaded currency: $currency');
      if (mounted) {
        setState(() {
          _selectedCurrency = currency;
          if (kDebugMode) {
            print('Settings: Set _selectedCurrency to: $_selectedCurrency');
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Settings: Error loading currency: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadThemePreference() async {
    setState(() => _isThemeLoading = true);
    try {
      await ThemeService.getThemePreference();
      if (mounted) {
        setState(() {
          _selectedTheme = ThemeService.getThemePreferenceSync();
          _isThemeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isThemeLoading = false);
    }
  }

  Future<void> _showThemeSelector() async {
    final availableThemes = [
      {
        'mode': ThemeMode.dark,
        'name': 'Dark Mode',
        'icon': Icons.dark_mode_rounded,
      },
      {
        'mode': ThemeMode.light,
        'name': 'Light Mode',
        'icon': Icons.light_mode_rounded,
      },
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (bottomSheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.5,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Theme Appearance',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              ListView.builder(
                shrinkWrap: true,
                itemCount: availableThemes.length,
                itemBuilder: (itemContext, index) {
                  final themeItem = availableThemes[index];
                  final mode = themeItem['mode'] as ThemeMode;
                  final activeTheme = ThemeService.themeModeNotifier.value;
                  final isSelected = activeTheme == mode;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          Navigator.pop(bottomSheetContext);
                          await _updateTheme(mode);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? context.textPrimary.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? context.textPrimary.withValues(alpha: 0.25)
                                  : context.borderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                themeItem['icon'] as IconData,
                                color: context.iconPrimary,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  themeItem['name'] as String,
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: context.iconPrimary,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    setState(() => _isThemeLoading = true);
    try {
      final success = await ThemeService.updateThemePreference(mode);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Theme updated to ${ThemeService.getThemeDisplayName(mode)}',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: const Color(0xFF00C851),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update theme',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF453A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating theme',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF453A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isThemeLoading = false);
      }
    }
  }

  Future<void> _showCurrencySelector() async {
    final availableCurrencies =
        CurrencyPreferenceService.getAvailableCurrencies();

    await showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true, // Allow proper height calculation
      builder: (bottomSheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(
            bottomSheetContext,
          ).viewInsets.bottom, // Handle keyboard
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(bottomSheetContext).size.height *
                0.7, // Max 70% of screen height
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Currency',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableCurrencies.length,
                  itemBuilder: (itemContext, index) {
                    final currency = availableCurrencies[index];
                    final isSelected = _selectedCurrency == currency['code'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            Navigator.pop(bottomSheetContext);
                            await _updateCurrency(currency['code']!);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? context.textPrimary.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? context.textPrimary.withValues(
                                        alpha: 0.25,
                                      )
                                    : context.borderColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  currency['symbol']!,
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    currency['name']!,
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check,
                                    color: context.iconPrimary,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateCurrency(String currencyCode) async {
    if (kDebugMode) {
      print('Settings: Starting currency update to: $currencyCode');
    }
    setState(() => _isLoading = true);

    try {
      final success = await CurrencyPreferenceService.updateCurrencyPreference(
        currencyCode,
      );

      if (kDebugMode) print('Settings: Currency update result: $success');

      if (success && mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Currency updated to ${CurrencyPreferenceService.getCurrencyDisplayName(currencyCode)}',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: const Color(0xFF00C851),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update currency',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF453A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('Settings: Exception during currency update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating currency',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF453A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Premium Header
              _buildHeader(context),

              const SizedBox(height: 32),

              // 2. Profile Section (Fully reactive)
              Center(child: _buildProfileSection(context)),

              const SizedBox(height: 48),

              // 3. Company & Statements
              _buildSectionLabel("ORGANIZATION"),
              _buildSettingsGroup([
                _buildTile(
                  icon: Icons.business,
                  title: "Company Details",
                  subtitle: "Manage address, funding, and structure",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CompanyDetailsScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                // NEW OPTION: Add Funding
                _buildTile(
                  icon: Icons.monetization_on_outlined,
                  title: "Add Funding",
                  subtitle: "Update your total available funds",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddFundingScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.category_outlined,
                  title: "Expense Categories",
                  subtitle: "Manage categories for your expenses",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CategorySettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.description_outlined,
                  title: "Statements",
                  subtitle: "Expense reports and exports",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ExpensesExportScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.autorenew,
                  title: "Manage Recurring Payments",
                  subtitle: "View and stop subscriptions or salaries",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const ManageRecurringPaymentsScreen(),
                      ),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 32),

              // 4. Preferences
              _buildSectionLabel("PREFERENCES"),
              _buildSettingsGroup([
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeService.themeModeNotifier,
                  builder: (context, currentThemeMode, _) {
                    return _buildTile(
                      icon: Icons.palette_outlined,
                      title: "Theme Appearance",
                      subtitle: ThemeService.getThemeDisplayName(
                        currentThemeMode,
                      ),
                      onTap: _showThemeSelector,
                      trailing: _isThemeLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  context.textPrimary,
                                ),
                              ),
                            )
                          : Text(
                              ThemeService.getThemeDisplayName(
                                currentThemeMode,
                              ),
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.currency_exchange,
                  title: "Currency",
                  subtitle: CurrencyPreferenceService.getCurrencyDisplayName(
                    _selectedCurrency,
                  ),
                  onTap: _showCurrencySelector,
                  trailing: _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              context.textPrimary,
                            ),
                          ),
                        )
                      : Text(
                          CurrencyPreferenceService.getCurrencySymbol(
                            _selectedCurrency,
                          ),
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: "Budget Settings",
                  subtitle: "Set budget for ALL expense categories",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BudgetSettingsScreen(),
                      ),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 32),

              // 5. Security & Data
              _buildSectionLabel("SECURITY & PRIVACY"),
              _buildSettingsGroup([
                // NEW OPTION: Set Password
                _buildTile(
                  icon: Icons.password_outlined,
                  title: "Set Password",
                  subtitle: "Create a password for Google accounts",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SetPasswordScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.lock_outline,
                  title: "Change Password",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: "Data Access Control",
                  subtitle: "Manage team permissions",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const ComingSoonDialog(),
                    );
                  },
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.security,
                  title: "Privacy Assurances",
                  subtitle: "How we protect your financial data",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PrivacyAssurancesScreen(),
                      ),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 32),

              // 6. Support
              _buildSectionLabel("SUPPORT"),
              _buildSettingsGroup([
                _buildTile(
                  icon: Icons.star_outline,
                  title: "Rate us on Play Store",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const ComingSoonDialog(),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 48),

              // 7. Logout
              _buildLogoutButton(),

              const SizedBox(height: 32),

              // 8. Version
              Center(
                child: Text(
                  "Version 1.0.2 (Build 402)",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSubtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildHeader(BuildContext context) {
    return Text(
      "Settings",
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: context.textPrimary,
        fontSize: 28, // Scaled up to match Home/Overview screens
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // Build profile avatar with Telegram photo support
  Widget _buildProfileAvatar(String? profileImageFileId) {
    if (profileImageFileId != null && profileImageFileId.isNotEmpty) {
      // Show uploaded profile image
      return FutureBuilder<String>(
        future: getTelegramImageUrl(profileImageFileId),
        builder: (context, snapshot) {
          return Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.borderColor, width: 1),
            ),
            child: ClipOval(
              child: snapshot.hasData
                  ? Image.network(
                      snapshot.data!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildDefaultAvatar();
                      },
                    )
                  : _buildDefaultAvatar(),
            ),
          );
        },
      );
    }

    // Show default avatar
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.borderColor, width: 1),
        color: context.cardSecondaryBackground,
        boxShadow: context.cardShadow,
      ),
      child: Icon(Icons.person, size: 40, color: context.iconSecondary),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const SizedBox();
    }

    // StreamBuilder listens to both user and company documents for complete profile data
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection("companies")
              .doc(user.uid)
              .snapshots(),
          builder: (context, companySnapshot) {
            String name = user.displayName ?? 'User';
            String email = user.email ?? 'No email';

            // Override with user document data if available
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData =
                  userSnapshot.data!.data() as Map<String, dynamic>;
              name = userData['name'] ?? name;
              email = userData['email'] ?? email;
            }

            // Priority: Use owner name from company data if available
            if (companySnapshot.hasData && companySnapshot.data!.exists) {
              final companyData =
                  companySnapshot.data!.data() as Map<String, dynamic>;
              name = companyData['Owner Name'] ?? name;
            }

            // Load profile image FileId from user data
            String? profileImageFileId;
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData =
                  userSnapshot.data!.data() as Map<String, dynamic>;
              profileImageFileId = userData['profileImageFileId'];
            }

            return Column(
              children: [
                _buildProfileAvatar(profileImageFileId),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EditProfileScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.glassBackgroundStrong,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Text(
                      "Edit Profile",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDarkMode
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.glassBackgroundStrong,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.iconPrimary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null)
                Icon(
                  Icons.chevron_right,
                  color: context.iconSecondary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: context.borderColor,
      indent: 76, // 20 padding + 40 icon width + 16 gap
    );
  }

  Widget _buildLogoutButton() {
    return Builder(
      builder: (context) => SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(
              0xFFFF453A,
            ).withValues(alpha: 0.1), // Soft Red fill
            foregroundColor: const Color(0xFFFF453A),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: const Color(
                  0xFFFF453A,
                ).withValues(alpha: 0.2), // Red border
              ),
            ),
          ),
          child: Text(
            "Log Out",
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
