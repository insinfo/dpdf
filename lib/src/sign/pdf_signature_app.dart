import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';

/// Signature application information stored in a PDF dictionary.
class PdfSignatureApp extends PdfObjectWrapper<PdfDictionary> {
  /// Creates a new PdfSignatureApp.
  PdfSignatureApp() : super(PdfDictionary());

  /// Creates a new PdfSignatureApp from existing dictionary.
  ///
  /// @param pdfObject PdfDictionary containing initial values
  PdfSignatureApp.fromDictionary(PdfDictionary pdfObject) : super(pdfObject);

  /// Updates the creator entry within the App portion of Prop_Build
  /// dictionary.
  ///
  /// @param name signing application label
  void setSignatureCreator(String name) {
    pdfRepresentation().put(PdfName.name, PdfName(name));
  }

  @override
  bool requiresIndirectStorage() {
    return false;
  }
}
