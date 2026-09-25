import 'package:startup_expense_tracker/services/ai_context_manager.dart';

/// A generic notifier for all financial data changes across the application.
/// Any module that modifies financial data (Expenses, Revenue, Team, etc.)
/// should call notifyChange() to ensure the AI subsystem is kept fresh.
class FinancialDataChangeNotifier {
  static final FinancialDataChangeNotifier _instance = FinancialDataChangeNotifier._internal();
  factory FinancialDataChangeNotifier() => _instance;
  FinancialDataChangeNotifier._internal();

  final AiContextManager _aiContextManager = AiContextManager();

  /// Notifies the system that financial data has changed.
  /// This acts as a central hub and automatically triggers an AI context invalidation.
  void notifyChange() {
    _aiContextManager.invalidate();
  }
}
