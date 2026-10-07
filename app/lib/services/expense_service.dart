import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:startup_expense_tracker/models/domain_events.dart';
import 'package:startup_expense_tracker/services/event_dispatcher.dart';
import 'package:startup_expense_tracker/utils/data_helpers.dart';


class ExpenseService {
  static final ExpenseService _instance = ExpenseService._internal();
  factory ExpenseService() => _instance;
  ExpenseService._internal();

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
    final batch = FirebaseFirestore.instance.batch();

    // 1. Write expense document
    final expenseRef = FirebaseFirestore.instance.collection('expenses').doc(id);
    batch.set(expenseRef, {
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
      if (expenseType == 'member' && teamMemberId != null) 'memberId': teamMemberId,
      'Time': FieldValue.serverTimestamp(),
      if (isRecurring) ...{
        'recurrenceFrequency': recurrenceFrequency,
        'recurringTenureMonths': recurringTenure,
      },
    });

    // 2. Increment company totalExpenses atomically
    final companyRef = FirebaseFirestore.instance.collection('companies').doc(companyId);
    batch.update(companyRef, {'totalExpenses': FieldValue.increment(amount)});

    // 3. If team expense, add to team's tracked expenses
    if (expenseType == 'team' && teamId != null) {
      final teamRef = FirebaseFirestore.instance.collection('teams').doc(teamId);
      batch.update(teamRef, {'usedBudget': FieldValue.increment(amount)});
    } else if (expenseType == 'member' && teamMemberId != null) {
      final memberRef = FirebaseFirestore.instance.collection('members').doc(teamMemberId);
      batch.update(memberRef, {
        'totalExpenses': FieldValue.increment(amount),
        'remainingSalary': FieldValue.increment(-amount),
      });
    }

    await batch.commit();

    // Dispatch domain event (UI remains decoupled from AI)
    EventDispatcher().dispatch(ExpenseSavedEvent(id));
  }

  Future<void> updateExpense({
    required String expenseId,
    required String companyId,
    required double diff,
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
    final batch = FirebaseFirestore.instance.batch();

    final expenseRef = FirebaseFirestore.instance.collection('expenses').doc(expenseId);
    batch.update(expenseRef, {
      "Amount": newAmount,
      "Title": title,
      "Description": description,
      "Date": date,
      "Category": category,
      "Type": type,
      "Time": FieldValue.serverTimestamp(),
      "AttachmentFileId": attachmentFileId ?? '',
      "BankAccount": bankAccount,
      "ExpenseType": expenseType,
      "TeamId": teamId,
      "TeamName": teamName,
      "TeamMemberId": teamMemberId,
      "TeamMemberName": teamMemberName,
      if (isRecurringOrSub) ...{
        'recurrenceFrequency': recurrenceFrequency,
        'recurringTenureMonths': recurringTenure,
      } else ...{
        'recurrenceFrequency': FieldValue.delete(),
        'recurringTenureMonths': FieldValue.delete(),
      }
    });

    if (diff != 0) {
      final companyDoc = await FirebaseFirestore.instance.collection('companies').doc(companyId).get();
      double currentTotal = 0.0;
      if (companyDoc.exists) {
        currentTotal = DataHelpers.safeParseDouble(companyDoc.data()?['totalExpenses']);
      }
      double newTotal = currentTotal + diff;
      if (newTotal < 0) newTotal = 0.0;

      final companyRef = FirebaseFirestore.instance.collection('companies').doc(companyId);
      batch.update(companyRef, {"totalExpenses": newTotal});

      if (expenseType == 'team' && teamId != null) {
        final teamRef = FirebaseFirestore.instance.collection('teams').doc(teamId);
        batch.update(teamRef, {"usedBudget": FieldValue.increment(diff)});
      } else if (expenseType == 'member' && teamMemberId != null) {
        final memberRef = FirebaseFirestore.instance.collection('members').doc(teamMemberId);
        batch.update(memberRef, {
          "totalExpenses": FieldValue.increment(diff),
          "remainingSalary": FieldValue.increment(-diff),
        });
      }
    }

    await batch.commit();

    // Dispatch domain event (UI remains decoupled from AI)
    EventDispatcher().dispatch(ExpenseUpdatedEvent(expenseId));
  }
}
