import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_number.dart';

enum LockAction { all, include, exclude }

enum LockPermissions { noChangesAllowed, formFilling, formFillingAndAnnotation }

class CraftPdfSigFieldLock extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfSigFieldLock([CraftPdfDictionary? dict])
      : super(dict ?? CraftPdfDictionary()) {
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.sigFieldLock);
  }

  @override
  bool requiresIndirectStorage() => true;

  void setDocumentPermissions(LockPermissions permissions) {
    pdfRepresentation().put(CraftPdfName.p, _getLockPermission(permissions));
  }

  void setFieldLock(LockAction action, List<String> fields) {
    final fieldsArray = CraftPdfArray();
    for (var field in fields) {
      fieldsArray.add(CraftPdfString(field));
    }
    pdfRepresentation().put(CraftPdfName.action, _getLockActionValue(action));
    pdfRepresentation().put(CraftPdfName.fields, fieldsArray);
  }

  static CraftPdfName _getLockActionValue(LockAction action) {
    switch (action) {
      case LockAction.all:
        return CraftPdfName.all;
      case LockAction.include:
        return CraftPdfName.include;
      case LockAction.exclude:
        return CraftPdfName.exclude;
    }
  }

  static CraftPdfNumber _getLockPermission(LockPermissions permissions) {
    switch (permissions) {
      case LockPermissions.noChangesAllowed:
        return CraftPdfNumber(1);
      case LockPermissions.formFilling:
        return CraftPdfNumber(2);
      case LockPermissions.formFillingAndAnnotation:
        return CraftPdfNumber(3);
    }
  }
}
