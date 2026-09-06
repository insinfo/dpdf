/// A notification identified by its event type.
abstract class CraftEvent {
  String get eventType;
}

/// A synchronous notification recipient.
abstract class CraftEventHandler {
  void onEvent(CraftEvent event);
}

/// Uses the event's Dart runtime type as its default identifier.
abstract class AbstractEvent implements CraftEvent {
  @override
  String get eventType => runtimeType.toString();
}

/// Ordered synchronous event delivery shared within the current Dart isolate.
///
/// Registration changes take effect on the next dispatch. A nested dispatch
/// takes its own snapshot and therefore sees the latest registrations. Handler
/// errors propagate to the caller and stop delivery of the current event.
class CraftEventManager {
  static final CraftEventManager _shared = CraftEventManager._();
  final Set<CraftEventHandler> _listeners = <CraftEventHandler>{};

  CraftEventManager._();
  static CraftEventManager get instance => _shared;

  /// Equal handlers are registered once, in insertion order.
  void register(CraftEventHandler handler) => _listeners.add(handler);

  void unregister(CraftEventHandler handler) => _listeners.remove(handler);

  void onEvent(CraftEvent event) {
    final recipients = List<CraftEventHandler>.of(_listeners, growable: false);
    for (var index = 0; index < recipients.length; index++) {
      recipients[index].onEvent(event);
    }
  }

  void clear() => _listeners.clear();
}

/// Compatibility identifiers for callers of the event API.
/// These strings do not install or advertise third-party product integrations.
class CraftProductNameConstant {
  CraftProductNameConstant._();

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
class CraftNamespaceConstant {
  CraftNamespaceConstant._();

  static const String Core = 'com.pdf';
  @Deprecated('Legacy namespace retained for event compatibility.')
  static const String pdfHtml = 'com.pdf.html2pdf';
  @Deprecated('Legacy namespace retained for event compatibility.')
  static const String pdfOcr = 'com.pdf.pdfocr';
}
