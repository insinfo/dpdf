import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';

import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Shared behaviour for square and circle annotations.
///
/// See ISO 32000-1:2008, 12.5.6.8, Table 177.
abstract class PdfSquareCircleAnnotation extends PdfMarkupAnnotation {
  PdfSquareCircleAnnotation(super.pdfObject);

  PdfSquareCircleAnnotation.fromRect(super.rect) : super.fromRect();

  /// Sets `/IC`, the interior colour filling the rectangle or ellipse.
  PdfSquareCircleAnnotation setInteriorColor(List<double> components) {
    put(PdfName.intern('IC'), PdfAnnotationColor.toArray(components));
    return this;
  }

  /// Gets `/IC`.
  Future<List<double>?> getInteriorColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.intern('IC'));

  /// Sets `/BE`, the border effect dictionary.
  PdfSquareCircleAnnotation setBorderEffect(PdfBorderEffect effect) {
    put(PdfName.intern('BE'), effect.pdfRepresentation());
    return this;
  }

  /// Gets `/BE`.
  Future<PdfBorderEffect?> getBorderEffect() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('BE'));
    return dictionary == null ? null : PdfBorderEffect(dictionary);
  }

  /// Sets `/RD`, the differences between `/Rect` and the actual boundaries of
  /// the underlying square or circle.
  PdfSquareCircleAnnotation setRectangleDifferences(
      double left, double top, double right, double bottom) {
    put(PdfName.intern('RD'),
        buildRectangleDifferences(left, top, right, bottom));
    return this;
  }

  /// Gets `/RD`.
  Future<List<double>?> getRectangleDifferences() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('RD'));
}

/// Square annotation (`/Subtype /Square`), ISO 32000-1:2008, 12.5.6.8.
class PdfSquareAnnotation extends PdfSquareCircleAnnotation {
  PdfSquareAnnotation(super.pdfObject);

  PdfSquareAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.square);
  }

  @override
  PdfName getSubtype() => PdfName.square;
}

/// Circle annotation (`/Subtype /Circle`), ISO 32000-1:2008, 12.5.6.8.
class PdfCircleAnnotation extends PdfSquareCircleAnnotation {
  PdfCircleAnnotation(super.pdfObject);

  PdfCircleAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.circle);
  }

  @override
  PdfName getSubtype() => PdfName.circle;
}

/// Shared behaviour for polygon and polyline annotations.
///
/// See ISO 32000-1:2008, 12.5.6.9, Table 178.
abstract class PdfPolyAnnotation extends PdfMarkupAnnotation {
  /// `/IT` value: the polygon functions as a cloud object.
  static final PdfName intentPolygonCloud = PdfName.intern('PolygonCloud');

  /// `/IT` value: the polyline functions as a dimension.
  static final PdfName intentPolyLineDimension =
      PdfName.intern('PolyLineDimension');

  /// `/IT` value: the polygon functions as a dimension.
  static final PdfName intentPolygonDimension =
      PdfName.intern('PolygonDimension');

  PdfPolyAnnotation(super.pdfObject);

  PdfPolyAnnotation.fromRect(super.rect) : super.fromRect();

  /// Sets `/Vertices`, the alternating x and y coordinates of every vertex.
  PdfPolyAnnotation setVertices(List<double> vertices) {
    if (vertices.isEmpty || vertices.length % 2 != 0) {
      throw ArgumentError.value(vertices, 'vertices',
          '/Vertices shall hold alternating x and y coordinates');
    }
    put(PdfName.intern('Vertices'), PdfArray.fromDoubles(vertices));
    return this;
  }

  /// Gets `/Vertices`.
  Future<List<double>?> getVertices() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('Vertices'));

  /// Sets `/IC`, the interior colour used to fill the line endings.
  PdfPolyAnnotation setInteriorColor(List<double> components) {
    put(PdfName.intern('IC'), PdfAnnotationColor.toArray(components));
    return this;
  }

  /// Gets `/IC`.
  Future<List<double>?> getInteriorColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.intern('IC'));

  /// Sets `/Measure`, a measure dictionary describing scale and units.
  PdfPolyAnnotation setMeasure(PdfDictionary measure) {
    put(PdfName.intern('Measure'), measure);
    return this;
  }

  /// Gets `/Measure`.
  Future<PdfDictionary?> getMeasure() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('Measure'));
}

/// Polygon annotation (`/Subtype /Polygon`), ISO 32000-1:2008, 12.5.6.9.
class PdfPolygonAnnotation extends PdfPolyAnnotation {
  PdfPolygonAnnotation(super.pdfObject);

  PdfPolygonAnnotation.fromRect(super.rect, List<double> vertices)
      : super.fromRect() {
    put(PdfName.subtype, PdfName.polygon);
    setVertices(vertices);
  }

  @override
  PdfName getSubtype() => PdfName.polygon;

  /// Sets `/BE`, meaningful only for polygon annotations (Table 178).
  PdfPolygonAnnotation setBorderEffect(PdfBorderEffect effect) {
    put(PdfName.intern('BE'), effect.pdfRepresentation());
    return this;
  }

  /// Gets `/BE`.
  Future<PdfBorderEffect?> getBorderEffect() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('BE'));
    return dictionary == null ? null : PdfBorderEffect(dictionary);
  }
}

/// Polyline annotation (`/Subtype /PolyLine`), ISO 32000-1:2008, 12.5.6.9.
class PdfPolyLineAnnotation extends PdfPolyAnnotation {
  PdfPolyLineAnnotation(super.pdfObject);

  PdfPolyLineAnnotation.fromRect(super.rect, List<double> vertices)
      : super.fromRect() {
    put(PdfName.subtype, PdfName.polyLine);
    setVertices(vertices);
  }

  @override
  PdfName getSubtype() => PdfName.polyLine;

  /// Sets `/LE`, meaningful only for polyline annotations (Table 178).
  PdfPolyLineAnnotation setLineEndings(PdfName start, PdfName end) {
    put(PdfName.intern('LE'), PdfArray.fromList([start, end]));
    return this;
  }

  /// Gets `/LE`; the default is `[/None /None]` per Table 178.
  Future<List<PdfName>> getLineEndings() async {
    final names =
        await readNameArray(pdfRepresentation(), PdfName.intern('LE'));
    if (names == null || names.length != 2) {
      return [PdfLineEnding.none, PdfLineEnding.none];
    }
    return names;
  }
}
