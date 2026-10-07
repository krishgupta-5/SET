import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'edit_expense_screen.dart';
import 'file_viewer_screen.dart';
import '../../../utils/data_helpers.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/team_member_service.dart';
import '../../../theme/app_theme.dart';

class ExpenseDetailsScreen extends StatefulWidget {
  final String expenseId;
  final Map<String, dynamic> expenseData;

  const ExpenseDetailsScreen({
    super.key,
    required this.expenseId,
    required this.expenseData,
  });

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  String get _originalId => widget.expenseId.contains('_')
      ? widget.expenseId.split('_').first
      : widget.expenseId;
  String _userCountryCode = '+1'; // Default to USD
  bool _isLoadingCountry = true;

  // Linked member state
  String? _linkedMemberName;
  String? _linkedMemberImageUrl;
  String? _linkedTeamName;
  bool _isLoadingLinkedMember = true;
  bool _isFundingTransaction = false;

  // Holds the latest live expense data from the StreamBuilder
  // Used so that the Edit sheet always opens with up-to-date values.
  Map<String, dynamic> _currentExpenseData = {};

  // Cache the Telegram bot token so dotenv.load is only called once
  String? _telegramBotToken;

  Future<String?> _getBotToken() async {
    if (_telegramBotToken != null) return _telegramBotToken;
    await dotenv.load(fileName: '.env.local');
    _telegramBotToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
    return _telegramBotToken;
  }

  // ✅ Get Telegram file URL (uses cached token)
  Future<String> getTelegramImageUrl(String fileId) async {
    try {
      final botToken = await _getBotToken();
      if (botToken == null) throw Exception('Telegram bot token not found');

      final res = await http.get(
        Uri.parse(
          'https://api.telegram.org/bot$botToken/getFile?file_id=$fileId',
        ),
      );

      final data = jsonDecode(res.body);
      final path = data['result']['file_path'];

      return 'https://api.telegram.org/file/bot$botToken/$path';
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
    }
  }

  // ✅ Get Telegram file info (uses cached token)
  Future<Map<String, dynamic>?> getTelegramFileInfo(String fileId) async {
    try {
      final botToken = await _getBotToken();
      if (botToken == null) throw Exception('Telegram bot token not found');

      final res = await http.get(
        Uri.parse(
          'https://api.telegram.org/bot$botToken/getFile?file_id=$fileId',
        ),
      );

      final data = jsonDecode(res.body);
      return data['result'];
    } catch (e) {
      debugPrint('Error getting Telegram file info: $e');
      return null;
    }
  }

  // ✅ Check if file is likely an image based on file path
  bool isImageFile(String? filePath) {
    if (filePath == null) return false;
    final extension = filePath.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
  }

  // ✅ Get file icon based on file path
  IconData getFileIcon(String? filePath) {
    if (filePath == null) return Icons.insert_drive_file;

    final extension = filePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  void initState() {
    super.initState();
    // Get currency preference synchronously for instant display
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    // Listen for currency changes
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
    _fetchLinkedMember();
  }

  Future<void> _fetchLinkedMember() async {
    try {
      // We need to read the live expense data
      final expenseDoc = await FirebaseFirestore.instance
          .collection('expenses')
          .doc(_originalId)
          .get();

      final expenseData = expenseDoc.data() ?? widget.expenseData;

      // Check if this is a funding transaction
      final isFunding = expenseData['isFunding'] == true;

      if (isFunding) {
        setState(() => _isFundingTransaction = true);

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
        // Check for team name
        final teamName = expenseData['TeamName'] as String?;
        if (teamName != null && teamName.isNotEmpty) {
          if (mounted) {
            setState(() => _linkedTeamName = teamName);
          }
        }

        // Check for linked member via TeamMemberId or memberId
        final memberId =
            expenseData['TeamMemberId'] as String? ??
            expenseData['memberId'] as String?;

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
          final memberName = expenseData['TeamMemberName'] as String?;
          if (memberName != null && memberName.isNotEmpty) {
            if (mounted) {
              setState(() => _linkedMemberName = memberName);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching linked member: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLinkedMember = false);
      }
    }
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
        _userCountryCode =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
    }
  }

  Future<void> _loadUserCountryCode() async {
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted) {
      setState(() {
        _userCountryCode = currencyCode;
        _isLoadingCountry = false;
      });
    }
  }

