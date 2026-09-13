import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_number.dart';

/// `/Action` of a signature field lock dictionary, ISO 32000-1 table 233.
enum LockAction {
  /// All fields in the document shall be locked.
  all,

  /// Only the fields listed in `/Fields` shall be locked.
  include,

  /// Every field except those listed in `/Fields` shall be locked.
  exclude,
}

/// `/P` of the DocMDP transform parameters, ISO 32000-1 table 254.
enum LockPermissions {
  /// Any change to the document invalidates the signature.
  noChangesAllowed,

  /// Filling in forms, instantiating page templates and signing are allowed.
  formFilling,

  /// Adds annotation creation, deletion and modification to [formFilling].
  formFillingAndAnnotation,
}

/// A signature field lock dictionary, ISO 32000-1 table 233.
///
/// The dictionary is referenced from the `/Lock` entry of a signature field and
/// names the form fields that a conforming reader shall not let the user change
/// once the field is signed. When the field is signed, 12.8.2.4 requires the
/// `/Action` and `/Fields` entries to be copied into the FieldMDP transform
/// parameters of the resulting signature.
class PdfSigFieldLock extends PdfObjectWrapper<PdfDictionary> {
  PdfSigFieldLock([PdfDictionary? dict]) : super(dict ?? PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.sigFieldLock);
  }

  /// Wraps an existing dictionary without rewriting its `/Type`.
  PdfSigFieldLock.fromDictionary(super.dict);

  @override
  bool requiresIndirectStorage() => true;

  /// Sets the DocMDP access permissions granted by the signature that locks
  /// this field.
  void setDocumentPermissions(LockPermissions permissions) {
    pdfRepresentation().put(PdfName.p, _getLockPermission(permissions));
  }

  /// Reads the `/P` entry, or null when it is absent or out of range.
  Future<LockPermissions?> getDocumentPermissions() async {
    final number = await pdfRepresentation().numberEntry(PdfName.p);
    switch (number?.intValue()) {
      case 1:
        return LockPermissions.noChangesAllowed;
      case 2:
        return LockPermissions.formFilling;
      case 3:
        return LockPermissions.formFillingAndAnnotation;
    }
    return null;
  }

  /// Sets `/Action` and, when the action is not [LockAction.all], `/Fields`.
  void setFieldLock(LockAction action, List<String> fields) {
    pdfRepresentation().put(PdfName.action, actionName(action));
    if (action == LockAction.all) {
      pdfRepresentation().remove(PdfName.fields);
      return;
    }
    final fieldsArray = PdfArray();
    for (var field in fields) {
      fieldsArray.add(PdfString(field));
    }
    pdfRepresentation().put(PdfName.fields, fieldsArray);
  }

  /// Reads the `/Action` entry, or null when it is absent or unknown.
  Future<LockAction?> getFieldLockAction() async =>
      actionOf(await pdfRepresentation().nameEntry(PdfName.action));

  /// Reads the `/Fields` entry as text strings; empty when absent.
  Future<List<String>> getFieldLockFields() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.fields);
    final names = <String>[];
    if (array == null) return names;
    for (var index = 0; index < array.size(); index++) {
      final entry = await array.get(index);
      if (entry is PdfString) {
        names.add(entry.decodeMappingText());
      } else if (entry is PdfName) {
        names.add(entry.getValue());
      }
    }
    return names;
  }

  /// Decides whether [fieldName] is locked by this dictionary.
  ///
  /// `Include` locks the listed fields and their descendants; `Exclude` locks
  /// everything but those.
  Future<bool> locksField(String fieldName) async {
    final action = await getFieldLockAction();
    if (action == null) return false;
    if (action == LockAction.all) return true;
    final listed = await getFieldLockFields();
    final named = listed
        .any((name) => name == fieldName || fieldName.startsWith('$name.'));
    return action == LockAction.include ? named : !named;
  }

  /// The `/Action` name of table 233 for [action].
  static PdfName actionName(LockAction action) {
    switch (action) {
      case LockAction.all:
        return PdfName.all;
      case LockAction.include:
        return PdfName.include;
      case LockAction.exclude:
        return PdfName.exclude;
    }
  }

  /// The [LockAction] for an `/Action` name, or null when unknown.
  static LockAction? actionOf(PdfName? name) {
    switch (name?.getValue()) {
      case 'All':
        return LockAction.all;
      case 'Include':
        return LockAction.include;
      case 'Exclude':
        return LockAction.exclude;
    }
    return null;
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
