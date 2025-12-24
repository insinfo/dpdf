import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/xobject/pdf_form_x_object.dart';
import 'pdf_form_field.dart';
import '../pdf_sig_field_lock.dart';

class PdfSignatureFormField extends PdfFormField {
  bool reuseAppearance = false;
  bool ignorePageRotation = true;
  PdfFormXObject? n0;
  PdfFormXObject? n2;

  PdfSignatureFormField(PdfDictionary pdfObject) : super(pdfObject);

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

  void setBackgroundLayer(PdfFormXObject n0) {
    this.n0 = n0;
    regenerateField();
  }

  void setSignatureAppearanceLayer(PdfFormXObject n2) {
    this.n2 = n2;
    regenerateField();
  }

  void setReuseAppearance(bool reuseAppearance) {
    this.reuseAppearance = reuseAppearance;
  }

  void setIgnorePageRotation(bool ignore) {
    this.ignorePageRotation = ignore;
  }
}