  // --- UNIFIED MINIMAL TOAST ---
  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF30D158),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .doc(_originalId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: context.appBackground,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  context.textSecondary,
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: context.appBackground,
            body: Center(
              child: Text(
                'Error loading expense details',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: Colors.redAccent,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: context.appBackground,
            body: Center(
              child: Text(
                'Expense not found',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                ),
              ),
            ),
          );
        }

        final updatedExpenseData =
            snapshot.data!.data() as Map<String, dynamic>;
        // Keep _currentExpenseData in sync so the Edit sheet uses live data
        _currentExpenseData = updatedExpenseData;
        return _buildExpenseDetails(context, updatedExpenseData);
      },
    );
  }

  Widget _buildExpenseDetails(
    BuildContext context,
    Map<String, dynamic> rawExpenseData,
  ) {
    final Map<String, dynamic> expenseData = Map<String, dynamic>.from(
      rawExpenseData,
    );
    if (widget.expenseId.contains('_')) {
      final parts = widget.expenseId.split('_');
      final index = int.tryParse(parts.last) ?? 0;
      final frequency = (expenseData['recurrenceFrequency'] ?? 'monthly')
          .toString()
          .toLowerCase();
      final dateVal = expenseData['Date'] ?? expenseData['date'];
      if (dateVal != null) {
        DateTime startDate;
        if (dateVal is Timestamp) {
          startDate = dateVal.toDate();
        } else {
          startDate = dateVal as DateTime;
        }
        DateTime occurrenceDate;
        if (frequency == 'daily') {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month,
            startDate.day + index,
            startDate.hour,
            startDate.minute,
            startDate.second,
          );
        } else if (frequency == 'weekly') {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month,
            startDate.day + (index * 7),
            startDate.hour,
            startDate.minute,
            startDate.second,
          );
        } else if (frequency == 'monthly') {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month + index,
            startDate.day,
            startDate.hour,
            startDate.minute,
            startDate.second,
          );
        } else if (frequency == 'yearly') {
          occurrenceDate = DateTime(
            startDate.year + index,
            startDate.month,
            startDate.day,
            startDate.hour,
            startDate.minute,
            startDate.second,
          );
        } else {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month + index,
            startDate.day,
            startDate.hour,
            startDate.minute,
            startDate.second,
          );
        }
        expenseData['Date'] = Timestamp.fromDate(occurrenceDate);
        expenseData['date'] = Timestamp.fromDate(occurrenceDate);
      }
    }

    // Safely extract data from Firebase
    final title = expenseData['Title'] ?? 'Unnamed Expense';
    final amount = DataHelpers.safeParseDouble(expenseData['Amount']);
    final rawCategory = expenseData['Category']?.toString() ?? 'General';
    final category = rawCategory.toUpperCase();
    final rawType = expenseData['Type']?.toString() ?? 'one_time';
    final type = _formatType(rawType);
    final notes = expenseData['Description'] ?? 'No notes provided.';

    final isRecurringOrSub =
        rawType == 'recurring' || rawType == 'subscription';
    final frequency = expenseData['recurrenceFrequency']?.toString();
    final tenure = expenseData['recurringTenureMonths'] as int?;
    final frequencyStr = frequency != null ? _formatType(frequency) : 'Monthly';
    final tenureStr = tenure != null ? "$tenure Months" : "Ongoing";

    // Format Date and Time
    String dateStr = 'Unknown Date';
    String timeStr = '--:--';
    if (expenseData['Date'] is Timestamp) {
      final DateTime date = (expenseData['Date'] as Timestamp).toDate();
      dateStr = "${date.day}/${date.month}/${date.year}";
    }
    if (expenseData['Time'] is Timestamp) {
      final DateTime time = (expenseData['Time'] as Timestamp).toDate();
      // Simple 24h time formatting
      timeStr =
          "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
    }

    return Scaffold(
      backgroundColor: context.appBackground, // Theme Background
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              // 1. Header with Actions
              _buildHeader(context),

              // 2. Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        "Expense Details",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Hero Amount & Title
                      Center(
                        child: Column(
                          children: [
                            _buildCategoryBadge(category),
                            const SizedBox(height: 24),
                            // FIXED: FITTED BOX FOR LARGE NUMBERS
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isLoadingCountry
                                    ? CurrencyFormatter.formatCompact(
                                        amount,
                                        countryCode: '+91',
                                      )
                                    : CurrencyFormatter.formatByCountryCompact(
                                        amount,
                                        _userCountryCode,
                                      ),
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 48,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 48),

                      // --- DETAILS SECTION ---
                      _buildSectionLabel("DETAILS"),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Column(
                          children: [
                            _buildDetailRow("Date", dateStr),
                            _buildDivider(),
                            _buildDetailRow("Time", timeStr),
                            _buildDivider(),
                            _buildDetailRow('Type', type),
                            if (isRecurringOrSub) ...[
                              _buildDivider(),
                              _buildDetailRow('Frequency', frequencyStr),
                              _buildDivider(),
                              _buildDetailRow('Tenure', tenureStr),
                            ],
                            _buildDivider(),
                            _buildLinkedMemberRow(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // --- NOTES SECTION ---
                      _buildSectionLabel("NOTES"),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Text(
                          notes,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // --- ATTACHMENT SECTION ---
                      _buildSectionLabel("ATTACHMENT"),
                      const SizedBox(height: 16),
                      _buildAttachmentPreview(expenseData),

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

  // Helper method to format types like 'one_time' to 'One Time'
  String _formatType(String raw) {
    return raw
        .split('_')
        .map((word) {
          if (word.isEmpty) return '';
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  // Method to duplicate expense
  Future<void> _duplicateExpense(
    BuildContext context,
    Map<String, dynamic> expenseData,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (context.mounted) {
          _showMinimalToast("User not logged in", isError: true);
        }
        return;
      }

      // Get companyId from user document
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) throw Exception('Company not found');

      final id = const Uuid().v4();
      final amount = DataHelpers.safeParseDouble(expenseData['Amount']);
      final expenseType = expenseData['ExpenseType'] as String?;
      final teamId = expenseData['TeamId'] as String?;
      final teamMemberId = expenseData['TeamMemberId'] as String?;

      // If it is a member expense, validate remaining salary first
      if (expenseType == 'member' && teamMemberId != null) {
        final memberDoc = await FirebaseFirestore.instance
            .collection('members')
            .doc(teamMemberId)
            .get();
        if (memberDoc.exists) {
          final data = memberDoc.data() as Map<String, dynamic>;
          final salary = (data['salary'] as num?)?.toDouble() ?? 0.0;
          final totalExpenses =
              (data['totalExpenses'] as num?)?.toDouble() ?? 0.0;
          if (totalExpenses + amount > salary) {
            if (context.mounted) {
              _showMinimalToast(
                "Cannot duplicate: Expense amount exceeds remaining salary for ${data['fullName'] ?? 'member'}",
                isError: true,
              );
            }
            return;
          }
        }
      }

      // Use batch for atomic operations
      final batch = FirebaseFirestore.instance.batch();

      // Set new expense document
      final expenseRef = FirebaseFirestore.instance
          .collection('expenses')
          .doc(id);
      batch.set(expenseRef, {
        "uid": user.uid,
        "companyId": companyId,
        "Amount": amount,
        "Title": "${expenseData['Title'] ?? 'Expense'} (Copy)",
        "Description": expenseData['Description'] ?? '',
        "Date": DateTime.now(),
        "Category": expenseData['Category'] ?? 'general',
        "Type": expenseData['Type'] ?? 'one_time',
        "Time": FieldValue.serverTimestamp(),
        "ExpenseType": expenseType,
        "TeamId": teamId,
        if (expenseData['TeamName'] != null)
          "TeamName": expenseData['TeamName'],
        "TeamMemberId": teamMemberId,
        if (expenseData['TeamMemberName'] != null)
          "TeamMemberName": expenseData['TeamMemberName'],
        if (expenseData['BankAccount'] != null)
          "BankAccount": expenseData['BankAccount'],
        if (expenseData['memberId'] != null)
          "memberId": expenseData['memberId'],
      });

      // Update totalExpenses atomically
      final companyRef = FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId);
      batch.update(companyRef, {"totalExpenses": FieldValue.increment(amount)});

      // Update team budget or member salary atomically
      if (expenseType == 'team' && teamId != null) {
        final teamRef = FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId);
        batch.update(teamRef, {"usedBudget": FieldValue.increment(amount)});
      } else if (expenseType == 'member' && teamMemberId != null) {
        final memberRef = FirebaseFirestore.instance
            .collection('members')
            .doc(teamMemberId);
        batch.update(memberRef, {
          "totalExpenses": FieldValue.increment(amount),
          "remainingSalary": FieldValue.increment(-amount),
        });
      }

      // Commit batch atomically
      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // Close bottom sheet
        _showMinimalToast("Expense duplicated successfully");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close bottom sheet
        _showMinimalToast("Failed to duplicate expense", isError: true);
      }
    }
  }

  Future<void> _deleteExpense() async {
    try {
      final currentData = _currentExpenseData.isNotEmpty
          ? _currentExpenseData
          : widget.expenseData;
      final expenseAmount = DataHelpers.safeParseDouble(currentData['Amount']);
      final expenseType = currentData['ExpenseType'] as String?;
      final teamId = currentData['TeamId'] as String?;
      final teamMemberId = currentData['TeamMemberId'] as String?;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Get companyId from user document
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) {
        throw Exception('Company not found');
      }

      final batch = FirebaseFirestore.instance.batch();

      // Delete expense document
      final expenseRef = FirebaseFirestore.instance
          .collection('expenses')
          .doc(_originalId);
      batch.delete(expenseRef);

      // Atomically decrement company totalExpenses.
      // Guard against going negative by running a transaction instead.
      final companyRef = FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId);

      // We still need a read to clamp — use a transaction for this one write.
      // For the rest of the batch writes we use increment which is safe.
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(companyRef);
        final current = DataHelpers.safeParseDouble(
          snap.data()?['totalExpenses'],
        );
        final newVal = (current - expenseAmount).clamp(0.0, double.infinity);
        txn.update(companyRef, {'totalExpenses': newVal});
      });

      // Update team budget or member salary atomically
      if (expenseType == 'team' && teamId != null) {
        final teamRef = FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId);
        batch.update(teamRef, {
          'usedBudget': FieldValue.increment(-expenseAmount),
        });
      } else if (expenseType == 'member' && teamMemberId != null) {
        final memberRef = FirebaseFirestore.instance
            .collection('members')
            .doc(teamMemberId);
        batch.update(memberRef, {
          'totalExpenses': FieldValue.increment(-expenseAmount),
          'remainingSalary': FieldValue.increment(expenseAmount),
        });
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context); // Go back to the list screen
        _showMinimalToast("Expense deleted");
      }
    } catch (e) {
      debugPrint("Failed to delete expense: $e");
      if (mounted) {
        _showMinimalToast("Failed to delete expense", isError: true);
      }
    }
  }

  // --- GORGEOUS CUSTOM DELETE DIALOG ---
  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8), // Darken backdrop
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cardBackground, // Match theme
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon & Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF453A).withValues(alpha: 0.1),
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
                        "Delete Expense?",
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
                // Warning Text
                Text(
                  "This will permanently delete this expense record and reverse it from your total company expenses. This action cannot be undone.",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(dialogContext),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: context.appBackground,
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
                        onTap: () async {
                          Navigator.pop(dialogContext); // Close dialog
                          await _deleteExpense(); // Execute deletion
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF453A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Delete",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: Colors.white,
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
  }

  // --- ACTIONS BOTTOM SHEET ---
  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Manage Expense",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                _buildActionOption(
                  icon: Icons.edit_outlined,
                  label: "Edit Expense",
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditExpenseScreen(
                          expenseId: _originalId,
                          // Use the live-streamed data, fall back to constructor data
                          expenseData: _currentExpenseData.isNotEmpty
                              ? _currentExpenseData
                              : widget.expenseData,
                        ),
                      ),
                    );
                  },
                ),
                _buildActionOption(
                  icon: Icons.copy_rounded,
                  label: "Duplicate",
                  onTap: () {
                    Navigator.pop(bottomSheetContext); // Close sheet
                    _duplicateExpense(
                      context,
                      _currentExpenseData.isNotEmpty
                          ? _currentExpenseData
                          : widget.expenseData,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Divider(color: context.borderColor, height: 1),
                const SizedBox(height: 16),
                _buildActionOption(
                  icon: Icons.delete_outline_rounded,
                  label: "Delete Expense",
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(bottomSheetContext); // Close sheet
                    _showDeleteConfirmation(context); // Open delete dialog
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- WIDGET BUILDERS ---

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
          // Actions Menu Button
          GestureDetector(
            onTap: () => _showOptionsBottomSheet(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
                boxShadow: context.cardShadow,
              ),
              child: Icon(
                Icons.more_horiz,
                color: context.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pie_chart_outline, color: context.textSecondary, size: 14),
          const SizedBox(width: 6),
          Text(
            category,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
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

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
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

  Widget _buildMemberAvatar(String name, String? imageUrl, {double size = 32}) {
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
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedMemberRow() {
    if (_isLoadingLinkedMember) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Linked Member",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: context.textSecondary,
            ),
          ),
        ],
      );
    }

    final hasLinkedMember = _linkedMemberName != null;
    final hasLinkedTeam = _linkedTeamName != null;

    // Determine display values
    String displayLabel;
    String displayName;
    String? subtitle;
    String avatarName;

    if (_isFundingTransaction) {
      displayLabel = "Linked Member";
      displayName = "Owner";
      subtitle = _linkedMemberName;
      avatarName = _linkedMemberName ?? 'Owner';
    } else if (hasLinkedMember && hasLinkedTeam) {
      displayLabel = "Linked Member";
      displayName = _linkedMemberName!;
      subtitle = _linkedTeamName;
      avatarName = _linkedMemberName!;
    } else if (hasLinkedMember) {
      displayLabel = "Linked Member";
      displayName = _linkedMemberName!;
      avatarName = _linkedMemberName!;
    } else if (hasLinkedTeam) {
      displayLabel = "Linked Team";
      displayName = _linkedTeamName!;
      avatarName = _linkedTeamName!;
    } else {
      // No linked member or team
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Linked Member",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            "None",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          displayLabel,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMemberAvatar(avatarName, _linkedMemberImageUrl),
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
                    fontSize: 14,
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
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(color: context.borderColor, height: 1),
    );
  }

  Widget _buildAttachmentPreview(Map<String, dynamic> expenseData) {
    final attachmentFileId = expenseData['AttachmentFileId'] as String?;

    if (attachmentFileId == null || attachmentFileId.isEmpty) {
      // No attachment
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
          boxShadow: context.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.description,
                color: context.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "No receipt attached",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "0 KB",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Has attachment - show actual file preview
    return FutureBuilder<Map<String, dynamic>?>(
      future: getTelegramFileInfo(attachmentFileId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF30D158).withValues(alpha: 0.3),
              ),
              boxShadow: context.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF30D158).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.receipt,
                        color: Color(0xFF30D158),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Loading receipt...",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: const Color(0xFF30D158),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "Fetching from Telegram",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF30D158),
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFFF453A).withValues(alpha: 0.3),
              ),
              boxShadow: context.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF453A).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.error_outline,
                        color: Color(0xFFFF453A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Failed to load receipt",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: const Color(0xFFFF453A),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "Could not fetch from Telegram",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      "Preview unavailable",
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final fileInfo = snapshot.data!;
        final filePath = fileInfo['file_path'] as String?;
        final fileName = filePath?.split('/').last ?? 'receipt';
        final fileSize = fileInfo['file_size'] as int? ?? 0;
        final isImage = isImageFile(filePath);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF30D158).withValues(alpha: 0.3),
            ),
            boxShadow: context.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF30D158).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      getFileIcon(filePath),
                      color: const Color(0xFF30D158),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Receipt attached",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: const Color(0xFF30D158),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "${(fileSize / 1024).toStringAsFixed(1)} KB • Stored in Telegram",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Download button
                  GestureDetector(
                    onTap: () async {
                      try {
                        final fileInfo = await getTelegramFileInfo(
                          attachmentFileId,
                        );
                        if (!context.mounted) return;
                        if (fileInfo != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FileViewerScreen(
                                fileId: attachmentFileId,
                                fileName:
                                    fileInfo['file_path']?.split('/').last ??
                                    'receipt',
                                filePath: fileInfo['file_path'],
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint("Error opening file viewer: $e");
                        if (mounted) {
                          _showMinimalToast(
                            "Failed to open file",
                            isError: true,
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.appBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.visibility,
                        color: context.textSecondary,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // File preview
              if (isImage && filePath != null)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      "https://api.telegram.org/file/bot${dotenv.env['TELEGRAM_BOT_TOKEN']}/$filePath",
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: context.appBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              "Failed to load image preview",
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: context.appBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF30D158),
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              else
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          getFileIcon(filePath),
                          color: context.textSecondary,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fileName,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Tap the download icon to view",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- WHITE GLASS ACTION SHEET BUTTONS ---
  Widget _buildActionOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFFF453A).withValues(alpha: 0.1)
              : context.appBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDestructive
                ? const Color(0xFFFF453A).withValues(alpha: 0.2)
                : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive
                  ? const Color(0xFFFF453A)
                  : context.textPrimary,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: isDestructive
                    ? const Color(0xFFFF453A)
                    : context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
