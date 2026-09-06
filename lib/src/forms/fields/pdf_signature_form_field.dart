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

  PdfSignatureFormField(PdfDictionary pdfObject) : super(pdfObject);
  
  /// Creates a signature form field for or a given document.
  static PdfSignatureFormField createFromDocument(PdfDocument document) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.ft, PdfName.sig);
    PdfSignatureFormField field = PdfSignatureFormField(dict);
    field.makeIndirect(document);
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
    PdfObject? sigLockDict = await getPdfObject().get(PdfName.lock, true);
    return sigLockDict is PdfDictionary ? PdfSigFieldLock(sigLockDict) : null;
  }

  /// Sets the background layer that is present when creating the signature field.
  void setBackgroundLayer(PdfFormXObject n0) {
    this.n0 = n0;
    regenerateField();
  }
  
  /// Gets the background layer that is present when creating the signature field if it was set.
  PdfFormXObject? getBackgroundLayer() => n0;

  /// Sets the signature appearance layer that contains information about the signature.
  void setSignatureAppearanceLayer(PdfFormXObject n2) {
    this.n2 = n2;
    regenerateField();
  }
  
  /// Gets the signature appearance layer that contains information about the signature if it was set.
  PdfFormXObject? getSignatureAppearanceLayer() => n2;

  /// Indicates that the existing appearances needs to be reused as a background.
  void setReuseAppearance(bool reuseAppearance) {
    this.reuseAppearance = reuseAppearance;
  }
  
  /// Gets the value which indicates if the existing appearances needs to be reused as a background.
  bool isReuseAppearance() => reuseAppearance;

  /// Sets the boolean value which indicates if page rotation should be ignored for the signature appearance.
  void setIgnorePageRotation(bool ignore) {
    this.ignorePageRotation = ignore;
  }
  
  /// Gets the boolean value which indicates if we need to ignore page rotation for the signature appearance.
  bool isPageRotationIgnored() => ignorePageRotation;

  @override
  Future<bool> regenerateField() async {
    PdfDictionary ap = PdfDictionary();
    if (n2 != null) {
      // Must use indirect reference for the appearance XObject
      final ref = n2!.getPdfObject().getIndirectReference();
      if (ref != null) {
        ap.put(PdfName.n, ref);
      } else {
        // If no indirect reference, put directly (less ideal but functional)
        ap.put(PdfName.n, n2!.getPdfObject());
      }
    }
    put(PdfName.ap, ap);
    setModified();
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
