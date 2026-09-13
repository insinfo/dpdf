import '../pdf_name.dart';

import '../../geom/rectangle.dart';
import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Text markup annotation: highlight, underline, squiggly-underline or
/// strikeout.
///
/// See ISO 32000-1:2008, 12.5.6.10, Table 179.
class PdfTextMarkupAnnotation extends PdfMarkupAnnotation {
  static final PdfName subtypeHighlight = PdfName.highlight;
  static final PdfName subtypeUnderline = PdfName.underline;
  static final PdfName subtypeSquiggly = PdfName.squiggly;
  static final PdfName subtypeStrikeOut = PdfName.strikeOut;

  static final Set<String> _subtypes = {
    subtypeHighlight.getValue(),
    subtypeUnderline.getValue(),
    subtypeSquiggly.getValue(),
    subtypeStrikeOut.getValue(),
  };

  PdfTextMarkupAnnotation(super.pdfObject);

  /// Creates a text markup annotation of [subtype] with the required
  /// `/QuadPoints` array (Table 179).
  PdfTextMarkupAnnotation.fromRect(
      super.rect, PdfName subtype, List<double> quadPoints)
      : super.fromRect() {
    if (!_subtypes.contains(subtype.getValue())) {
      throw ArgumentError.value(subtype, 'subtype',
          'Text markup subtype shall be /Highlight, /Underline, /Squiggly or /StrikeOut');
    }
    put(PdfName.subtype, subtype);
    setQuadPoints(quadPoints);
  }

  /// Creates a highlight annotation.
  factory PdfTextMarkupAnnotation.highlight(
          Rectangle rect, List<double> quadPoints) =>
      PdfTextMarkupAnnotation.fromRect(rect, subtypeHighlight, quadPoints);

  /// Creates an underline annotation.
  factory PdfTextMarkupAnnotation.underline(
          Rectangle rect, List<double> quadPoints) =>
      PdfTextMarkupAnnotation.fromRect(rect, subtypeUnderline, quadPoints);

  /// Creates a squiggly-underline annotation.
  factory PdfTextMarkupAnnotation.squiggly(
          Rectangle rect, List<double> quadPoints) =>
      PdfTextMarkupAnnotation.fromRect(rect, subtypeSquiggly, quadPoints);

  /// Creates a strikeout annotation.
  factory PdfTextMarkupAnnotation.strikeOut(
          Rectangle rect, List<double> quadPoints) =>
      PdfTextMarkupAnnotation.fromRect(rect, subtypeStrikeOut, quadPoints);

  @override
  PdfName getSubtype() {
    final subtype = pdfRepresentation().getMap()?[PdfName.subtype];
    return subtype is PdfName ? subtype : subtypeHighlight;
  }

  /// Sets `/QuadPoints`, an `8 x n` array of quadrilateral coordinates.
  PdfTextMarkupAnnotation setQuadPoints(List<double> coordinates) {
    put(PdfName.intern('QuadPoints'), buildQuadPoints(coordinates));
    return this;
  }

  /// Gets `/QuadPoints`.
  Future<List<double>?> getQuadPoints() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('QuadPoints'));
}
