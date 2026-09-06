import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../../geom/rectangle.dart';
import '../action/pdf_action.dart';
import 'pdf_annotation.dart';

class CraftPdfWidgetAnnotation extends CraftPdfAnnotation {
  static const int hidden = 1;
  static const int visibleButDoesNotPrint = 2;
  static const int hiddenButPrintable = 3;
  static const int visible = 4;

  CraftPdfWidgetAnnotation(CraftPdfDictionary pdfObject) : super(pdfObject);

  CraftPdfWidgetAnnotation.fromRect(CraftRectangle rect)
      : super.fromRect(rect) {
    put(CraftPdfName.subtype, CraftPdfName.widget);
  }

  @override
  CraftPdfName getSubtype() {
    return CraftPdfName.widget;
  }

  CraftPdfWidgetAnnotation setVisibility(int visibility) {
    switch (visibility) {
      case hidden:
        put(
            CraftPdfName.f,
            CraftPdfNumber.fromInt(
                CraftPdfAnnotation.print | CraftPdfAnnotation.hidden));
        break;
      case visibleButDoesNotPrint:
        // Visible (no Hidden/NoView) and No Print
        put(CraftPdfName.f, CraftPdfNumber.fromInt(0));
        break;
      case hiddenButPrintable:
        put(
            CraftPdfName.f,
            CraftPdfNumber.fromInt(
                CraftPdfAnnotation.print | CraftPdfAnnotation.noView));
        break;
      case visible:
      default:
        put(CraftPdfName.f, CraftPdfNumber.fromInt(CraftPdfAnnotation.print));
        break;
    }
    return this;
  }

  CraftPdfWidgetAnnotation setAction(CraftPdfAction action) {
    put(CraftPdfName.a, action.pdfRepresentation());
    return this;
  }

  Future<CraftPdfWidgetAnnotation> setAdditionalAction(
      CraftPdfName key, CraftPdfAction action) async {
    await CraftPdfAction.setAdditionalAction(this, key, action);
    return this;
  }

  /// Sets the parent dictionary.
  CraftPdfWidgetAnnotation setParent(CraftPdfDictionary parent) {
    put(CraftPdfName.parent, parent);
    return this;
  }

  /// Gets the parent dictionary.
  Future<CraftPdfDictionary?> getParent() async {
    return await pdfRepresentation().dictionaryEntry(CraftPdfName.parent);
  }

  /// Sets the highlight mode.
  ///
  /// [mode] can be [highlightNone], [highlightInvert], [highlightOutline], or [highlightPush].
  CraftPdfWidgetAnnotation setHighlightMode(CraftPdfName mode) {
    put(CraftPdfName.intern('H'), mode);
    return this;
  }

  /// Gets the highlight mode.
  Future<CraftPdfName?> getHighlightMode() async {
    return await pdfRepresentation().nameEntry(CraftPdfName.intern('H'));
  }

  // Highlight modes
  static final CraftPdfName highlightNone = CraftPdfName.intern('N');
  static final CraftPdfName highlightInvert = CraftPdfName.intern('I');
  static final CraftPdfName highlightOutline = CraftPdfName.intern('O');
  static final CraftPdfName highlightPush = CraftPdfName.intern('P');
  static final CraftPdfName highlightToggle = CraftPdfName.intern('T');
}
