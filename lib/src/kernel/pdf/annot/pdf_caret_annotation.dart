import '../pdf_name.dart';

import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Caret annotation, a visual symbol indicating text edits.
///
/// See ISO 32000-1:2008, 12.5.6.11, Table 180.
class PdfCaretAnnotation extends PdfMarkupAnnotation {
  /// `/Sy` value: a new paragraph symbol is associated with the caret.
  static final PdfName symbolParagraph = PdfName.intern('P');

  /// `/Sy` value: no symbol is associated with the caret.
  static final PdfName symbolNone = PdfName.intern('None');

  PdfCaretAnnotation(super.pdfObject);

  PdfCaretAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.caret);
  }

  @override
  PdfName getSubtype() => PdfName.caret;

  /// Sets `/RD`, the differences between `/Rect` and the caret boundaries.
  PdfCaretAnnotation setRectangleDifferences(
      double left, double top, double right, double bottom) {
    put(PdfName.intern('RD'),
        buildRectangleDifferences(left, top, right, bottom));
    return this;
  }

  /// Gets `/RD`.
  Future<List<double>?> getRectangleDifferences() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('RD'));

  /// Sets `/Sy`, the caret symbol.
  PdfCaretAnnotation setSymbol(PdfName symbol) {
    if (symbol != symbolParagraph && symbol != symbolNone) {
      throw ArgumentError.value(
          symbol, 'symbol', 'Caret /Sy shall be /P or /None');
    }
    put(PdfName.intern('Sy'), symbol);
    return this;
  }

  /// Gets `/Sy`; the default is [symbolNone] per Table 180.
  Future<PdfName> getSymbol() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('Sy')) ?? symbolNone;
}
