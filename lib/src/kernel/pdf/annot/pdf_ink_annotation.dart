import '../pdf_name.dart';

import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Ink annotation, a freehand "scribble" made of one or more disjoint paths.
///
/// See ISO 32000-1:2008, 12.5.6.13, Table 182.
class PdfInkAnnotation extends PdfMarkupAnnotation {
  PdfInkAnnotation(super.pdfObject);

  /// Creates an ink annotation. `/InkList` is required by Table 182.
  PdfInkAnnotation.fromRect(super.rect, List<List<double>> inkList)
      : super.fromRect() {
    put(PdfName.subtype, PdfName.ink);
    setInkList(inkList);
  }

  @override
  PdfName getSubtype() => PdfName.ink;

  /// Sets `/InkList`, an array of stroked paths. Every path is a series of
  /// alternating x and y coordinates.
  PdfInkAnnotation setInkList(List<List<double>> inkList) {
    if (inkList.isEmpty) {
      throw ArgumentError.value(
          inkList, 'inkList', '/InkList shall contain at least one path');
    }
    for (final path in inkList) {
      if (path.isEmpty || path.length % 2 != 0) {
        throw ArgumentError.value(inkList, 'inkList',
            'Every ink path shall hold alternating x and y coordinates');
      }
    }
    put(PdfName.intern('InkList'), buildNumberMatrix(inkList));
    return this;
  }

  /// Gets `/InkList`.
  Future<List<List<double>>?> getInkList() =>
      readNumberMatrix(pdfRepresentation(), PdfName.intern('InkList'));
}
