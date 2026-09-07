import '../exceptions/pdf_exception.dart';
import '../exceptions/kernel_exception_message_constant.dart';
import 'pdf_object.dart';
import 'pdf_document.dart';

/// Base class for all PDF object wrappers.
abstract class PdfObjectWrapper<T extends PdfObject> {
  T _pdfObject;

  PdfObjectWrapper(this._pdfObject) {
    if (requiresIndirectStorage()) {
      markObjectAsIndirect(_pdfObject);
    }
  }

  T pdfRepresentation() {
    return _pdfObject;
  }

  PdfDocument? getDocument() {
    return _pdfObject.indirectHandle()?.getDocument();
  }

  PdfObjectWrapper<T> attachToDocument(PdfDocument document) {
    _pdfObject.attachToDocument(document);
    return this;
  }

  PdfObjectWrapper<T> markChanged() {
    _pdfObject.markChanged();
    return this;
  }

  Future<void> flush() async {
    await _pdfObject.flush();
  }

  bool hasBeenWritten() {
    return _pdfObject.hasBeenWritten();
  }

  /// Determines whether the wrapped value requires indirect storage in the
  /// resultant document.
  bool requiresIndirectStorage();

  void setPdfObject(T pdfObject) {
    _pdfObject = pdfObject;
  }

  void setForbidRelease() {
    _pdfObject.setState(PdfObject.forbidRelease);
  }

  void unsetForbidRelease() {
    _pdfObject.clearState(PdfObject.forbidRelease);
  }

  void ensureUnderlyingObjectHasIndirectReference() {
    if (_pdfObject.indirectHandle() == null) {
      throw PdfException(KernelExceptionMessageConstant
          .toFlushThisWrapperUnderlyingObjectMustBeAddedToDocument);
    }
  }

  static void markObjectAsIndirect(PdfObject pdfObject) {
    if (pdfObject.indirectHandle() == null) {
      pdfObject.setState(PdfObject.mustBeIndirect);
    }
  }

  static void ensureObjectIsAddedToDocument(PdfObject object) {
    if (object.indirectHandle() == null) {
      throw PdfException(KernelExceptionMessageConstant
          .objectMustBeIndirectToWorkWithThisWrapper);
    }
  }
}
