import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/xobject/pdf_form_x_object.dart';
import 'pdf_form_field.dart';
import '../pdf_sig_field_lock.dart';

class PdfSignatureFormField extends PdfFormField {
  bool reuseAppearance = false;
  bool ignorePageRotation = true;
  PdfFormXObject? n0;
  PdfFormXObject? n2;

  PdfSignatureFormField(super.pdfObject);

  /// Creates a signature form field for or a given document.
  static PdfSignatureFormField createFromDocument(PdfDocument document) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.ft, PdfName.sig);
    PdfSignatureFormField field = PdfSignatureFormField(dict);
    field.attachToDocument(document);
    return field;
  }

  @override
  Future<PdfName?> getFormType() async {
    return PdfName.sig;
  }

  @override
  void setValue(Object value) {
    if (value is PdfObject) {
      put(PdfName.v, value);
    } else {
      super.setValue(value);
    }
  }

  Future<PdfSigFieldLock?> getSigFieldLockDictionary() async {
    PdfObject? sigLockDict = await pdfRepresentation().get(PdfName.lock, true);
    return sigLockDict is PdfDictionary ? PdfSigFieldLock(sigLockDict) : null;
  }

  /// Assigns the signature field's background appearance layer.
  void setBackgroundLayer(PdfFormXObject n0) {
    this.n0 = n0;
    regenerateField();
  }

  /// Returns the configured background appearance, when present.
  PdfFormXObject? getBackgroundLayer() => n0;

  /// Sets the signature appearance layer that contains information about the signature.
  void setSignatureAppearanceLayer(PdfFormXObject n2) {
    this.n2 = n2;
    regenerateField();
  }

  /// Returns the configured signature information appearance, when present.
  PdfFormXObject? getSignatureAppearanceLayer() => n2;

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
    PdfDictionary ap = PdfDictionary();
    if (n2 != null) {
      // Must use indirect reference for the appearance XObject
      final ref = n2!.pdfRepresentation().indirectHandle();
      if (ref != null) {
        ap.put(PdfName.n, ref);
      } else {
        // If no indirect reference, put directly (less ideal but functional)
        ap.put(PdfName.n, n2!.pdfRepresentation());
      }
    }
    put(PdfName.ap, ap);
    markChanged();
    return true;
  }

  /// Gets the signature value dictionary.
  Future<PdfDictionary?> getSignatureDictionary() async {
    PdfObject? v = await getValue();
    if (v is PdfDictionary) {
      return v;
    }
    return null;
  }

  /// Checks if this signature field contains a signature.
  Future<bool> isSigned() async {
    return (await getSignatureDictionary()) != null;
  }
}
