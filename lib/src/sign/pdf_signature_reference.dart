import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import '../kernel/pdf/pdf_string.dart';
import '../forms/pdf_sig_field_lock.dart';
import 'access_permissions.dart';

/// Names of ISO 32000-1 table 253/254/256 that the kernel does not intern.
class SignatureReferenceNames {
  SignatureReferenceNames._();

  /// `/SigRef`, the `/Type` of a signature reference dictionary.
  static final PdfName sigRef = PdfName.intern('SigRef');

  /// `/TransformParams`, the `/Type` of a transform parameters dictionary.
  static final PdfName transformParamsType = PdfName.intern('TransformParams');

  /// `/Data`, required when the transform method is FieldMDP.
  static final PdfName data = PdfName.intern('Data');

  /// `/DigestMethod` of a signature reference dictionary.
  static final PdfName digestMethod = PdfName.intern('DigestMethod');

  /// `/Changes` of a signature dictionary (table 252).
  static final PdfName changes = PdfName.intern('Changes');

  /// `/1.2`, the only valid transform parameters version.
  static final PdfName version12 = PdfName.intern('1.2');
}

/// Transform method of a signature reference dictionary, ISO 32000-1 12.8.2.
enum SignatureTransformMethod {
  /// Detects modifications relative to a certification signature (12.8.2.2).
  docMdp,

  /// Detects modifications that invalidate a usage rights signature (12.8.2.3).
  ur,

  /// Detects modifications to a list of form fields (12.8.2.4).
  fieldMdp,
}

/// A signature reference dictionary, ISO 32000-1 table 253.
///
/// The dictionary is always a direct object because a signature dictionary that
/// carries a byte range digest may not contain indirect values; the single
/// exception is `/Data`, which table 253 explicitly defines as an indirect
/// reference.
class PdfSignatureReference extends PdfObjectWrapper<PdfDictionary> {
  /// Wraps an existing signature reference dictionary.
  PdfSignatureReference(super.dictionary);

  /// Builds the DocMDP reference of a certification signature (12.8.2.2).
  ///
  /// [permissions] is written as the `/P` transform parameter. `/Data` shall
  /// point at the object the analysis starts from, in practice the catalog.
  factory PdfSignatureReference.docMdp(AccessPermissions permissions,
      {PdfObject? data, String? digestMethod}) {
    final parameters = PdfDictionary();
    parameters.put(PdfName.type, SignatureReferenceNames.transformParamsType);
    parameters.put(PdfName.p, PdfNumber.fromInt(docMdpPermissionOf(permissions)));
    parameters.put(PdfName.v, SignatureReferenceNames.version12);
    return PdfSignatureReference._build(
        PdfName.docMDP, parameters, data, digestMethod);
  }

  /// Builds a FieldMDP reference from a signature field lock dictionary.
  ///
  /// ISO 32000-1 12.8.2.4 requires the `/Action` and `/Fields` entries to be
  /// copied out of the lock dictionary, because the transform parameters
  /// dictionary cannot reference it indirectly.
  factory PdfSignatureReference.fieldMdp(LockAction action,
      {List<String> fields = const [],
      PdfObject? data,
      String? digestMethod}) {
    final parameters = PdfDictionary();
    parameters.put(PdfName.type, SignatureReferenceNames.transformParamsType);
    parameters.put(PdfName.action, PdfSigFieldLock.actionName(action));
    if (action != LockAction.all) {
      final array = PdfArray();
      for (final field in fields) {
        array.add(PdfString(field));
      }
      parameters.put(PdfName.fields, array);
    }
    parameters.put(PdfName.v, SignatureReferenceNames.version12);
    return PdfSignatureReference._build(
        PdfName.fieldMDP, parameters, data, digestMethod);
  }

