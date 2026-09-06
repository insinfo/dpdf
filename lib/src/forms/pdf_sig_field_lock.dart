import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_number.dart';

enum LockAction { all, include, exclude }

enum LockPermissions { noChangesAllowed, formFilling, formFillingAndAnnotation }

class PdfSigFieldLock extends PdfObjectWrapper<PdfDictionary> {
  PdfSigFieldLock([PdfDictionary? dict]) : super(dict ?? PdfDictionary()) {
    getPdfObject().put(PdfName.type, PdfName.sigFieldLock);
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  void setDocumentPermissions(LockPermissions permissions) {
    getPdfObject().put(PdfName.p, _getLockPermission(permissions));
  }

  void setFieldLock(LockAction action, List<String> fields) {
    final fieldsArray = PdfArray();
    for (var field in fields) {
      fieldsArray.add(PdfString(field));
    }
    getPdfObject().put(PdfName.action, _getLockActionValue(action));
    getPdfObject().put(PdfName.fields, fieldsArray);
  }

  static PdfName _getLockActionValue(LockAction action) {
    switch (action) {
      case LockAction.all:
        return PdfName.all;
      case LockAction.include:
        return PdfName.include;
      case LockAction.exclude:
        return PdfName.exclude;
    }
  }

  static PdfNumber _getLockPermission(LockPermissions permissions) {
    switch (permissions) {
      case LockPermissions.noChangesAllowed:
        return PdfNumber(1);
      case LockPermissions.formFilling:
        return PdfNumber(2);
      case LockPermissions.formFillingAndAnnotation:
        return PdfNumber(3);
    }
  }
}
