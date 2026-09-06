import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';

/// Signature application information stored in a PDF dictionary.
class CraftPdfSignatureApp extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  /// Creates a new PdfSignatureApp.
  CraftPdfSignatureApp() : super(CraftPdfDictionary());

  /// Creates a new PdfSignatureApp from existing dictionary.
  ///
  /// @param pdfObject PdfDictionary containing initial values
  CraftPdfSignatureApp.fromDictionary(CraftPdfDictionary pdfObject)
      : super(pdfObject);

  /// Updates the creator entry within the App portion of Prop_Build
  /// dictionary.
  ///
  /// @param name signing application label
  void setSignatureCreator(String name) {
    pdfRepresentation().put(CraftPdfName.name, CraftPdfName(name));
  }

  @override
  bool requiresIndirectStorage() {
    return false;
  }
}
