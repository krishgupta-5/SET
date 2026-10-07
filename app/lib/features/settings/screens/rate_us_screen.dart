import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme/app_theme.dart';

class RateUsScreen extends StatefulWidget {
  const RateUsScreen({super.key});

  @override
  State<RateUsScreen> createState() => _RateUsScreenState();
}

class _RateUsScreenState extends State<RateUsScreen> {
  int _selectedRating = 0;
  final List<String> _ratingDescriptions = [
    "Not Rated",
    "Poor",
    "Fair",
    "Good",
    "Very Good",
    "Excellent",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Rate Us",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                          ),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        "Startup Expense Tracker",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Version 1.0.2 (Build 402)",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 40),

                      Text(
                        "How would you rate our app?",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _ratingDescriptions[_selectedRating],
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 24),

                      _buildStarRating(),

                      const SizedBox(height: 40),

                      if (_selectedRating > 0 && _selectedRating < 4) ...[
                        _buildFeedbackSection(),
                        const SizedBox(height: 40),
                      ],

                      if (_selectedRating >= 4) ...[
                        _buildPositiveActions(),
                        const SizedBox(height: 40),
                      ],

                      _buildAdditionalOptions(),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: () => setState(() => _selectedRating = index + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              index < _selectedRating ? Icons.star : Icons.star_border,
              color: index < _selectedRating
                  ? Colors.amber
                  : context.borderColorStrong,
              size: 40,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFeedbackSection() {
    final btnBg = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Help us improve",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "We're sorry to hear you're not completely satisfied. Your feedback helps us improve the app.",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: btnBg,
                foregroundColor: context.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                "Send Feedback",
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
    );
  }

  Widget _buildPositiveActions() {
    final primaryBg = context.isDarkMode ? Colors.white : Colors.black;
    final primaryText = context.isDarkMode ? Colors.black : Colors.white;
    final secondaryBg = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
            boxShadow: context.cardShadow,
          ),
          child: Column(
            children: [
              Text(
                "Thank you for your rating!",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "We're glad you're enjoying the app. Would you mind leaving a review on the Play Store?",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _launchPlayStore();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBg,
                        foregroundColor: primaryText,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Rate on Play Store",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: secondaryBg,
                        foregroundColor: context.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Maybe Later",
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdditionalOptions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Other ways to support",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildOptionTile(
            icon: Icons.share,
            title: "Share App",
            subtitle: "Share with friends and colleagues",
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _buildOptionTile(
            icon: Icons.contact_support,
            title: "Contact Support",
            subtitle: "Get help with the app",
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: context.iconSecondary, size: 20),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.iconSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchPlayStore() async {
    const packageName = 'com.yourcompany.startupexpensetracker';
    final Uri playStoreUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageName',
    );
    if (await canLaunchUrl(playStoreUri)) {
      await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open Play Store.',
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
              ),
            ),
            backgroundColor: context.cardBackground,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
