import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'currency_formatter.dart';
import 'currency_preference_service.dart';

/// Service for managing bank accounts with production-grade subcollection model
///
/// Uses stable IDs from Firestore subcollection instead of fragile array-based
/// matching for proper fintech architecture.
class BankAccountService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 🔥 PRODUCTION FIX: Get all bank accounts from subcollection with stable IDs
  static Future<List<Map<String, dynamic>>> getBankAccounts() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      debugPrint('🔍 DEBUG: Fetching bank accounts for user: ${user.uid}');

      // ✅ FIX: Get companyId from user document first
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      debugPrint('🔍 DEBUG: User document exists: ${userDoc.exists}');

      if (userDoc.exists && userDoc.data() != null) {
        debugPrint('🔍 DEBUG: User document data: ${userDoc.data()}');
      }

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) {
        debugPrint('🔍 DEBUG: No companyId found for user: ${user.uid}');
        debugPrint(
          '🔍 DEBUG: Available fields in user doc: ${userDoc.data()?.keys.toList()}',
        );

        // Try fallback to user.uid as companyId
        debugPrint('🔍 DEBUG: Trying fallback with user.uid as companyId');
        return await _getBankAccountsWithCompanyId(user.uid);
      }

      debugPrint('🔍 DEBUG: Using companyId: $companyId');
      return await _getBankAccountsWithCompanyId(companyId);
    } catch (e) {
      debugPrint('❌ DEBUG: Error fetching bank accounts: $e');
      debugPrint('❌ DEBUG: Error stack trace: ${StackTrace.current}');
      throw Exception('Failed to fetch bank accounts: $e');
    }
  }

  /// Helper method to get bank accounts with a specific companyId
  static Future<List<Map<String, dynamic>>> _getBankAccountsWithCompanyId(
    String companyId,
  ) async {
    try {
      debugPrint('🔍 DEBUG: Getting bank accounts for companyId: $companyId');

      // First try subcollection (new model)
      final subcollectionAccounts = await _getBankAccountsFromSubcollection(
        companyId,
      );
      if (subcollectionAccounts.isNotEmpty) {
        debugPrint(
          '🔍 DEBUG: Found ${subcollectionAccounts.length} accounts in subcollection',
        );
        return subcollectionAccounts;
      }

      debugPrint(
        '🔍 DEBUG: No accounts in subcollection, checking company document array...',
      );

      // Fallback to company document array (from company setup)
      final arrayAccounts = await _getBankAccountsFromCompanyArray(companyId);
      if (arrayAccounts.isNotEmpty) {
        debugPrint(
          '🔍 DEBUG: Found ${arrayAccounts.length} accounts in company array',
        );
        return arrayAccounts;
      }

      debugPrint('🔍 DEBUG: No bank accounts found anywhere');
      return [];
    } catch (e) {
      debugPrint('❌ DEBUG: Error in _getBankAccountsWithCompanyId: $e');
      return [];
    }
  }

  /// Get bank accounts from subcollection (new model)
  static Future<List<Map<String, dynamic>>> _getBankAccountsFromSubcollection(
    String companyId,
  ) async {
    try {
      // Try subcollection first (new model) - remove orderBy to avoid index requirement
      final bankAccountsSnapshot = await _firestore
          .collection("companies")
          .doc(companyId)
          .collection("bankAccounts")
          .where('isActive', isEqualTo: true)
          .get();

      debugPrint(
        '🔍 DEBUG: Subcollection snapshot found: ${bankAccountsSnapshot.docs.length} documents',
      );

      if (bankAccountsSnapshot.docs.isNotEmpty) {
        // Sort client-side by createdAt (newest first)
        final sortedDocs = bankAccountsSnapshot.docs.toList();
        sortedDocs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime); // Descending order
        });

        final accounts = sortedDocs
            .map((doc) => _processBankAccountDocument(doc))
            .toList();
        return accounts;
      }
      return [];
    } catch (e) {
      debugPrint('❌ DEBUG: Error getting subcollection accounts: $e');
      return [];
    }
  }

  /// Get bank accounts from company document array (company setup model)
  static Future<List<Map<String, dynamic>>> _getBankAccountsFromCompanyArray(
    String companyId,
  ) async {
    try {
      final companyDoc = await _firestore
          .collection("companies")
          .doc(companyId)
          .get();

      if (!companyDoc.exists || companyDoc.data() == null) {
        debugPrint('🔍 DEBUG: No company document found');
        return [];
      }

      final data = companyDoc.data()!;
      debugPrint('🔍 DEBUG: Company document keys: ${data.keys.toList()}');

      // Check for different possible field names for bank accounts array
      final bankAccountsData =
          data["Bank Accounts"] as List<dynamic>? ??
          data["bankAccounts"] as List<dynamic>? ??
          data["bank_accounts"] as List<dynamic>? ??
          [];

      debugPrint(
        '🔍 DEBUG: Found ${bankAccountsData.length} bank accounts in company array',
      );

      if (bankAccountsData.isEmpty) {
        return [];
      }

      final accounts = bankAccountsData
          .map((accountData) {
            // Handle the format from company setup
            if (accountData is Map<String, dynamic>) {
              return _processCompanyArrayBankAccount(accountData);
            }
            return <String, dynamic>{};
          })
          .where((account) => account.isNotEmpty)
          .toList();

      return accounts;
    } catch (e) {
      debugPrint('❌ DEBUG: Error getting company array accounts: $e');
      return [];
    }
  }

  /// Process bank account document from subcollection
  static Map<String, dynamic> _processBankAccountDocument(
    DocumentSnapshot doc,
  ) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      debugPrint('🔍 DEBUG: Document data is null');
      return {};
    }

    debugPrint('🔍 DEBUG: Full bank account document data: $data');
    debugPrint('🔍 DEBUG: Document ID: ${doc.id}');
    debugPrint('🔍 DEBUG: Available fields: ${data.keys.toList()}');

    // Show all string fields that could be the bank name
    final possibleNameFields = <String, String>{};
    data.forEach((key, value) {
      if (value is String && value.isNotEmpty) {
        possibleNameFields[key] = value;
        debugPrint('🔍 DEBUG: String field - $key: "$value"');
      }
    });

    // Try different possible field names for the bank name
    String bankName =
        data['name']?.toString() ??
        data['bankName']?.toString() ??
        data['bank_name']?.toString() ??
        data['accountName']?.toString() ??
        data['account_name']?.toString() ??
        data['title']?.toString() ??
        data['displayName']?.toString() ??
        data['display_name']?.toString() ??
        data['institution']?.toString() ??
        data['bank']?.toString() ??
        'Unknown Bank';

    // If still unknown, try to use the first non-empty string field
    if (bankName == 'Unknown Bank' && possibleNameFields.isNotEmpty) {
      final firstField = possibleNameFields.entries.first;
      bankName = firstField.value;
      debugPrint(
        '🔍 DEBUG: Using fallback field "${firstField.key}" with value: "$bankName"',
      );
    }

    // Clean up the bank name - capitalize properly and handle "unknown bank"
    if (bankName.toLowerCase() == 'unknown bank') {
      bankName = 'Bank Account';
    } else {
      // Capitalize first letter of each word
      bankName = bankName
          .split(' ')
          .map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          })
          .join(' ');
    }

    debugPrint('🔍 DEBUG: Cleaned bank name: "$bankName"');
    debugPrint('🔍 DEBUG: All possible name fields: $possibleNameFields');

    // Also check for account number fields
    final accountNumber =
        data['number']?.toString() ??
        data['accountNumber']?.toString() ??
        data['account_number']?.toString() ??
        data['account']?.toString() ??
        '';

    debugPrint('🔍 DEBUG: Account number: "$accountNumber"');

    // Handle last4 digits properly - always extract only last 4 digits
    String last4 = data['last4']?.toString() ?? '';
    if (last4.isEmpty && accountNumber.isNotEmpty) {
      last4 = extractLast4(accountNumber);
    } else if (last4.isNotEmpty) {
      // Even if last4 exists, ensure it's only 4 digits
      last4 = extractLast4(last4);
    }

    // If still no last4, use a default
    if (last4.isEmpty) {
      last4 = '****';
      debugPrint('🔍 DEBUG: No account number available, using default last4');
    }

    debugPrint('🔍 DEBUG: Final last4: "$last4"');

    return {
      'id': data['id']?.toString() ?? doc.id,
      'name': bankName,
      'number': accountNumber,
      'last4': last4,
      'maskedNumber':
          data['maskedNumber']?.toString() ??
          _maskAccountNumber(accountNumber.isNotEmpty ? accountNumber : '****'),
      'createdAt': data['createdAt'],
      'isActive': data['isActive'] ?? true,
      'legacyKey':
          '${bankName.toUpperCase()}-$last4', // Add legacyKey for matching with expenses
    };
  }

  /// Process bank account from company array (company setup format)
  static Map<String, dynamic> _processCompanyArrayBankAccount(
    Map<String, dynamic> accountData,
  ) {
    debugPrint('🔍 DEBUG: Processing company array bank account: $accountData');

    // Company setup uses either "bankName" or "name" field
    String bankName =
        accountData['bankName'] ??
        accountData['name'] ??
        accountData['bank_name'] ??
        'Unknown Bank';

    // Clean up the bank name
    if (bankName.toLowerCase() == 'unknown bank') {
      bankName = 'Bank Account';
    } else {
      bankName = bankName
          .split(' ')
          .map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          })
          .join(' ');
    }

    final String rawLast4 = accountData['last4']?.toString() ?? '';

    // Handle account number - could be in various fields
    String accountNumber =
        accountData['number']?.toString() ??
        accountData['accountNumber']?.toString() ??
        accountData['account_number']?.toString() ??
        accountData['account']?.toString() ??
        '';
    if (accountNumber.isEmpty && rawLast4.isNotEmpty) {
      accountNumber = rawLast4; // Use last4 as account number fallback
    }

    // Extract last 4 digits properly
    final String last4 = rawLast4.isNotEmpty
        ? extractLast4(rawLast4)
        : (accountNumber.isNotEmpty ? extractLast4(accountNumber) : '****');

    debugPrint(
      '🔍 DEBUG: Company array bank - Name: "$bankName", Last4: "$last4", AccountNumber: "$accountNumber"',
    );

    // For masking, always use the available number (full account number or last4)
    final String numberToMask = accountNumber.isNotEmpty
        ? accountNumber
        : rawLast4;

    return {
      'id':
          'company_array_${bankName}_$last4', // More stable ID using bank name and last4
      'name': bankName,
      'number': accountNumber,
      'last4': last4,
      'maskedNumber': _maskAccountNumber(
        numberToMask.isNotEmpty ? numberToMask : '****',
      ),
      'createdAt': DateTime.now(), // Use current time as fallback
      'isActive': true,
      'legacyKey':
          '${bankName.toUpperCase()}-$last4', // Add legacyKey for matching with expenses
    };
  }

  /// 🔥 PRODUCTION FIX: Calculate spending for each bank account using stable ID matching
  /// Also accumulates Cash expenses and returns a virtual "Cash" account entry.
  static Future<List<Map<String, dynamic>>> getBankAccountsWithSpending(
    List<Map<String, dynamic>> expenses,
  ) async {
    final bankAccounts = await getBankAccounts();

    // Initialize spending map with stable IDs
    final Map<String, double> bankSpending = {};
    for (var account in bankAccounts) {
      bankSpending[account['id']] = 0.0;
    }

    // Track cash spending separately
    double cashSpending = 0.0;

    // Calculate actual spending for each bank account from expenses
    for (var expense in expenses) {
      final amount =
          (expense['amount'] as num?)?.toDouble() ??
          (expense['Amount'] as num?)?.toDouble() ??
          0.0;
      final expenseBankAccount = expense['bankAccount'] as String?;
      final expenseTitle =
          expense['title'] as String? ??
          expense['Title'] as String? ??
          'Unknown';

      debugPrint(
        '🔍 DEBUG: Processing expense - Title: "$expenseTitle", Amount: $amount, BankAccount: "$expenseBankAccount"',
      );

      if (expenseBankAccount != null) {
        // ✅ Identify Cash transactions and track them separately
        final normalizedAccount = expenseBankAccount.trim().toLowerCase();
        final isCashTransaction =
            normalizedAccount == 'cash' || normalizedAccount == 'cash-';

        if (isCashTransaction) {
          // Accumulate cash spending separately
          if (amount > 0) {
            cashSpending += amount;
            debugPrint(
              '🔍 DEBUG: Cash expense "$expenseTitle" - Added $amount (cash total: $cashSpending)',
            );
          }
        } else {
          // Try stable ID match first (new format)
          final matchedAccount = bankAccounts.firstWhere(
            (account) => account['id'] == expenseBankAccount,
            orElse: () =>
                _findAccountByLegacyKey(bankAccounts, expenseBankAccount),
          );

          debugPrint(
            '🔍 DEBUG: Matched account for expense "$expenseTitle": ${matchedAccount['id']} (${matchedAccount['name']})',
          );

          if (matchedAccount['id'] != null) {
            // 🔥 PRODUCTION FIX: Only count real outflows (positive amounts)
            // Exclude refunds, revenue, and credits from "total spent"
            if (amount > 0) {
              bankSpending[matchedAccount['id']] =
                  (bankSpending[matchedAccount['id']] ?? 0.0) + amount;
              debugPrint(
                '🔍 DEBUG: Added $amount to ${matchedAccount['name']} (total: ${bankSpending[matchedAccount['id']]})',
              );
            }
          } else {
            debugPrint(
              '🔍 DEBUG: No matching account found for expense "$expenseTitle" with bankAccount: "$expenseBankAccount"',
            );
          }
        }
      } else {
        debugPrint(
          '🔍 DEBUG: Expense "$expenseTitle" has no bankAccount field',
        );
      }
    }

    // Build result: bank accounts with calculated spending
    final result = bankAccounts.map((account) {
      return {...account, 'totalSpent': bankSpending[account['id']] ?? 0.0};
    }).toList();

    // ✅ Append a virtual "Cash" account entry if there is any cash spending
    if (cashSpending > 0) {
      debugPrint(
        '🔍 DEBUG: Adding virtual Cash account with total spending: $cashSpending',
      );
      result.add({
        'id': null, // null = no delete button shown in UI
        'isCash': true, // flag for special Cash UI treatment
        'name': 'Cash',
        'number': '',
        'last4': '',
        'maskedNumber': 'Cash Payments',
        'totalSpent': cashSpending,
        'isActive': true,
        'legacyKey': 'Cash-',
      });
    }

    return result;
  }

  /// 🔥 PRODUCTION FIX: Migrate expense bank account references to stable IDs
  static Future<void> migrateExpenseBankAccountReferences() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // Get all bank accounts with stable IDs
      final bankAccounts = await getBankAccounts();

      // Get all expenses
      final expensesSnapshot = await _firestore
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .get();

      // Batch update expenses to use stable IDs
      final batch = _firestore.batch();

      for (var doc in expensesSnapshot.docs) {
        final data = doc.data();
        final currentBankAccount = data['BankAccount'] as String?;

        if (currentBankAccount != null) {
          // Find matching bank account
          final matchedAccount = bankAccounts.firstWhere(
            (account) => account['legacyKey'] == currentBankAccount,
            orElse: () => {'id': null},
          );

          if (matchedAccount['id'] != null) {
            // Update to use stable ID
            batch.update(doc.reference, {
              'BankAccount': matchedAccount['id'],
              'bankAccountId': matchedAccount['id'], // New field for clarity
            });
          }
        }
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to migrate expense bank references: $e');
    }
  }

  /// Find account by legacy key for backward compatibility
  static Map<String, dynamic> _findAccountByLegacyKey(
    List<Map<String, dynamic>> accounts,
    String legacyKey,
  ) {
    try {
      // First try exact legacyKey match
      final exactMatch = accounts.firstWhere(
        (account) => account['legacyKey'] == legacyKey,
        orElse: () => {'id': null},
      );

      if (exactMatch['id'] != null) {
        return exactMatch;
      }

      // If no exact match, try to match by extracting bank name and last4 from legacyKey
      // Handle formats like "ICICI Bank-4321" or "HDFC BANK-3037"
      final parts = legacyKey.split('-');
      if (parts.length >= 2) {
        final bankName = parts.sublist(0, parts.length - 1).join('-').trim();
        final last4 = parts.last.trim();

        debugPrint(
          '🔍 DEBUG: Trying to match by bankName: "$bankName", last4: "$last4"',
        );

        // Try to find account by matching bank name (case-insensitive) and last4
        final fuzzyMatch = accounts.firstWhere((account) {
          final accountName = account['name']?.toString().toLowerCase() ?? '';
          final accountLast4 = account['last4']?.toString() ?? '';
          final searchName = bankName.toLowerCase();

          debugPrint(
            '🔍 DEBUG: Comparing "$accountName" with "$searchName" and "$accountLast4" with "$last4"',
          );

          return accountName.contains(searchName) ||
              searchName.contains(accountName);
        }, orElse: () => {'id': null});

        if (fuzzyMatch['id'] != null) {
          debugPrint(
            '🔍 DEBUG: Found fuzzy match: ${fuzzyMatch['name']} with last4: ${fuzzyMatch['last4']}',
          );
          return fuzzyMatch;
        }
      }

      return {'id': null};
    } catch (e) {
      debugPrint('🔍 DEBUG: Error in _findAccountByLegacyKey: $e');
      return {'id': null};
    }
  }

  /// Extract last 4 digits from account number
  static String extractLast4(String accountNumber) {
    if (accountNumber.length <= 4) return accountNumber;
    return accountNumber.substring(accountNumber.length - 4);
  }

  /// Mask account number for display - show only last 4 digits
  static String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length <= 4) {
      return '****$accountNumber'; // Always mask even short numbers
    }
    final last4 = accountNumber.substring(accountNumber.length - 4);
    return '****$last4';
  }

  /// Format currency consistently across the app
  static String formatCurrency(double value, {String? countryCode}) {
    // Use user's preferred currency if no country code is provided
    final effectiveCountryCode =
        countryCode ?? CurrencyPreferenceService.getCurrencyPreferenceSync();
    return CurrencyFormatter.formatByCountry(value, effectiveCountryCode);
  }
}
