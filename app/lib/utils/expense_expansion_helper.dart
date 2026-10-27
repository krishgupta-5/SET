import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseExpansionHelper {
  /// A single salary payment recorded from a member's screen
  /// ([ExpenseService.recordSalaryPayment]). Legacy rows carry
  /// Type='recurring' but no recurrenceFrequency; each one is a real one-off
  /// payment, so expanding it monthly counted the same salary again every
  /// month. Must match `is_salary_payment` in backend/services/metrics_service.py.
  static bool isSalaryPayment(Map<String, dynamic> e) {
    final category = (e['Category'] ?? e['category'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (category != 'salary' && category != 'salaries') return false;
    final freq = e['recurrenceFrequency'];
    if (freq != null && freq.toString().isNotEmpty) return false;
    final memberId = e['memberId'];
    return e['ExpenseType'] == 'member' ||
        (memberId != null && memberId.toString().isNotEmpty);
  }

  /// Adds [months] to [d], clamping the day to the target month's length
  /// (31 Jan + 1 month = 28/29 Feb, not 3 Mar). Matches the backend.
  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + (total ~/ 12);
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      d.day > lastDay ? lastDay : d.day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
      d.microsecond,
    );
  }

  /// Expands a list of raw expenses (which may contain recurring/subscription templates)
  /// into virtual individual occurrences up to [maxDate].
  ///
  /// Each virtual occurrence is a copy of the template, with its date and ID updated.
  static List<Map<String, dynamic>> expandExpenses(
    List<Map<String, dynamic>> rawExpenses, {
    DateTime? maxDate,
    bool allowFuture = false,
    DateTime? now,
  }) {
    final List<Map<String, dynamic>> expanded = [];
    now ??= DateTime.now();
    final limitDate = maxDate ?? now;
    final actualLimit = allowFuture
        ? limitDate
        : (limitDate.isAfter(now) ? now : limitDate);

    for (final expense in rawExpenses) {
      final typeVal = (expense['Type'] ?? expense['type'] ?? 'one_time')
          .toString()
          .toLowerCase();
      final isRecurring =
          (typeVal == 'recurring' || typeVal == 'subscription') &&
          !isSalaryPayment(expense);

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
      // EMI repayment rows written before the fix only carry loanTenureMonths.
      final rawTenure =
          expense['recurringTenureMonths'] ?? expense['loanTenureMonths'];
      final tenureMonths = rawTenure is num ? rawTenure.toInt() : null;

      DateTime? endDate;
      if (tenureMonths != null) {
        endDate = _addMonths(startDate, tenureMonths);
      }

      // An explicit stop date (set when a series is stopped) also caps it.
      final stopVal = expense['recurringEndDate'];
      final stopDate = stopVal is Timestamp
          ? stopVal.toDate()
          : (stopVal is DateTime ? stopVal : null);
      if (stopDate != null && (endDate == null || stopDate.isBefore(endDate))) {
        endDate = stopDate.add(const Duration(microseconds: 1));
      }

      final upperLimit = (endDate != null && endDate.isBefore(actualLimit))
          ? endDate
          : actualLimit;

      final originalId = expense['id'] ?? expense['expenseId'] ?? '';
      final skipped = <int>{
        for (final v in (expense['skippedOccurrences'] as List?) ?? const [])
          if (v is num) v.toInt(),
      };

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
        } else if (frequency == 'yearly') {
          occurrenceDate = _addMonths(startDate, 12 * index);
        } else {
          // Monthly (and unknown frequencies). Always computed from the start
          // date so a 31st-of-month series doesn't drift or skip months.
          occurrenceDate = _addMonths(startDate, index);
        }

        // Stop if the occurrence date exceeds our upperLimit
        if (occurrenceDate.isAfter(upperLimit)) {
          break;
        }
        // Tenure end is exclusive: a 3-month tenure yields exactly 3 charges.
        if (endDate != null && !occurrenceDate.isBefore(endDate)) {
          break;
        }

        // Occurrences deleted individually are recorded on the template.
        if (skipped.contains(index)) {
          index++;
          continue;
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
