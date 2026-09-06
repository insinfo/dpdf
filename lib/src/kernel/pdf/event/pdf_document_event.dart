import '../pdf_dictionary.dart';
import '../pdf_document.dart';
import '../../../commons/actions/event_manager.dart';

/// Event dispatched by the [PdfDocument].
class PdfDocumentEvent implements IEvent {
  /// Dispatched before page is created.
  static const String startPage = 'StartPage';

  /// Dispatched after page is created and added to the document.
  static const String insertPage = 'InsertPage';

  /// Dispatched after page is removed from the document.
  static const String removePage = 'RemovePage';

  /// Dispatched before document closing.
  static const String endPage =
      'EndPage'; // This might be confusing naming from , usually 'EndPage' is per page, not closes doc. Checking C# source.

  final String _type;
  final PdfDictionary? _page;

  /// Creates a [PdfDocumentEvent].
  PdfDocumentEvent(String type, this._page) : _type = type;

  @override
  String get eventType => _type;

  /// Gets the [PdfDictionary] representation of the page associated with this event.
  PdfDictionary? getPage() => _page;
}
