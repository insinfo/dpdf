import '../data/event_data.dart';
import '../event_type.dart';

/// Interface for listening to content stream parsing events.
abstract class EventListener {
  /// Called when an event occurs.
  void eventOccurred(EventData? data, EventType type);

  /// Returns the set of event types this listener is interested in.
  Set<EventType> getSupportedEvents();
}
