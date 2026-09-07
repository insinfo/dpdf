import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/xobject/pdf_form_x_object.dart';
import 'pdf_form_field.dart';
import '../pdf_sig_field_lock.dart';

class CraftPdfSignatureFormField extends CraftPdfFormField {
  bool reuseAppearance = false;
  bool ignorePageRotation = true;
  CraftPdfFormXObject? n0;
  CraftPdfFormXObject? n2;

  CraftPdfSignatureFormField(super.pdfObject);

  /// Creates a signature form field for or a given document.
  static CraftPdfSignatureFormField createFromDocument(
      CraftPdfDocument document) {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.ft, CraftPdfName.sig);
    CraftPdfSignatureFormField field = CraftPdfSignatureFormField(dict);
    field.attachToDocument(document);
    return field;
  }

  @override
  Future<CraftPdfName?> getFormType() async {
    return CraftPdfName.sig;
  }

  @override
  void setValue(Object value) {
    if (value is CraftPdfObject) {
      put(CraftPdfName.v, value);
    } else {
      super.setValue(value);
    }
  }

  Future<CraftPdfSigFieldLock?> getSigFieldLockDictionary() async {
    CraftPdfObject? sigLockDict =
        await pdfRepresentation().get(CraftPdfName.lock, true);
    return sigLockDict is CraftPdfDictionary
        ? CraftPdfSigFieldLock(sigLockDict)
        : null;
  }

  /// Assigns the signature field's background appearance layer.
  void setBackgroundLayer(CraftPdfFormXObject n0) {
    this.n0 = n0;
    regenerateField();
  }

  /// Returns the configured background appearance, when present.
  CraftPdfFormXObject? getBackgroundLayer() => n0;

  /// Sets the signature appearance layer that contains information about the signature.
  void setSignatureAppearanceLayer(CraftPdfFormXObject n2) {
    this.n2 = n2;
    regenerateField();
  }

  /// Returns the configured signature information appearance, when present.
  CraftPdfFormXObject? getSignatureAppearanceLayer() => n2;

  /// Controls reuse of the previous appearance as a background.
  void setReuseAppearance(bool reuseAppearance) {
    this.reuseAppearance = reuseAppearance;
  }

  /// Gets the value which indicates if the existing appearances needs to be reused as a background.
  bool isReuseAppearance() => reuseAppearance;

  /// Sets the boolean value which indicates if page rotation should be ignored for the signature appearance.
  void setIgnorePageRotation(bool ignore) {
    ignorePageRotation = ignore;
  }

  /// Gets the boolean value which indicates if we need to ignore page rotation for the signature appearance.
  bool isPageRotationIgnored() => ignorePageRotation;

  @override
  Future<bool> regenerateField() async {
    CraftPdfDictionary ap = CraftPdfDictionary();
    if (n2 != null) {
      // Must use indirect reference for the appearance XObject
      final ref = n2!.pdfRepresentation().indirectHandle();
      if (ref != null) {
        ap.put(CraftPdfName.n, ref);
      } else {
        // If no indirect reference, put directly (less ideal but functional)
        ap.put(CraftPdfName.n, n2!.pdfRepresentation());
      }
    }
    put(CraftPdfName.ap, ap);
    markChanged();
    return true;
  }

  /// Gets the signature value dictionary.
  Future<CraftPdfDictionary?> getSignatureDictionary() async {
    CraftPdfObject? v = await getValue();
    if (v is CraftPdfDictionary) {
      return v;
    }
    return null;
  }

  /// Checks if this signature field contains a signature.
  Future<bool> isSigned() async {
    return (await getSignatureDictionary()) != null;
  }
}
