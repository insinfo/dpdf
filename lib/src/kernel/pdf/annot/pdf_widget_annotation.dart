import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import '../action/pdf_action.dart';
import 'pdf_annotation.dart';

class PdfWidgetAnnotation extends PdfAnnotation {
  static const int hidden = 1;
  static const int visibleButDoesNotPrint = 2;
  static const int hiddenButPrintable = 3;
  static const int visible = 4;

  PdfWidgetAnnotation(PdfDictionary pdfObject) : super(pdfObject);

  PdfWidgetAnnotation.fromRect(Rectangle rect) : super.fromRect(rect) {
    put(PdfName.subtype, PdfName.widget);
  }

  @override
  PdfName getSubtype() {
    return PdfName.widget;
  }

  PdfWidgetAnnotation setVisibility(int visibility) {
    switch (visibility) {
      case hidden:
        put(PdfName.f,
            PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.hidden));
        break;
      case visibleButDoesNotPrint:
        // Visible (no Hidden/NoView) and No Print
        put(PdfName.f, PdfNumber.fromInt(0));
        break;
      case hiddenButPrintable:
        put(PdfName.f,
            PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.noView));
        break;
      case visible:
      default:
        put(PdfName.f, PdfNumber.fromInt(PdfAnnotation.print));
        break;
    }
    return this;
  }

  PdfWidgetAnnotation setAction(PdfAction action) {
    put(PdfName.a, action.getPdfObject());
    return this;
  }

  Future<PdfWidgetAnnotation> setAdditionalAction(
      PdfName key, PdfAction action) async {
    await PdfAction.setAdditionalAction(this, key, action);
    return this;
  }

  // TODO: setParent, getParent, setHighlightMode, etc.
}
