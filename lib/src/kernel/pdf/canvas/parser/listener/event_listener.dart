import '../data/event_data.dart';
import '../event_type.dart';

/// Interface for listening to content stream parsing events.
abstract class CraftEventListener {
  /// Called when an event occurs.
  void eventOccurred(CraftEventData? data, CraftEventType type);

  /// Returns the set of event types this listener is interested in.
  Set<CraftEventType> getSupportedEvents();
}
