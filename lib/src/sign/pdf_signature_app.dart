import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';

/// A dictionary that stores the name of the application that signs the PDF.
class PdfSignatureApp extends PdfObjectWrapper<PdfDictionary> {
  /// Creates a new PdfSignatureApp.
  PdfSignatureApp() : super(PdfDictionary());

  /// Creates a new PdfSignatureApp from existing dictionary.
  ///
  /// @param pdfObject PdfDictionary containing initial values
  PdfSignatureApp.fromDictionary(PdfDictionary pdfObject) : super(pdfObject);

  /// Sets the signature created property in the Prop_Build dictionary's App
  /// dictionary.
  ///
  /// @param name String name of the application creating the signature
  void setSignatureCreator(String name) {
    getPdfObject().put(PdfName.name, PdfName(name));
  }

  @override
  bool isWrappedObjectMustBeIndirect() {
    return false;
  }
}
