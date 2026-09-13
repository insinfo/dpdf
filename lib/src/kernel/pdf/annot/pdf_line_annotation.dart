import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';

import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Line annotation.
///
/// See ISO 32000-1:2008, 12.5.6.7, Table 175.
class PdfLineAnnotation extends PdfMarkupAnnotation {
  /// `/IT` value: the annotation functions as an arrow.
  static final PdfName intentLineArrow = PdfName.intern('LineArrow');

  /// `/IT` value: the annotation functions as a dimension line.
  static final PdfName intentLineDimension = PdfName.intern('LineDimension');

  /// `/CP` value: the caption is centered inside the line.
  static final PdfName captionInline = PdfName.intern('Inline');

  /// `/CP` value: the caption is on top of the line.
  static final PdfName captionTop = PdfName.intern('Top');

  PdfLineAnnotation(super.pdfObject);

  /// Creates a line annotation. `/L` is required by Table 175.
  PdfLineAnnotation.fromRect(super.rect, List<double> line) : super.fromRect() {
    put(PdfName.subtype, PdfName.line);
    setLine(line);
  }

  @override
  PdfName getSubtype() => PdfName.line;

  /// Sets `/L`, the `[x1 y1 x2 y2]` coordinates of the line.
  PdfLineAnnotation setLine(List<double> line) {
    if (line.length != 4) {
      throw ArgumentError.value(
          line, 'line', 'Line /L shall contain four numbers');
    }
    put(PdfName.intern('L'), PdfArray.fromDoubles(line));
    return this;
  }

  /// Gets `/L`.
  Future<List<double>?> getLine() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('L'));

  /// Sets `/LE`, the two line ending styles (Table 176).
  PdfLineAnnotation setLineEndings(PdfName start, PdfName end) {
    put(PdfName.intern('LE'), PdfArray.fromList([start, end]));
    return this;
  }

  /// Gets `/LE`; the default is `[/None /None]` per Table 175.
  Future<List<PdfName>> getLineEndings() async {
    final names =
        await readNameArray(pdfRepresentation(), PdfName.intern('LE'));
    if (names == null || names.length != 2) {
      return [PdfLineEnding.none, PdfLineEnding.none];
    }
    return names;
  }

  /// Sets `/IC`, the interior colour used to fill the line endings.
  PdfLineAnnotation setInteriorColor(List<double> components) {
    put(PdfName.intern('IC'), PdfAnnotationColor.toArray(components));
    return this;
  }

  /// Gets `/IC`.
  Future<List<double>?> getInteriorColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.intern('IC'));

  /// Sets `/LL`, the leader line length. Table 175 makes `/LL` required when
  /// `/LLE` is present.
  PdfLineAnnotation setLeaderLine(double length) {
    put(PdfName.intern('LL'), PdfNumber(length));
    return this;
  }

  /// Gets `/LL`; the default is 0 (no leader lines).
  Future<double> getLeaderLine() async =>
      (await pdfRepresentation().numberEntry(PdfName.intern('LL')))
          ?.getValue() ??
      0.0;

  /// Sets `/LLE`, the non-negative leader line extension length.
  PdfLineAnnotation setLeaderLineExtension(double length) {
    if (length < 0) {
      throw ArgumentError.value(
          length, 'length', 'Line /LLE shall be non-negative');
    }
    put(PdfName.intern('LLE'), PdfNumber(length));
    return this;
  }

  /// Gets `/LLE`; the default is 0.
  Future<double> getLeaderLineExtension() async =>
      (await pdfRepresentation().numberEntry(PdfName.intern('LLE')))
          ?.getValue() ??
      0.0;

  /// Sets `/LLO`, the non-negative leader line offset.
  PdfLineAnnotation setLeaderLineOffset(double offset) {
    if (offset < 0) {
      throw ArgumentError.value(
          offset, 'offset', 'Line /LLO shall be non-negative');
    }
    put(PdfName.intern('LLO'), PdfNumber(offset));
    return this;
  }

  /// Gets `/LLO`.
  Future<double?> getLeaderLineOffset() async =>
      (await pdfRepresentation().numberEntry(PdfName.intern('LLO')))
          ?.getValue();

  /// Sets `/Cap`, whether the contents are replicated as a caption.
  PdfLineAnnotation setCaption(bool caption) {
    put(PdfName.intern('Cap'), PdfBoolean(caption));
    return this;
  }

  /// Gets `/Cap`; the default is false.
  Future<bool> hasCaption() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Cap')))
          ?.getValue() ??
      false;

  /// Sets `/CP`, meaningful only when `/Cap` is true.
  PdfLineAnnotation setCaptionPosition(PdfName position) {
    if (position != captionInline && position != captionTop) {
      throw ArgumentError.value(
          position, 'position', 'Line /CP shall be /Inline or /Top');
    }
    put(PdfName.intern('CP'), position);
    return this;
  }

  /// Gets `/CP`; the default is [captionInline].
  Future<PdfName> getCaptionPosition() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('CP')) ??
      captionInline;

  /// Sets `/CO`, the horizontal and vertical caption offsets.
  PdfLineAnnotation setCaptionOffset(double horizontal, double vertical) {
    put(PdfName.intern('CO'), PdfArray.fromDoubles([horizontal, vertical]));
    return this;
  }

  /// Gets `/CO`; the default is `[0 0]`.
  Future<List<double>> getCaptionOffset() async =>
      await readNumberArray(pdfRepresentation(), PdfName.intern('CO')) ??
      const [0.0, 0.0];

  /// Sets `/Measure`, a measure dictionary describing scale and units.
  PdfLineAnnotation setMeasure(PdfDictionary measure) {
    put(PdfName.intern('Measure'), measure);
    return this;
  }

  /// Gets `/Measure`.
  Future<PdfDictionary?> getMeasure() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('Measure'));
}
