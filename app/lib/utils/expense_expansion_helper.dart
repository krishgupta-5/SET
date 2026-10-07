import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseExpansionHelper {
  /// Expands a list of raw expenses (which may contain recurring/subscription templates)
  /// into virtual individual occurrences up to [maxDate].
  ///
  /// Each virtual occurrence is a copy of the template, with its date and ID updated.
  static List<Map<String, dynamic>> expandExpenses(
    List<Map<String, dynamic>> rawExpenses, {
    DateTime? maxDate,
    bool allowFuture = false,
  }) {
    final List<Map<String, dynamic>> expanded = [];
    final now = DateTime.now();
    final limitDate = maxDate ?? now;
    final actualLimit = allowFuture
        ? limitDate
        : (limitDate.isAfter(now) ? now : limitDate);

    for (final expense in rawExpenses) {
      final typeVal = (expense['Type'] ?? expense['type'] ?? 'one_time')
          .toString()
          .toLowerCase();
      final isRecurring = typeVal == 'recurring' || typeVal == 'subscription';

      if (!isRecurring) {
        // One-time expense is returned as-is
        expanded.add(expense);
        continue;
      }

      final dateVal = expense['Date'] ?? expense['date'];
      if (dateVal == null) {
        expanded.add(expense);
        continue;
      }

      DateTime startDate;
      if (dateVal is Timestamp) {
        startDate = dateVal.toDate();
      } else if (dateVal is DateTime) {
        startDate = dateVal;
      } else {
        expanded.add(expense);
        continue;
      }

      // If the recurring expense starts in the future, don't generate occurrences
      if (startDate.isAfter(actualLimit)) {
        continue;
      }

      final frequency = (expense['recurrenceFrequency'] ?? 'monthly')
          .toString()
          .toLowerCase();
      final tenureMonths = expense['recurringTenureMonths'] as int?;

      DateTime? endDate;
      if (tenureMonths != null) {
        endDate = DateTime(
          startDate.year,
          startDate.month + tenureMonths,
          startDate.day,
          startDate.hour,
          startDate.minute,
          startDate.second,
          startDate.millisecond,
          startDate.microsecond,
        );
      }

      final upperLimit = (endDate != null && endDate.isBefore(actualLimit))
          ? endDate
          : actualLimit;

      final originalId = expense['id'] ?? expense['expenseId'] ?? '';

      int index = 0;
      while (true) {
        DateTime occurrenceDate;
        if (frequency == 'daily') {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month,
            startDate.day + index,
            startDate.hour,
            startDate.minute,
            startDate.second,
            startDate.millisecond,
            startDate.microsecond,
          );
        } else if (frequency == 'weekly') {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month,
            startDate.day + (index * 7),
            startDate.hour,
            startDate.minute,
            startDate.second,
            startDate.millisecond,
            startDate.microsecond,
          );
        } else if (frequency == 'monthly') {
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month + index,
            startDate.day,
            startDate.hour,
            startDate.minute,
            startDate.second,
            startDate.millisecond,
            startDate.microsecond,
          );
        } else if (frequency == 'yearly') {
          occurrenceDate = DateTime(
            startDate.year + index,
            startDate.month,
            startDate.day,
            startDate.hour,
            startDate.minute,
            startDate.second,
            startDate.millisecond,
            startDate.microsecond,
          );
        } else {
          // Fallback to monthly if frequency unknown
          occurrenceDate = DateTime(
            startDate.year,
            startDate.month + index,
            startDate.day,
            startDate.hour,
            startDate.minute,
            startDate.second,
            startDate.millisecond,
            startDate.microsecond,
          );
        }

        // Stop if the occurrence date exceeds our upperLimit
        if (occurrenceDate.isAfter(upperLimit)) {
          break;
        }

        // Create the virtual occurrence
        final occurrence = Map<String, dynamic>.from(expense);
        occurrence['Date'] = Timestamp.fromDate(occurrenceDate);
        occurrence['date'] = Timestamp.fromDate(occurrenceDate);
        if (originalId.isNotEmpty) {
          occurrence['id'] = '${originalId}_$index';
          occurrence['expenseId'] = '${originalId}_$index';
        }
        occurrence['isVirtual'] = true;
        occurrence['virtualIndex'] = index;
        occurrence['originalId'] = originalId;

        expanded.add(occurrence);
        index++;
      }
    }

    return expanded;
  }
}
