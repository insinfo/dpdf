import '../pdf_array.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_string.dart';

import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Free text annotation.
///
/// See ISO 32000-1:2008, 12.5.6.6, Table 174.
class PdfFreeTextAnnotation extends PdfMarkupAnnotation {
  /// Quadding: left justified.
  static const int alignLeft = 0;

  /// Quadding: centered.
  static const int alignCenter = 1;

  /// Quadding: right justified.
  static const int alignRight = 2;

  /// `/IT` value: a plain free-text annotation (text box comment).
  static final PdfName intentFreeText = PdfName.intern('FreeText');

  /// `/IT` value: a callout, associated with an area through `/CL`.
  static final PdfName intentFreeTextCallout =
      PdfName.intern('FreeTextCallout');

  /// `/IT` value: a click-to-type or typewriter object.
  static final PdfName intentFreeTextTypeWriter =
      PdfName.intern('FreeTextTypeWriter');

  PdfFreeTextAnnotation(super.pdfObject);

  /// Creates a free text annotation. `/DA` is required by Table 174, so the
  /// default appearance string is part of the constructor.
  PdfFreeTextAnnotation.fromRect(super.rect, String defaultAppearance)
      : super.fromRect() {
    put(PdfName.subtype, PdfName.freeText);
    put(PdfName.da, PdfString(defaultAppearance));
  }

  @override
  PdfName getSubtype() => PdfName.freeText;

  /// Sets `/DA`, the default appearance string (required).
  PdfFreeTextAnnotation setDefaultAppearance(String defaultAppearance) {
    put(PdfName.da, PdfString(defaultAppearance));
    return this;
  }

  /// Gets `/DA`.
  Future<String?> getDefaultAppearance() async =>
      (await pdfRepresentation().stringEntry(PdfName.da))?.getValue();

  /// Sets `/Q`, the quadding code.
  PdfFreeTextAnnotation setJustification(int quadding) {
    if (quadding < alignLeft || quadding > alignRight) {
      throw ArgumentError.value(
          quadding, 'quadding', 'Free text /Q shall be 0, 1 or 2');
    }
    put(PdfName.q, PdfNumber.fromInt(quadding));
    return this;
  }

  /// Gets `/Q`; the default is [alignLeft] per Table 174.
  Future<int> getJustification() async =>
      await pdfRepresentation().integerEntry(PdfName.q) ?? alignLeft;

  /// Sets `/DS`, the default style string.
  PdfFreeTextAnnotation setDefaultStyle(PdfString style) {
    put(PdfName.ds, style);
    return this;
  }

  /// Gets `/DS`.
  Future<PdfString?> getDefaultStyle() async =>
      await pdfRepresentation().stringEntry(PdfName.ds);

  /// Sets `/CL`, the callout line. Table 174 allows four numbers
  /// `[x1 y1 x2 y2]` or six numbers `[x1 y1 x2 y2 x3 y3]`.
  PdfFreeTextAnnotation setCalloutLine(List<double> coordinates) {
    if (coordinates.length != 4 && coordinates.length != 6) {
      throw ArgumentError.value(coordinates, 'coordinates',
          'Free text /CL shall contain four or six numbers');
    }
    put(PdfName.intern('CL'), PdfArray.fromDoubles(coordinates));
    return this;
  }

  /// Gets `/CL`.
  Future<List<double>?> getCalloutLine() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('CL'));

  /// Sets `/BE`, the border effect dictionary.
  PdfFreeTextAnnotation setBorderEffect(PdfBorderEffect effect) {
    put(PdfName.intern('BE'), effect.pdfRepresentation());
    return this;
  }

  /// Gets `/BE`.
  Future<PdfBorderEffect?> getBorderEffect() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('BE'));
    return dictionary == null ? null : PdfBorderEffect(dictionary);
  }

  /// Sets `/RD`: the differences between `/Rect` and the inner rectangle in
  /// which the text is displayed (left, top, right, bottom).
  PdfFreeTextAnnotation setRectangleDifferences(
      double left, double top, double right, double bottom) {
    put(PdfName.intern('RD'),
        buildRectangleDifferences(left, top, right, bottom));
    return this;
  }

  /// Gets `/RD`.
  Future<List<double>?> getRectangleDifferences() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('RD'));

  /// Sets `/LE`, the line ending style drawn at `(x1, y1)` of `/CL`.
  PdfFreeTextAnnotation setLineEnding(PdfName lineEnding) {
    put(PdfName.intern('LE'), lineEnding);
    return this;
  }

  /// Gets `/LE`; the default is `/None` per Table 174.
  Future<PdfName> getLineEnding() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('LE')) ??
      PdfLineEnding.none;
}
