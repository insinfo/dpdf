import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../action/pdf_action.dart';
import 'pdf_annotation.dart';

class PdfWidgetAnnotation extends PdfAnnotation {
  static const int hidden = 1;
  static const int visibleButDoesNotPrint = 2;
  static const int hiddenButPrintable = 3;
  static const int visible = 4;

  PdfWidgetAnnotation(super.pdfObject);

  PdfWidgetAnnotation.fromRect(super.rect) : super.fromRect() {
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
    put(PdfName.a, action.pdfRepresentation());
    return this;
  }

  Future<PdfWidgetAnnotation> setAdditionalAction(
      PdfName key, PdfAction action) async {
    await PdfAction.setAdditionalAction(this, key, action);
    return this;
  }

  /// Sets the parent dictionary.
  PdfWidgetAnnotation setParent(PdfDictionary parent) {
    put(PdfName.parent, parent);
    return this;
  }

  /// Gets the parent dictionary.
  Future<PdfDictionary?> getParent() async {
    return await pdfRepresentation().dictionaryEntry(PdfName.parent);
  }

  /// Sets the highlight mode.
  ///
  /// [mode] can be [highlightNone], [highlightInvert], [highlightOutline], or [highlightPush].
  PdfWidgetAnnotation setHighlightMode(PdfName mode) {
    put(PdfName.intern('H'), mode);
    return this;
  }

  /// Gets the highlight mode.
  Future<PdfName?> getHighlightMode() async {
    return await pdfRepresentation().nameEntry(PdfName.intern('H'));
  }

  // Highlight modes
  static final PdfName highlightNone = PdfName.intern('N');
  static final PdfName highlightInvert = PdfName.intern('I');
  static final PdfName highlightOutline = PdfName.intern('O');
  static final PdfName highlightPush = PdfName.intern('P');
  static final PdfName highlightToggle = PdfName.intern('T');
}