  factory PdfSignatureReference._build(PdfName method, PdfDictionary parameters,
      PdfObject? data, String? digestMethod) {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, SignatureReferenceNames.sigRef);
    dictionary.put(PdfName.transformMethod, method);
    dictionary.put(PdfName.transformParams, parameters);
    if (data != null) {
      dictionary.put(SignatureReferenceNames.data, data);
    }
    if (digestMethod != null) {
      dictionary.put(SignatureReferenceNames.digestMethod,
          PdfName.intern(digestMethod));
    }
    return PdfSignatureReference(dictionary);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// The `/TransformMethod`, or null when absent or unknown.
  Future<SignatureTransformMethod?> getTransformMethod() async {
    final name = await pdfRepresentation().nameEntry(PdfName.transformMethod);
    if (name == null) return null;
    switch (name.getValue()) {
      case 'DocMDP':
        return SignatureTransformMethod.docMdp;
      case 'UR':
      case 'UR3':
        return SignatureTransformMethod.ur;
      case 'FieldMDP':
        return SignatureTransformMethod.fieldMdp;
    }
    return null;
  }

  /// The `/TransformParams` dictionary, or null when absent.
  Future<PdfDictionary?> getTransformParams() async =>
      pdfRepresentation().dictionaryEntry(PdfName.transformParams);

  /// The `/DigestMethod` name, or null when absent.
  Future<String?> getDigestMethod() async =>
      (await pdfRepresentation()
              .nameEntry(SignatureReferenceNames.digestMethod))
          ?.getValue();

  /// The DocMDP `/P` value, clamped to the 1..3 range of table 254.
  ///
  /// Returns null when this is not a DocMDP reference. An absent `/P` falls
  /// back to the default value 2 mandated by table 254.
  Future<int?> getDocMdpPermission() async {
    if (await getTransformMethod() != SignatureTransformMethod.docMdp) {
      return null;
    }
    final parameters = await getTransformParams();
    if (parameters == null) return 2;
    final number = await parameters.numberEntry(PdfName.p);
    if (number == null) return 2;
    final value = number.intValue();
    if (value < 1 || value > 3) return null;
    return value;
  }

  /// The FieldMDP `/Action`, or null when this is not a FieldMDP reference.
  Future<LockAction?> getFieldMdpAction() async {
    if (await getTransformMethod() != SignatureTransformMethod.fieldMdp) {
      return null;
    }
    final parameters = await getTransformParams();
    final name = await parameters?.nameEntry(PdfName.action);
    return PdfSigFieldLock.actionOf(name);
  }

  /// The FieldMDP `/Fields` names, empty when the entry is absent.
  Future<List<String>> getFieldMdpFields() async {
    final parameters = await getTransformParams();
    return readFieldNames(await parameters?.arrayEntry(PdfName.fields));
  }

  /// Reads an array of field name text strings, skipping foreign entries.
  static Future<List<String>> readFieldNames(PdfArray? array) async {
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

  /// Maps [AccessPermissions] onto the `/P` values of table 254.
  static int docMdpPermissionOf(AccessPermissions permissions) {
    switch (permissions) {
      case AccessPermissions.noChangesPermitted:
        return 1;
      case AccessPermissions.formFieldsModification:
        return 2;
      case AccessPermissions.annotationModification:
        return 3;
      case AccessPermissions.unspecified:
        return 2;
    }
  }

  /// Maps a `/P` value of table 254 back onto [AccessPermissions].
  static AccessPermissions accessPermissionsOf(int? permission) {
    switch (permission) {
      case 1:
        return AccessPermissions.noChangesPermitted;
      case 2:
        return AccessPermissions.formFieldsModification;
      case 3:
        return AccessPermissions.annotationModification;
      default:
        return AccessPermissions.unspecified;
    }
  }

  /// Reads the `/Reference` array of a signature dictionary (table 252).
  static Future<List<PdfSignatureReference>> readAll(
      PdfDictionary signatureDictionary) async {
    final result = <PdfSignatureReference>[];
    final array = await signatureDictionary.arrayEntry(PdfName.reference);
    if (array == null) return result;
    for (var index = 0; index < array.size(); index++) {
      final entry = await array.get(index);
      if (entry is PdfDictionary) {
        result.add(PdfSignatureReference(entry));
      }
    }
    return result;
  }
}
