import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';

abstract class PdfAction extends PdfObjectWrapper<PdfDictionary> {
  PdfAction(PdfDictionary pdfObject) : super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  /// Sets an additional action to the annotation/field.
  static Future<void> setAdditionalAction(
      PdfObjectWrapper<PdfDictionary> wrapper,
      PdfName key,
      PdfAction action) async {
    PdfDictionary? aa = await wrapper
        .getPdfObject()
        .getAsDictionary(PdfName.aa); // AA = Additional Actions
    if (aa == null) {
      aa = PdfDictionary();
      wrapper.getPdfObject().put(PdfName.aa, aa);
    }
    aa.put(key, action.getPdfObject());
    action.setModified();
    wrapper.setModified();
  }

  // TODO: Factory MakeAction
}
