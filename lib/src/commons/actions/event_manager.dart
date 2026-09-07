/// A notification identified by its event type.
abstract class Event {
  String get eventType;
}

/// A synchronous notification recipient.
abstract class EventHandler {
  void onEvent(Event event);
}

/// Uses the event's Dart runtime type as its default identifier.
abstract class AbstractEvent implements Event {
  @override
  String get eventType => runtimeType.toString();
}

/// Ordered synchronous event delivery shared within the current Dart isolate.
///
/// Registration changes take effect on the next dispatch. A nested dispatch
/// takes its own snapshot and therefore sees the latest registrations. Handler
/// errors propagate to the caller and stop delivery of the current event.
class EventManager {
  static final EventManager _shared = EventManager._();
  final Set<EventHandler> _listeners = <EventHandler>{};

  EventManager._();
  static EventManager get instance => _shared;

  /// Equal handlers are registered once, in insertion order.
  void register(EventHandler handler) => _listeners.add(handler);

  void unregister(EventHandler handler) => _listeners.remove(handler);

  void onEvent(Event event) {
    final recipients = List<EventHandler>.of(_listeners, growable: false);
    for (var index = 0; index < recipients.length; index++) {
      recipients[index].onEvent(event);
    }
  }

  void clear() => _listeners.clear();
}

/// Compatibility identifiers for callers of the event API.
/// These strings do not install or advertise third-party product integrations.
class ProductNameConstant {
  ProductNameConstant._();

  static const String Core = 'dpdf Core';
  @Deprecated('Legacy product identifier retained for event compatibility.')
  static const String pdfHtml = 'pdfHTML';
  @Deprecated('Legacy product identifier retained for event compatibility.')
  static const String pdfSweep = 'pdfSweep';
  @Deprecated('Legacy product identifier retained for event compatibility.')
  static const String pdfOcr = 'pdfOCR';
  @Deprecated('Legacy product identifier retained for event compatibility.')
  static const String pdfCalligraph = 'pdfCalligraph';
}

/// Legacy event namespaces; values remain stable for existing subscribers.
class NamespaceConstant {
  NamespaceConstant._();

  static const String Core = 'com.pdf';
  @Deprecated('Legacy namespace retained for event compatibility.')
  static const String pdfHtml = 'com.pdf.html2pdf';
  @Deprecated('Legacy namespace retained for event compatibility.')
  static const String pdfOcr = 'com.pdf.pdfocr';
}
