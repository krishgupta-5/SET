import 'package:startup_expense_tracker/models/domain_events.dart';

typedef EventHandler<T extends DomainEvent> = void Function(T event);

/// A simple generic Event Bus / Dispatcher.
class EventDispatcher {
  static final EventDispatcher _instance = EventDispatcher._internal();
  factory EventDispatcher() => _instance;
  EventDispatcher._internal();

  final Map<Type, List<EventHandler>> _listeners = {};

  /// Subscribes to a specific event type.
  void subscribe<T extends DomainEvent>(EventHandler<T> handler) {
    if (!_listeners.containsKey(T)) {
      _listeners[T] = [];
    }
    // We wrap the handler to handle type casting dynamically
    _listeners[T]!.add((DomainEvent event) => handler(event as T));
  }

  /// Dispatches an event to all subscribers of its type (and base types).
  void dispatch<T extends DomainEvent>(T event) {
    // Exact match listeners
    if (_listeners.containsKey(T)) {
      for (final handler in _listeners[T]!) {
        handler(event);
      }
    }
    
    // Also notify listeners of the base class FinancialEvent if applicable
    if (event is FinancialEvent && T != FinancialEvent) {
      if (_listeners.containsKey(FinancialEvent)) {
        for (final handler in _listeners[FinancialEvent]!) {
          handler(event);
        }
      }
    }
  }
}
