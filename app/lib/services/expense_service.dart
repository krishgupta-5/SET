import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:startup_expense_tracker/models/domain_events.dart';
import 'package:startup_expense_tracker/services/event_dispatcher.dart';
import 'package:startup_expense_tracker/utils/data_helpers.dart';
import 'package:startup_expense_tracker/utils/expense_expansion_helper.dart';

/// Which team or member an expense's amount is attributed to.
///
/// Expenses keep three denormalized counters in sync:
/// `companies.totalExpenses`, `teams.usedBudget` (team expenses) and
/// `members.totalExpenses` / `members.remainingSalary` (member expenses).
/// Every write path goes through [ExpenseService] so those counters move in
/// the same atomic batch as the expense document.
class ExpenseLink {
  const ExpenseLink({this.expenseType, this.teamId, this.memberId});

  factory ExpenseLink.fromData(Map<String, dynamic> data) {
    final memberId = (data['TeamMemberId'] ?? data['memberId']) as String?;
    var type = data['ExpenseType'] as String?;
    // Salary payments written before this fix have no ExpenseType but did
    // update the member's counters.
    if (type == null &&
        memberId != null &&
        (data['Category'] ?? '').toString().toLowerCase() == 'salary') {
      type = 'member';
    }
    return ExpenseLink(
      expenseType: type,
      teamId: data['TeamId'] as String?,
      memberId: memberId,
    );
  }

  final String? expenseType;
  final String? teamId;
  final String? memberId;

  bool get isTeam => expenseType == 'team' && (teamId?.isNotEmpty ?? false);
  bool get isMember =>
      expenseType == 'member' && (memberId?.isNotEmpty ?? false);
}

class ExpenseService {
  static final ExpenseService _instance = ExpenseService._internal();
  factory ExpenseService() => _instance;
  ExpenseService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Adds [amount] (may be negative) to the counters for [link].
  void _applyLinkDelta(WriteBatch batch, ExpenseLink link, double amount) {
    if (amount == 0) return;
    if (link.isTeam) {
      batch.update(_db.collection('teams').doc(link.teamId), {
        'usedBudget': FieldValue.increment(amount),
      });
    } else if (link.isMember) {
      batch.update(_db.collection('members').doc(link.memberId), {
        'totalExpenses': FieldValue.increment(amount),
        'remainingSalary': FieldValue.increment(-amount),
      });
    }
  }

  Future<void> addExpense({
    required String uid,
    required String companyId,
    required double amount,
    required String title,
    required String description,
    required DateTime date,
    required String category,
    required String type,
    String? bankAccount,
    String? attachmentFileId,
    required String expenseType,
    String? teamId,
    String? teamName,
    String? teamMemberId,
    String? teamMemberName,
    required bool isRecurring,
    String? recurrenceFrequency,
    int? recurringTenure,
  }) async {
    final id = const Uuid().v4();
    final batch = _db.batch();

    batch.set(_db.collection('expenses').doc(id), {
      'uid': uid,
      'companyId': companyId,
      'Amount': amount,
      'Title': title,
      'Description': description,
      'Date': date,
      'Category': category,
      'Type': type,
      'BankAccount': bankAccount,
      'AttachmentFileId': attachmentFileId ?? '',
      'ExpenseType': expenseType,
      'TeamId': teamId,
      'TeamName': teamName,
      'TeamMemberId': teamMemberId,
      'TeamMemberName': teamMemberName,
      if (expenseType == 'member' && teamMemberId != null)
        'memberId': teamMemberId,
      'Time': FieldValue.serverTimestamp(),
      if (isRecurring) ...{
        'recurrenceFrequency': recurrenceFrequency,
        'recurringTenureMonths': recurringTenure,
      },
    });

    batch.update(_db.collection('companies').doc(companyId), {
      'totalExpenses': FieldValue.increment(amount),
    });
    _applyLinkDelta(
      batch,
      ExpenseLink(
        expenseType: expenseType,
        teamId: teamId,
        memberId: teamMemberId,
      ),
      amount,
    );

    await batch.commit();
    EventDispatcher().dispatch(ExpenseSavedEvent(id));
  }

