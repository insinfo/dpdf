import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object_wrapper.dart';

/// The mark information dictionary of ISO 32000-1:2008, 14.7.1, Table 321.
///
/// It is the value of `/MarkInfo` in the document catalog (Table 28) and tells
/// a reader how far the document follows Tagged PDF conventions.
class PdfMarkInfo extends PdfObjectWrapper<PdfDictionary> {
  /// `/Marked`.
  static final PdfName marked = PdfName.intern('Marked');

  /// `/UserProperties`.
  static final PdfName userProperties = PdfName.intern('UserProperties');

  /// `/Suspects`.
  static final PdfName suspects = PdfName.intern('Suspects');

  /// Wraps [dictionary], or starts an empty mark information dictionary.
  PdfMarkInfo([PdfDictionary? dictionary])
      : super(dictionary ?? PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/Marked`: the document conforms to Tagged PDF conventions.
  /// Default `false`.
  PdfMarkInfo setMarked(bool value) => _put(marked, value);

  /// Gets `/Marked`, defaulting to `false`.
  Future<bool> getMarked() => _flag(marked);

  /// Sets `/UserProperties` (PDF 1.6): structure elements carrying user
  /// properties attributes are present. Default `false`.
  PdfMarkInfo setUserProperties(bool value) => _put(userProperties, value);

  /// Gets `/UserProperties`, defaulting to `false`.
  Future<bool> getUserProperties() => _flag(userProperties);

  /// Sets `/Suspects` (PDF 1.6): tag suspects are present, so the document may
  /// not completely conform to Tagged PDF conventions. Default `false`.
  PdfMarkInfo setSuspects(bool value) => _put(suspects, value);

  /// Gets `/Suspects`, defaulting to `false`.
  Future<bool> getSuspects() => _flag(suspects);

  PdfMarkInfo _put(PdfName key, bool value) {
    pdfRepresentation().put(key, PdfBoolean(value));
    markChanged();
    return this;
  }

  Future<bool> _flag(PdfName key) async {
    return (await pdfRepresentation().booleanEntry(key))?.getValue() ?? false;
  }
}
