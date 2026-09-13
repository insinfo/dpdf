import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// The URI dictionary of ISO 32000-1:2008, 12.6.4.7, Table 207.
///
/// It is the value of `/URI` in the document catalog (Table 28) and holds the
/// document level information used by URI actions.
class PdfUriDictionary extends PdfObjectWrapper<PdfDictionary> {
  /// `/Base`.
  static final PdfName base = PdfName.intern('Base');

  /// Wraps [dictionary], or starts an empty URI dictionary.
  PdfUriDictionary([PdfDictionary? dictionary])
      : super(dictionary ?? PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/Base`, the base URI used to resolve relative URI references.
  PdfUriDictionary setBase(String baseUri) {
    pdfRepresentation().put(base, PdfString(baseUri));
    markChanged();
    return this;
  }

  /// Gets `/Base`, or `null` when absent. Table 207 then resolves partial URIs
  /// relative to the location of the document itself.
  Future<String?> getBase() async {
    return (await pdfRepresentation().stringEntry(base))?.decodeMappingText();
  }
}
