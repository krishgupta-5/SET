import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for managing strictly formatted data collections for the 10 UI Sections
class AIService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Fetches base data ONCE, extracts ONLY the requested fields,
  /// and syncs them into 10 cleanly separated sub-collections.
  static Future<void> syncAICollections() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    final uid = user.uid;

    // Define time boundaries
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 6, 1);
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);
    final twoMonthsAgo = DateTime(now.year, now.month - 1, 1);
    final startOfCurrentMonth = DateTime(now.year, now.month, 1);

    // 1. FETCH BASE DATA ONCE (Max bounds to minimize reads)
    final futures = await Future.wait([
      _firestore
          .collection('expenses')
          .where('uid', isEqualTo: uid)
          .where(
            'Date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(sixMonthsAgo),
          )
          .get(),
      _firestore
          .collection('revenue')
          .where('uid', isEqualTo: uid)
          .where(
            'Date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(sixMonthsAgo),
          )
          .get(),
      _firestore.collection('members').where('uid', isEqualTo: uid).get(),
      _firestore.collection('teams').where('uid', isEqualTo: uid).get(),
      _firestore.collection('users').doc(uid).get(),
    ]);

    final expensesDocs = (futures[0] as QuerySnapshot).docs;
    final revenueDocs = (futures[1] as QuerySnapshot).docs;
    final membersDocs = (futures[2] as QuerySnapshot).docs;
    final teamsDocs = (futures[3] as QuerySnapshot).docs;
    final userDoc = futures[4] as DocumentSnapshot;

    // Fetch Company & Bank Accounts
    final companyId = (userDoc.data() as Map<String, dynamic>?)?['companyId'];
    Map<String, dynamic> companyData = {};
    List<Map<String, dynamic>> bankAccounts = [];

    if (companyId != null) {
      final companyDoc = await _firestore
          .collection('companies')
          .doc(companyId)
          .get();
      if (companyDoc.exists) {
        companyData = companyDoc.data() as Map<String, dynamic>;
      }

      final banksSnapshot = await _firestore
          .collection('companies')
          .doc(companyId)
          .collection('bankAccounts')
          .where('isActive', isEqualTo: true)
          .get();
      bankAccounts = banksSnapshot.docs
          .map((doc) => _extractFields(doc.data(), ['name', 'isActive']))
          .toList();
    }

    // 2. HELPER METHODS FOR STRICT FIELD FILTERING
    List<Map<String, dynamic>> filterExpenses(
      DateTime since,
      List<String> fields, {
      String? type,
      String? category,
    }) {
      return expensesDocs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp).toDate();
            if (date.isBefore(since)) return false;
            if (type != null && data['Type'] != type) return false;
            if (category != null && data['Category'] != category) return false;
            return true;
          })
          .map(
            (doc) => _extractFields(doc.data() as Map<String, dynamic>, fields),
          )
          .toList();
    }

    List<Map<String, dynamic>> filterRevenue(
      DateTime since,
      List<String> fields,
    ) {
      return revenueDocs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp).toDate();
            return !date.isBefore(since);
          })
          .map(
            (doc) => _extractFields(doc.data() as Map<String, dynamic>, fields),
          )
          .toList();
    }

    List<Map<String, dynamic>> extractFromDocs(
      List<QueryDocumentSnapshot> docs,
      List<String> fields,
    ) {
      return docs
          .map(
            (doc) => _extractFields(doc.data() as Map<String, dynamic>, fields),
          )
          .toList();
    }

    // 3. PREPARE THE BATCH WRITE
    final batch = _firestore.batch();
    final aiMainRef = _firestore
        .collection('ai')
        .doc(uid); // Centralize under UID

    batch.set(aiMainRef, {
      'uid': uid,
      'lastSynced': FieldValue.serverTimestamp(),
      'status': 'updated',
    }, SetOptions(merge: true));

    // -- Section 1: Primary Insight
    batch.set(aiMainRef.collection('primary_insight').doc('data'), {
      'expenses': filterExpenses(sixMonthsAgo, [
        'Amount',
        'Category',
        'Date',
        'Type',
      ]),
      'company': _extractFields(companyData, [
        'Funding',
        'totalExpenses',
        'Runway',
      ]),
      'members': extractFromDocs(membersDocs, ['salary', 'status']),
      'revenue': filterRevenue(sixMonthsAgo, ['Amount', 'Date']),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 2: Key Recommendations
    batch.set(aiMainRef.collection('key_recommendations').doc('data'), {
      'expenses': filterExpenses(twoMonthsAgo, [
        'Amount',
        'Category',
        'Title',
        'Type',
        'Date',
      ]),
      'company': _extractFields(companyData, ['budgets', 'totalExpenses']),
      'teams': extractFromDocs(teamsDocs, [
        'teamName',
        'monthlyBudget',
        'usedBudget',
      ]),
      'members': extractFromDocs(membersDocs, [
        'salary',
        'totalExpenses',
        'status',
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 3: Runway Optimization
    batch.set(aiMainRef.collection('runway_optimization').doc('data'), {
      'expenses': filterExpenses(sixMonthsAgo, [
        'Amount',
        'Category',
        'Date',
        'Type',
      ]),
      'company': _extractFields(companyData, [
        'Funding',
        'totalExpenses',
        'Runway',
      ]),
      'members': extractFromDocs(membersDocs, ['salary', 'status']),
      'revenue': filterRevenue(sixMonthsAgo, ['Amount', 'Date']),
      'teams': extractFromDocs(teamsDocs, ['teamName', 'monthlyBudget']),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 4: Investment Strategy
    batch.set(aiMainRef.collection('investment_strategy').doc('data'), {
      'expenses': filterExpenses(sixMonthsAgo, [
        'Amount',
        'Category',
        'Date',
        'Type',
      ]),
      'company': _extractFields(companyData, [
        'Funding',
        'totalExpenses',
        'Runway',
        'budgets',
      ]),
      'members': extractFromDocs(membersDocs, ['salary', 'status']),
      'revenue': filterRevenue(sixMonthsAgo, ['Amount', 'Date']),
      'bankAccounts': bankAccounts,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 5: Burn Optimization
    batch.set(aiMainRef.collection('burn_optimization').doc('data'), {
      'expenses': filterExpenses(threeMonthsAgo, [
        'Amount',
        'Category',
        'Title',
        'Type',
        'Date',
      ]),
      'company': _extractFields(companyData, ['budgets', 'totalExpenses']),
      'teams': extractFromDocs(teamsDocs, [
        'teamName',
        'monthlyBudget',
        'usedBudget',
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 6: Staffing Analysis
    batch.set(aiMainRef.collection('staffing_analysis').doc('data'), {
      'expenses': filterExpenses(threeMonthsAgo, [
        'Amount',
        'TeamId',
        'TeamName',
        'Date',
        'Category',
      ], category: 'salary'),
      'company': _extractFields(companyData, ['totalExpenses']),
      'teams': extractFromDocs(teamsDocs, [
        'teamName',
        'monthlyBudget',
        'usedBudget',
      ]),
      'members': extractFromDocs(membersDocs, [
        'fullName',
        'salary',
        'totalExpenses',
        'remainingSalary',
        'role',
        'status',
        'teamId',
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 7: Performance Analysis
    batch.set(aiMainRef.collection('performance_analysis').doc('data'), {
      'expenses': filterExpenses(threeMonthsAgo, [
        'Amount',
        'TeamMemberId',
        'TeamMemberName',
        'Date',
      ]),
      'teams': extractFromDocs(teamsDocs, ['teamName']),
      'members': extractFromDocs(membersDocs, [
        'fullName',
        'salary',
        'totalExpenses',
        'role',
        'teamId',
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 8: Team Efficiency
    batch.set(aiMainRef.collection('team_efficiency').doc('data'), {
      'expenses': filterExpenses(startOfCurrentMonth, [
        'Amount',
        'TeamId',
        'TeamName',
        'Category',
        'Date',
      ]),
      'teams': extractFromDocs(teamsDocs, [
        'teamName',
        'monthlyBudget',
        'usedBudget',
      ]),
      'members': extractFromDocs(membersDocs, [
        'salary',
        'totalExpenses',
        'teamId',
        'status',
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 9: Expense Analysis
    batch.set(aiMainRef.collection('expense_analysis').doc('data'), {
      'expenses': filterExpenses(threeMonthsAgo, [
        'Amount',
        'Category',
        'Title',
        'Date',
        'Type',
      ]),
      'company': _extractFields(companyData, ['budgets']),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // -- Section 10: Subscription Analysis
    batch.set(aiMainRef.collection('subscription_analysis').doc('data'), {
      'expenses': filterExpenses(threeMonthsAgo, [
        'Amount',
        'Title',
        'Category',
        'Date',
        'Type',
      ], type: 'recurring'),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 4. COMMIT ALL CHANGES IN ONE BATCH
    await batch.commit();
  }

  /// Helper: Strips a document down to only the explicitly requested keys
  static Map<String, dynamic> _extractFields(
    Map<String, dynamic> data,
    List<String> fields,
  ) {
    final Map<String, dynamic> result = {};
    for (var field in fields) {
      if (data.containsKey(field)) {
        result[field] = data[field];
      }
    }
    return result;
  }

  /// Listen to a specific section's data for your UI
  static Stream<DocumentSnapshot> streamSection(String sectionName) {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return _firestore
        .collection('ai')
        .doc(user.uid)
        .collection(sectionName)
        .doc('data')
        .snapshots();
  }
}
