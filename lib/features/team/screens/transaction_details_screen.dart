import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/bank_account_service.dart';
import '../../../services/team_member_service.dart';
import '../../../../theme/app_theme.dart';

class TransactionDetailsScreen extends StatefulWidget {
  final String transactionId;
  final Map<String, dynamic> transactionData;
  final String formattedDate;
  final String formattedAmount;
  final String displayTitle;

  const TransactionDetailsScreen({
    super.key,
    required this.transactionId,
    required this.transactionData,
    required this.formattedDate,
    required this.formattedAmount,
    required this.displayTitle,
  });

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen> {
  Map<String, dynamic>? bankAccount;
  bool isLoadingBankAccount = true;

  // Linked member state
  String? _linkedMemberName;
  String? _linkedMemberImageUrl;
  bool _isLoadingLinkedMember = true;
  bool _isFundingTransaction = false;

  @override
  void initState() {
    super.initState();
    _fetchBankAccount();
    _fetchLinkedMember();
  }

  Future<void> _fetchBankAccount() async {
    try {
      // Check both possible field names for bank account
      final bankAccountId =
          widget.transactionData['bankAccount'] as String? ??
          widget.transactionData['BankAccount'] as String?;

      if (bankAccountId != null && bankAccountId.isNotEmpty) {
        final bankAccounts = await BankAccountService.getBankAccounts();

        final account = bankAccounts.firstWhere(
          (account) => account['id']?.toString() == bankAccountId,
          orElse: () => <String, dynamic>{},
        );

        if (account.isNotEmpty) {
          setState(() {
            bankAccount = account;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ DEBUG: Error fetching bank account: $e');
    } finally {
      setState(() {
        isLoadingBankAccount = false;
      });
    }
  }

  Future<void> _fetchLinkedMember() async {
    try {
      // Check if this is a funding transaction
      final isFunding = widget.transactionData['isFunding'] == true;

      if (isFunding) {
        // For funding transactions, show Owner with their profile image
        setState(() {
          _isFundingTransaction = true;
        });

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists && userDoc.data() != null) {
            final userData = userDoc.data()!;
            final ownerName =
                userData['name'] as String? ??
                userData['displayName'] as String? ??
                'Owner';
            final profileImageFileId =
                userData['profileImageFileId'] as String?;

            String? imageUrl;
            if (profileImageFileId != null && profileImageFileId.isNotEmpty) {
              try {
                imageUrl = await TeamMemberService.getTelegramImageUrl(
                  profileImageFileId,
                );
              } catch (e) {
                debugPrint('Error getting owner profile image: $e');
              }
            }

            if (mounted) {
              setState(() {
                _linkedMemberName = ownerName;
                _linkedMemberImageUrl = imageUrl;
              });
            }
          }
        }
      } else {
        // Check for linked member via memberId or TeamMemberId
        final memberId =
            widget.transactionData['memberId'] as String? ??
            widget.transactionData['TeamMemberId'] as String?;

        if (memberId != null && memberId.isNotEmpty) {
          final memberDoc = await FirebaseFirestore.instance
              .collection('members')
              .doc(memberId)
              .get();

          if (memberDoc.exists && memberDoc.data() != null) {
            final memberData = memberDoc.data()!;
            final memberName =
                memberData['fullName'] as String? ?? 'Unknown Member';
            final telegramFileId = memberData['telegramFileId'] as String?;

            String? imageUrl;
            if (telegramFileId != null && telegramFileId.isNotEmpty) {
              try {
                imageUrl = await TeamMemberService.getTelegramImageUrl(
                  telegramFileId,
                );
              } catch (e) {
                debugPrint('Error getting member image: $e');
              }
            }

            if (mounted) {
              setState(() {
                _linkedMemberName = memberName;
                _linkedMemberImageUrl = imageUrl;
              });
            }
          }
        } else {
          // Try TeamMemberName as fallback (stored inline)
          final memberName =
              widget.transactionData['TeamMemberName'] as String?;
          if (memberName != null && memberName.isNotEmpty) {
            if (mounted) {
              setState(() {
                _linkedMemberName = memberName;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching linked member: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLinkedMember = false;
        });
      }
    }
  }

  String _getBankAccountDisplay() {
    if (isLoadingBankAccount) {
      return 'Loading...';
    }
    if (bankAccount != null && bankAccount!.isNotEmpty) {
      final name = bankAccount!['name'] as String? ?? 'Unknown Bank';
      final last4 = bankAccount!['last4'] as String? ?? '****';
      return '$name ****$last4';
    }

    final bankAccountId =
        widget.transactionData['bankAccount'] as String? ??
        widget.transactionData['BankAccount'] as String?;

    if (bankAccountId != null) {
      // Check if it's a cash transaction (either "Cash-" or "Cash")
      if (bankAccountId == 'Cash-' || bankAccountId == 'Cash') {
        return 'Cash';
      }
      return 'Bank Account ID: $bankAccountId (Not Found)';
    }

    // Check if it's a cash payment
    final paymentMethod = widget.transactionData['PaymentMethod'] as String?;
    if (paymentMethod == 'cash') {
      return 'Cash';
    }

    return 'Not specified';
  }

  // Generate consistent color from name for fallback avatar
  Color _generateColorFromName(String name) {
    final int hash = name.hashCode;
    final List<Color> colors = [
      const Color(0xFF0A84FF),
      const Color(0xFF30D158),
      const Color(0xFFFF9F0A),
      const Color(0xFFA259FF),
      const Color(0xFFFF453A),
      const Color(0xFF5AC8FA),
      const Color(0xFFFFCC00),
      const Color(0xFFAF52DE),
    ];
    return colors[hash.abs() % colors.length];
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Transaction Details",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 28, // Compact Hero
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Clean Big Amount
                      Text(
                        widget.formattedAmount,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.5,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF30D158).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Completed",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: const Color(0xFF30D158),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Details Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              "Transaction Type",
                              widget.displayTitle,
                            ),
                            _buildDivider(),
                            _buildDetailRow(
                              "Date & Time",
                              widget.formattedDate,
                            ),
                            _buildDivider(),
                            // T-11: Read Category from the transaction doc
                            // instead of hardcoding "Salary" for all payments.
                            _buildDetailRow(
                              "Category",
                              widget.transactionData['Category'] as String? ??
                                  widget.transactionData['category']
                                      as String? ??
                                  'Salary',
                            ),
                            _buildDivider(),
                            _buildDetailRow(
                              "Description",
                              widget.transactionData['Title'] ?? 'N/A',
                            ),
                            _buildDivider(),
                            _buildDetailRow(
                              "Payment Method",
                              _getBankAccountDisplay(),
                            ),
                            _buildDivider(),
                            _buildLinkedMemberRow(),
                            _buildDivider(),
                            _buildDetailRow(
                              "Transaction ID",
                              widget.transactionId,
                              isId: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
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
          const SizedBox(
            width: 44,
          ), // To balance the back button and center the title
        ],
      ),
    );
  }

  Widget _buildLinkedMemberRow() {
    if (_isLoadingLinkedMember) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Linked Member",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final hasLinkedMember = _linkedMemberName != null;
    final displayName = _isFundingTransaction
        ? 'Owner'
        : (_linkedMemberName ?? 'None');
    final subtitle = _isFundingTransaction ? _linkedMemberName : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "Linked Member",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          if (hasLinkedMember)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile image or initials avatar
                _buildMemberAvatar(
                  _isFundingTransaction
                      ? (_linkedMemberName ?? 'O')
                      : _linkedMemberName!,
                  _linkedMemberImageUrl,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ],
            )
          else
            Text(
              "None",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(String name, String? imageUrl) {
    const double size = 32;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.borderColor, width: 1.5),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Fallback: initials avatar
    final color = _generateColorFromName(name);
    final initials = _getInitials(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isId = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: isId
                  ? GoogleFonts.robotoMono(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    )
                  : TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(color: context.borderColor, height: 1),
    );
  }
}
