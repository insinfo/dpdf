import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';

import '../action/pdf_action.dart';
import '../navigation/pdf_destination.dart';
import 'pdf_annotation.dart';
import 'pdf_annotation_border.dart';

/// Link annotation.
///
/// See ISO 32000-1:2008, 12.5.6.5, Table 173. A link annotation is not a
/// markup annotation (Table 169), so it derives from [PdfAnnotation].
class PdfLinkAnnotation extends PdfAnnotation {
  /// `/H` value: no highlighting.
  static final PdfName highlightModeNone = PdfName.intern('N');

  /// `/H` value: invert the contents of the annotation rectangle.
  static final PdfName highlightModeInvert = PdfName.intern('I');

  /// `/H` value: invert the annotation's border.
  static final PdfName highlightModeOutline = PdfName.intern('O');

  /// `/H` value: display the annotation as if pushed below the page.
  static final PdfName highlightModePush = PdfName.intern('P');

  PdfLinkAnnotation(super.pdfObject);

  PdfLinkAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.link);
  }

  @override
  PdfName getSubtype() => PdfName.link;

  /// Sets `/A`, the action performed when the link is activated. Table 173
  /// forbids `/Dest` when `/A` is present, so any `/Dest` is removed.
  PdfLinkAnnotation setAction(PdfAction action) {
    pdfRepresentation().remove(PdfName.dest);
    put(PdfName.a, action.pdfRepresentation());
    return this;
  }

  /// Gets `/A`.
  Future<PdfDictionary?> getAction() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.a);

  /// Sets `/Dest`. Table 173 forbids `/Dest` when `/A` is present, so any
  /// `/A` entry is removed.
  PdfLinkAnnotation setDestination(PdfDestination destination) {
    pdfRepresentation().remove(PdfName.a);
    put(PdfName.dest, destination.pdfRepresentation());
    return this;
  }

  /// Gets `/Dest` as written.
  Future<PdfObject?> getDestinationObject() async =>
      await pdfRepresentation().get(PdfName.dest, true);

  /// Sets `/H`, the highlighting mode.
  PdfLinkAnnotation setHighlightMode(PdfName mode) {
    put(PdfName.intern('H'), mode);
    return this;
  }

  /// Gets `/H`; the default is [highlightModeInvert] per Table 173.
  Future<PdfName> getHighlightMode() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('H')) ??
      highlightModeInvert;

  /// Sets `/PA`, the URI action formerly associated with this annotation.
  PdfLinkAnnotation setPreviousAction(PdfAction action) {
    put(PdfName.intern('PA'), action.pdfRepresentation());
    return this;
  }

  /// Gets `/PA`.
  Future<PdfDictionary?> getPreviousAction() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('PA'));

  /// Sets `/QuadPoints`, an `8 x n` array delimiting the activation region.
  PdfLinkAnnotation setQuadPoints(List<double> coordinates) {
    put(PdfName.intern('QuadPoints'), buildQuadPoints(coordinates));
    return this;
  }

  /// Gets `/QuadPoints`.
  Future<List<double>?> getQuadPoints() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('QuadPoints'));

  /// Sets `/BS`, the border style dictionary.
  PdfLinkAnnotation setBorderStyleDictionary(PdfBorderStyle style) {
    put(PdfName.bs, style.pdfRepresentation());
    return this;
  }

  /// Reads `/QuadPoints` as a list of quadrilaterals, each with 8 numbers.
  Future<List<List<double>>?> getQuadrilaterals() async {
    final flat = await getQuadPoints();
    if (flat == null) return null;
    return [
      for (var i = 0; i + 8 <= flat.length; i += 8) flat.sublist(i, i + 8)
    ];
  }

  /// Convenience for building the `/QuadPoints` array from separate quads.
  static PdfArray quadrilaterals(List<List<double>> quads) {
    final flat = <double>[];
    for (final quad in quads) {
      if (quad.length != 8) {
        throw ArgumentError.value(
            quad, 'quads', 'Every quadrilateral needs exactly 8 numbers');
      }
      flat.addAll(quad);
    }
    return buildQuadPoints(flat);
  }
}
