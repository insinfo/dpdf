import '../exceptions/pdf_exception.dart';
import '../exceptions/kernel_exception_message_constant.dart';
import 'pdf_object.dart';
// import 'pdf_document.dart'; // Circular dependency if imported now

/// Base class for all PDF object wrappers.
abstract class PdfObjectWrapper<T extends PdfObject> {
  T _pdfObject;

  PdfObjectWrapper(this._pdfObject) {
    if (isWrappedObjectMustBeIndirect()) {
      markObjectAsIndirect(_pdfObject);
    }
  }

  T getPdfObject() {
    return _pdfObject;
  }

  // TODO: Implement MakeIndirect after PdfDocument is ported
  /*
  PdfObjectWrapper<T> makeIndirect(PdfDocument document, [PdfIndirectReference? reference]) {
    _pdfObject.makeIndirect(document, reference);
    return this;
  }
  */

  PdfObjectWrapper<T> setModified() {
    _pdfObject.setModified();
    return this;
  }

  void flush() {
    _pdfObject.flush();
  }

  bool isFlushed() {
    return _pdfObject.isFlushed();
  }

  /// Defines if the object behind this wrapper must be an indirect object in the
  /// resultant document.
  bool isWrappedObjectMustBeIndirect();

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
    if (_pdfObject.getIndirectReference() == null) {
      throw PdfException(KernelExceptionMessageConstant
          .toFlushThisWrapperUnderlyingObjectMustBeAddedToDocument);
    }
  }

  static void markObjectAsIndirect(PdfObject pdfObject) {
    if (pdfObject.getIndirectReference() == null) {
      pdfObject.setState(PdfObject.mustBeIndirect);
    }
  }

  static void ensureObjectIsAddedToDocument(PdfObject object) {
    if (object.getIndirectReference() == null) {
      throw PdfException(KernelExceptionMessageConstant
          .objectMustBeIndirectToWorkWithThisWrapper);
    }
  }
}
