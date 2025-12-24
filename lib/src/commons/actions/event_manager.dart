/// Interface for events in the iText event system.
abstract class IEvent {
  /// Gets the type of event.
  String get eventType;
}

/// Interface for event handlers.
abstract class IEventHandler {
  /// Handles the event.
  void onEvent(IEvent event);
}

/// Base class for iText events.
abstract class AbstractITextEvent implements IEvent {
  @override
  String get eventType => runtimeType.toString();
}

/// Simple event manager for the iText library.
///
/// This is a simplified version - the original has product tracking,
/// context management, and statistics aggregation.
class EventManager {
  static final EventManager _instance = EventManager._();

  final List<IEventHandler> _handlers = [];

  EventManager._();

  /// Gets the singleton instance.
  static EventManager get instance => _instance;

  /// Registers an event handler.
  void register(IEventHandler handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
    }
  }

  /// Unregisters an event handler.
  void unregister(IEventHandler handler) {
    _handlers.remove(handler);
  }

  /// Dispatches an event to all handlers.
  void onEvent(IEvent event) {
    for (final handler in _handlers) {
      handler.onEvent(event);
    }
  }

  /// Clears all handlers.
  void clear() {
    _handlers.clear();
  }
}

/// Product name constants.
class ProductNameConstant {
  ProductNameConstant._();

  static const String iTextCore = 'iText Core';
  static const String pdfHtml = 'pdfHTML';
  static const String pdfSweep = 'pdfSweep';
  static const String pdfOcr = 'pdfOCR';
  static const String pdfCalligraph = 'pdfCalligraph';
}

/// Namespace constants for iText products.
class NamespaceConstant {
  NamespaceConstant._();

  static const String iTextCore = 'com.itextpdf';
  static const String pdfHtml = 'com.itextpdf.html2pdf';
  static const String pdfOcr = 'com.itextpdf.pdfocr';
}
