import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

/// URI action, resolving a uniform resource identifier.
///
/// See ISO 32000-1:2008, 12.6.4.7, Table 206.
class PdfActionURI extends PdfAction {
  PdfActionURI(super.pdfObject);

  static PdfActionURI createURI(String uri, {bool? isMap}) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.s, PdfName.uri);
    dict.put(PdfName.uri, PdfString(uri));
    if (isMap != null) {
      dict.put(PdfName.intern('IsMap'), PdfBoolean(isMap));
    }
    return PdfActionURI(dict);
  }

  Future<String?> getUri() async {
    return (await pdfRepresentation().stringEntry(PdfName.uri))?.getValue();
  }

  /// Sets `/URI`, the identifier to resolve, encoded in 7-bit ASCII.
  PdfActionURI setUri(String uri) {
    pdfRepresentation().put(PdfName.uri, PdfString(uri));
    return this;
  }

  /// Sets `/IsMap`, whether the mouse position is tracked when the URI is
  /// resolved.
  PdfActionURI setIsMap(bool isMap) {
    pdfRepresentation().put(PdfName.intern('IsMap'), PdfBoolean(isMap));
    return this;
  }

  /// Gets `/IsMap`; the default is false per Table 206.
  Future<bool> isMap() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('IsMap')))
          ?.getValue() ??
      false;
}

/// URI dictionary of the document catalog.
///
/// See ISO 32000-1:2008, 12.6.4.7, Table 207.
abstract final class PdfUriDictionary {
  /// Builds a `/URI` dictionary with the `/Base` entry used to resolve
  /// relative URI references.
  static PdfDictionary withBase(String baseUri) {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.intern('Base'), PdfString(baseUri));
    return dictionary;
  }

  /// Reads `/Base` from a URI dictionary.
  static Future<String?> readBase(PdfDictionary dictionary) async =>
      (await dictionary.stringEntry(PdfName.intern('Base')))?.getValue();
}
