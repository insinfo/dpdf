import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import 'pdf_signature_app.dart';

/// Dictionary that stores signature build properties.
class CraftPdfSignatureBuildProperties
    extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  /// Creates new PdfSignatureBuildProperties.
  CraftPdfSignatureBuildProperties() : super(CraftPdfDictionary());

  /// Creates new PdfSignatureBuildProperties with preset values.
  ///
  /// @param dict PdfDictionary containing preset values
  CraftPdfSignatureBuildProperties.fromDictionary(CraftPdfDictionary dict)
      : super(dict);

  /// Sets the signatureCreator property in the underlying PdfSignatureApp dictionary.
  ///
  /// @param name the signature creator's name to be set
  void setSignatureCreator(String name) {
    getPdfSignatureAppProperty().setSignatureCreator(name);
  }

  /// Gets the PdfSignatureApp from this dictionary.
  ///
  /// If it does not exist, it adds a new PdfSignatureApp and returns this instance.
  ///
  /// @return PdfSignatureApp
  CraftPdfSignatureApp getPdfSignatureAppProperty() {
    final map = pdfRepresentation().getMap();
    final obj = map?[CraftPdfName.app];
    if (obj == null || obj is! CraftPdfDictionary) {
      final newDict = CraftPdfDictionary();
      pdfRepresentation().put(CraftPdfName.app, newDict);
      return CraftPdfSignatureApp.fromDictionary(newDict);
    }
    return CraftPdfSignatureApp.fromDictionary(obj);
  }

  @override
  bool requiresIndirectStorage() {
    return false;
  }
}