  /// Updates an expense and moves its amount between teams/members if the
  /// link changed. Reads the stored document first so counters are always
  /// reversed against what is actually saved, not what the screen loaded.
  Future<void> updateExpense({
    required String expenseId,
    required String companyId,
    required double newAmount,
    required String title,
    required String description,
    required DateTime date,
    required String category,
    required String type,
    String? bankAccount,
    String? attachmentFileId,
    required String expenseType,
    String? teamId,
    String? teamName,
    String? teamMemberId,
    String? teamMemberName,
    required bool isRecurringOrSub,
    String? recurrenceFrequency,
    int? recurringTenure,
  }) async {
    final expenseRef = _db.collection('expenses').doc(expenseId);
    final current = await expenseRef.get(const GetOptions(source: Source.server));
    if (!current.exists) {
      throw StateError('Expense no longer exists');
    }
    final oldData = current.data()!;
    final oldAmount = DataHelpers.safeParseDouble(oldData['Amount']);
    final oldLink = ExpenseLink.fromData(oldData);
    final newLink = ExpenseLink(
      expenseType: expenseType,
      teamId: teamId,
      memberId: teamMemberId,
    );

    final batch = _db.batch();
    batch.update(expenseRef, {
      'Amount': newAmount,
      'Title': title,
      'Description': description,
      'Date': date,
      'Category': category,
      'Type': type,
      'Time': FieldValue.serverTimestamp(),
      'AttachmentFileId': attachmentFileId ?? '',
      'BankAccount': bankAccount,
      'ExpenseType': expenseType,
      'TeamId': teamId,
      'TeamName': teamName,
      'TeamMemberId': teamMemberId,
      'TeamMemberName': teamMemberName,
      // memberId drives payment history; keep it aligned with the new link.
      'memberId': newLink.isMember ? teamMemberId : FieldValue.delete(),
      if (isRecurringOrSub) ...{
        'recurrenceFrequency': recurrenceFrequency,
        'recurringTenureMonths': recurringTenure,
      } else ...{
        'recurrenceFrequency': FieldValue.delete(),
        'recurringTenureMonths': FieldValue.delete(),
      },
    });

    final diff = newAmount - oldAmount;
    if (diff != 0) {
      batch.update(_db.collection('companies').doc(companyId), {
        'totalExpenses': FieldValue.increment(diff),
      });
    }
    // Reverse the old attribution in full, then apply the new one in full.
    // When the link is unchanged this nets out to `diff`.
    _applyLinkDelta(batch, oldLink, -oldAmount);
    _applyLinkDelta(batch, newLink, newAmount);

    await batch.commit();
    EventDispatcher().dispatch(ExpenseUpdatedEvent(expenseId));
  }

  /// Deletes an expense document and reverses its counters in one batch.
  Future<void> deleteExpense({
    required String expenseId,
    required String companyId,
  }) async {
    final expenseRef = _db.collection('expenses').doc(expenseId);
    final snap = await expenseRef.get(const GetOptions(source: Source.server));
    if (!snap.exists) return;
    final data = snap.data()!;
    final amount = DataHelpers.safeParseDouble(data['Amount']);

    final batch = _db.batch();
    batch.delete(expenseRef);
    if (data['isFunding'] != true) {
      batch.update(_db.collection('companies').doc(companyId), {
        'totalExpenses': FieldValue.increment(-amount),
      });
      _applyLinkDelta(batch, ExpenseLink.fromData(data), -amount);
    }
    await batch.commit();
    EventDispatcher().dispatch(ExpenseUpdatedEvent(expenseId));
  }

  /// Removes a single occurrence of a recurring/subscription series without
  /// touching the rest of the series. Counters are per-template (added once
  /// when the series was created), so they are left as-is here.
  Future<void> skipOccurrence({
    required String expenseId,
    required int occurrenceIndex,
  }) async {
    await _db.collection('expenses').doc(expenseId).update({
      'skippedOccurrences': FieldValue.arrayUnion([occurrenceIndex]),
    });
    EventDispatcher().dispatch(ExpenseUpdatedEvent(expenseId));
  }

