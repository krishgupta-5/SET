import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../services/bank_account_service.dart';
import '../../../services/team_member_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import '../team_widgets.dart';

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

        if (account.isNotEmpty && mounted) {
          setState(() => bankAccount = account);
        }
      }
    } catch (e) {
      debugPrint('❌ DEBUG: Error fetching bank account: $e');
    } finally {
      if (mounted) setState(() => isLoadingBankAccount = false);
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
      // Stored as 'BankName-last4'.
      final parts = bankAccountId.split('-');
      if (parts.length >= 2 && parts[0].isNotEmpty) {
        final last4 = BankAccountService.extractLast4(parts[1]);
        return last4.isNotEmpty ? '${parts[0]} ****$last4' : parts[0];
      }
      return bankAccountId;
    }

    // Check if it's a cash payment
    final paymentMethod = widget.transactionData['PaymentMethod'] as String?;
    if (paymentMethod == 'cash') {
      return 'Cash';
    }

    return 'Not specified';
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final data = widget.transactionData;
    final category =
        (data['Category'] as String? ?? data['category'] as String? ?? 'salary')
            .toString();
    final categoryLabel = category.isEmpty
        ? 'Salary'
        : category[0].toUpperCase() + category.substring(1);
    final description = (data['Title'] ?? '').toString();
    final isAdvance = widget.displayTitle.contains('Advance');

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: ''),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    MediaQuery.paddingOf(context).bottom + 32,
                  ),
                  children: [
                    RxReveal.index(
                      0,
                      child: Column(
                        children: [
                          RxIconTile(
                            icon: isAdvance
                                ? HugeIcons.strokeRoundedFastWind
                                : RxCategory.icon(category),
                            size: 52,
                            iconSize: 24,
                            background: isAdvance
                                ? rx.warningSoft
                                : RxCategory.soft(context, category),
                            foreground: isAdvance
                                ? rx.warning
                                : RxCategory.color(context, category),
                          ),
                          const SizedBox(height: 16),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.formattedAmount,
                              style: RxText.hero(context, size: 44),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.displayTitle,
                            textAlign: TextAlign.center,
                            style: RxText.label(context),
                          ),
                          const SizedBox(height: 12),
                          RxPill(
                            label: 'Completed',
                            dot: true,
                            foreground: rx.positive,
                            background: rx.positiveSoft,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    RxReveal.index(
                      1,
                      child: Column(
                        children: [
                          const RxSectionHeader(title: 'Details'),
                          RxCard(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(
                              children: [
                                RxDetailRow(
                                  label: 'Date',
                                  value: widget.formattedDate,
                                ),
                                const RxDivider(),
                                RxDetailRow(
                                  label: 'Category',
                                  value: categoryLabel,
                                ),
                                if (description.isNotEmpty) ...[
                                  const RxDivider(),
                                  RxDetailRow(
                                    label: 'Description',
                                    value: description,
                                  ),
                                ],
                                const RxDivider(),
                                RxDetailRow(
                                  label: 'Paid with',
                                  value: _getBankAccountDisplay(),
                                ),
                                if (_isLoadingLinkedMember ||
                                    _linkedMemberName != null) ...[
                                  const RxDivider(),
                                  _buildLinkedMemberRow(),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    RxReveal.index(
                      2,
                      child: RxCard(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.transactionId),
                          );
                          showRxToast(context, 'Transaction ID copied');
                        },
                        semanticLabel: 'Copy transaction ID',
                        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Transaction ID',
                                    style: RxText.label(context),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.transactionId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: RxText.caption(
                                      context,
                                      color: rx.textPrimary,
                                    ).copyWith(fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedCopy01,
                              color: rx.textSecondary,
                              size: 18,
                              strokeWidth: 1.8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedMemberRow() {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            _isFundingTransaction ? 'Added by' : 'Paid to',
            style: RxText.label(context),
          ),
          const Spacer(),
          if (_isLoadingLinkedMember)
            const RxSkeleton(width: 110, height: 16)
          else ...[
            _linkedMemberImageUrl != null
                ? MemberAvatar(
                    name: _linkedMemberName ?? '',
                    size: 26,
                    avatarUrl: _linkedMemberImageUrl,
                  )
                : MemberAvatar(name: _linkedMemberName ?? '', size: 26),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                _linkedMemberName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RxText.body(context, color: rx.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
