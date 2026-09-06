import '../exceptions/pdf_exception.dart';
import '../exceptions/kernel_exception_message_constant.dart';
import 'pdf_object.dart';
import 'pdf_document.dart';

/// Base class for all PDF object wrappers.
abstract class CraftPdfObjectWrapper<T extends CraftPdfObject> {
  T _pdfObject;

  CraftPdfObjectWrapper(this._pdfObject) {
    if (requiresIndirectStorage()) {
      markObjectAsIndirect(_pdfObject);
    }
  }

  T pdfRepresentation() {
    return _pdfObject;
  }

  CraftPdfDocument? getDocument() {
    return _pdfObject.indirectHandle()?.getDocument();
  }

  CraftPdfObjectWrapper<T> attachToDocument(CraftPdfDocument document) {
    _pdfObject.attachToDocument(document);
    return this;
  }

  CraftPdfObjectWrapper<T> markChanged() {
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
    _pdfObject.setState(CraftPdfObject.forbidRelease);
  }

  void unsetForbidRelease() {
    _pdfObject.clearState(CraftPdfObject.forbidRelease);
  }

  void ensureUnderlyingObjectHasIndirectReference() {
    if (_pdfObject.indirectHandle() == null) {
      throw CraftPdfException(CraftKernelExceptionMessageConstant
          .toFlushThisWrapperUnderlyingObjectMustBeAddedToDocument);
    }
  }

  static void markObjectAsIndirect(CraftPdfObject pdfObject) {
    if (pdfObject.indirectHandle() == null) {
      pdfObject.setState(CraftPdfObject.mustBeIndirect);
    }
  }

  static void ensureObjectIsAddedToDocument(CraftPdfObject object) {
    if (object.indirectHandle() == null) {
      throw CraftPdfException(CraftKernelExceptionMessageConstant
          .objectMustBeIndirectToWorkWithThisWrapper);
    }
  }
}