  /// Records a salary/advance payment and updates company + member counters
  /// atomically.
  Future<void> recordSalaryPayment({
    required String uid,
    required String companyId,
    required String memberId,
    required String memberName,
    String? teamId,
    String? teamName,
    required double amount,
    required String title,
    required String description,
    required String bankAccount,
    required String paymentMethod,
  }) async {
    final id = const Uuid().v4();
    final batch = _db.batch();
    batch.set(_db.collection('expenses').doc(id), {
      'uid': uid,
      'companyId': companyId,
      'Amount': amount,
      'Title': title,
      'Description': description,
      'TeamId': teamId,
      'TeamName': teamName,
      'TeamMemberId': memberId,
      'TeamMemberName': memberName,
      'ExpenseType': 'member',
      'Date': DateTime.now(),
      'Category': 'salary',
      // Legacy value kept for compatibility. Each payment is one-off:
      // ExpenseExpansionHelper.isSalaryPayment (and the backend) never expand
      // it, so one row = one paid month.
      'Type': 'recurring',
      'BankAccount': bankAccount,
      'bankAccount': bankAccount,
      'PaymentMethod': paymentMethod,
      'memberId': memberId,
      'Time': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('companies').doc(companyId), {
      'totalExpenses': FieldValue.increment(amount),
    });
    _applyLinkDelta(
      batch,
      ExpenseLink(expenseType: 'member', memberId: memberId),
      amount,
    );
    await batch.commit();
    EventDispatcher().dispatch(ExpenseSavedEvent(id));
  }

  /// Records a funding round (and optional loan EMI schedule) atomically.
  ///
  /// Funding rows stay in `expenses` with `isFunding: true` because the funds
  /// history and transaction detail screens read them from there.
  /// [FinancialCalculator.compute] is the one place that excludes them.
  Future<void> recordFunding({
    required String uid,
    required String companyId,
    required double amount,
    required double previousFunding,
    required String sourceLabel,
    required String sourceKey,
    required String notes,
    String? targetRunway,
    Map<String, dynamic>? loan,
    double? emiAmount,
    DateTime? emiStartDate,
  }) async {
    final now = DateTime.now();
    final batch = _db.batch();

    batch.set(_db.collection('funding_transactions').doc(), {
      'uid': uid,
      'companyId': companyId,
      'amount': amount,
      'source': sourceLabel,
      'sourceKey': sourceKey,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'previousFunding': previousFunding,
      'newTotalFunding': previousFunding + amount,
      ...?loan,
    });

    batch.set(_db.collection('expenses').doc(const Uuid().v4()), {
      'uid': uid,
      'companyId': companyId,
      'Amount': amount,
      'Title': 'Funding: $sourceLabel',
      'Description': notes,
      'Date': Timestamp.fromDate(now),
      'Category': 'funding',
      'Type': 'one_time',
      'BankAccount': null,
      'AttachmentFileId': '',
      'ExpenseType': 'funding',
      'isFunding': true,
      'fundingSource': sourceLabel,
      'fundingSourceKey': sourceKey,
      'Time': FieldValue.serverTimestamp(),
      ...?loan,
    });

    if (emiAmount != null && emiAmount > 0 && emiStartDate != null) {
      final lender = loan?['loanLenderBank'] ?? 'Bank';
      batch.set(_db.collection('expenses').doc(const Uuid().v4()), {
        'uid': uid,
        'companyId': companyId,
        'Amount': emiAmount,
        'Title': 'EMI: $lender Loan Repayment',
        'Description':
            'Monthly EMI repayment for $lender loan of amount $amount',
        'Date': Timestamp.fromDate(emiStartDate),
        'Category': 'others',
        'Type': 'recurring',
        'recurrenceFrequency': 'monthly',
        'recurringTenureMonths': loan?['loanTenureMonths'],
        'BankAccount': null,
        'AttachmentFileId': '',
        'ExpenseType': 'others',
        'isFunding': false,
        'isEmiRepayment': true,
        ...?loan,
        // The EMI row is an outflow, never a funding row.
        'isBankLoan': null,
        'Time': FieldValue.serverTimestamp(),
      });
    }

    // increment() on a non-numeric field would replace it, so only use it when
    // the stored value is already a number (company setup writes an int).
    final companyRef = _db.collection('companies').doc(companyId);
    final companySnap = await companyRef.get(
      const GetOptions(source: Source.server),
    );
    final storedFunding = companySnap.data()?['Funding'];
    batch.set(companyRef, {
      'Funding': storedFunding is num
          ? FieldValue.increment(amount)
          : DataHelpers.safeParseDouble(storedFunding) + amount,
      if (targetRunway != null && targetRunway.isNotEmpty)
        'Target Runway': targetRunway,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Records revenue (customer income). Stored in `revenue`, not as funding,
  /// so total funding raised stays accurate and net burn = burn - revenue.
  Future<void> recordRevenue({
    required String uid,
    required String companyId,
    required double amount,
    required String source,
    required String notes,
    DateTime? date,
  }) async {
    final ref = _db.collection('revenue').doc(const Uuid().v4());
    await ref.set({
      'uid': uid,
      'companyId': companyId,
      'Amount': amount,
      'Title': notes.isNotEmpty ? notes : source,
      'Source': source,
      'Description': notes,
      'Date': Timestamp.fromDate(date ?? DateTime.now()),
      'Time': FieldValue.serverTimestamp(),
    });
    EventDispatcher().dispatch(FinancialDataChangedEvent('revenue'));
  }

  /// This month's spend attributed to [teamId]: active members' monthly cost
  /// plus non-salary expenses tagged to the team. Same definition the monthly
  /// burn screen uses for team budget variance.
  Future<double> teamSpendThisMonth({
    required String uid,
    required String teamId,
  }) async {
    final now = DateTime.now();
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final results = await Future.wait([
      _db
          .collection('members')
          .where('uid', isEqualTo: uid)
          .where('teamId', isEqualTo: teamId)
          .get(),
      _db.collection('expenses').where('uid', isEqualTo: uid).get(),
    ]);

    double total = 0;
    for (final m in results[0].docs) {
      final d = m.data();
      if ((d['status'] ?? 'Active') != 'Active') continue;
      total += DataHelpers.safeParseDouble(d['monthlyCost'] ?? d['salary']);
    }

    final expanded = ExpenseExpansionHelper.expandExpenses(
      results[1].docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((e) => e['isFunding'] != true && e['TeamId'] == teamId)
          .toList(),
      maxDate: endOfMonth,
      allowFuture: true,
    );
    for (final e in expanded) {
      final cat = (e['Category'] ?? '').toString().toLowerCase();
      if (cat == 'salary' || cat == 'salaries') continue;
      final dt = DataHelpers.safeParseDate(e['Date']);
      if (dt != null && dt.year == now.year && dt.month == now.month) {
        total += DataHelpers.safeParseDouble(e['Amount']);
      }
    }
    return total;
  }

  /// This month's spend in [category] (case-insensitive), including recurring
  /// occurrences. Queries on `uid` only, so no composite index is needed.
  Future<double> categorySpendThisMonth({
    required String uid,
    required String category,
  }) async {
    final now = DateTime.now();
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final snap = await _db
        .collection('expenses')
        .where('uid', isEqualTo: uid)
        .get();
    final target = category.toLowerCase().trim();
    final expanded = ExpenseExpansionHelper.expandExpenses(
      snap.docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((e) => e['isFunding'] != true)
          .toList(),
      maxDate: endOfMonth,
      allowFuture: true,
    );
    double total = 0;
    for (final e in expanded) {
      final cat = (e['Category'] ?? '').toString().toLowerCase().trim();
      if (cat != target) continue;
      final dt = DataHelpers.safeParseDate(e['Date']);
      if (dt != null && dt.year == now.year && dt.month == now.month) {
        total += DataHelpers.safeParseDouble(e['Amount']);
      }
    }
    return total;
  }
}
