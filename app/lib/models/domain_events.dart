/// Base class for all domain events
abstract class DomainEvent {}

/// Base class for all financial-related events
abstract class FinancialEvent extends DomainEvent {}

class ExpenseSavedEvent extends FinancialEvent {
  final String expenseId;
  ExpenseSavedEvent(this.expenseId);
}

class ExpenseUpdatedEvent extends FinancialEvent {
  final String expenseId;
  ExpenseUpdatedEvent(this.expenseId);
}

class ExpenseDeletedEvent extends FinancialEvent {
  final String expenseId;
  ExpenseDeletedEvent(this.expenseId);
}

/// Any other financial data changed (funding, members, teams, company,
/// budgets, revenue). Emitted when live data changes so AI context refreshes.
class FinancialDataChangedEvent extends FinancialEvent {
  final String source;
  FinancialDataChangedEvent(this.source);
}
