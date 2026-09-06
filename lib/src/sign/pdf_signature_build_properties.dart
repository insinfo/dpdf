import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import 'pdf_signature_app.dart';

/// Dictionary that stores signature build properties.
class PdfSignatureBuildProperties extends PdfObjectWrapper<PdfDictionary> {
  /// Creates new PdfSignatureBuildProperties.
  PdfSignatureBuildProperties() : super(PdfDictionary());

  /// Creates new PdfSignatureBuildProperties with preset values.
  ///
  /// @param dict PdfDictionary containing preset values
  PdfSignatureBuildProperties.fromDictionary(PdfDictionary dict) : super(dict);

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
  PdfSignatureApp getPdfSignatureAppProperty() {
    final map = getPdfObject().getMap();
    final obj = map?[PdfName.app];
    if (obj == null || obj is! PdfDictionary) {
      final newDict = PdfDictionary();
      getPdfObject().put(PdfName.app, newDict);
      return PdfSignatureApp.fromDictionary(newDict);
    }
    return PdfSignatureApp.fromDictionary(obj);
  }

  @override
  bool isWrappedObjectMustBeIndirect() {
    return false;
  }
}
