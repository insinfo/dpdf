import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_stream.dart';

import 'pdf_annotation.dart';
import 'pdf_annotation_border.dart';

/// 3D annotation.
///
/// Listed in ISO 32000-1:2008, Table 169 and specified in 13.6.2
/// "3D Annotations", Table 298.
class Pdf3DAnnotation extends PdfAnnotation {
  /// `/3DD` is required; it is the 3D stream or 3D reference dictionary that
  /// specifies the artwork.
  Pdf3DAnnotation(super.pdfObject);

  Pdf3DAnnotation.fromRect(super.rect, PdfObject artwork) : super.fromRect() {
    put(PdfName.subtype, PdfName.threeD);
    setArtwork(artwork);
  }

  @override
  PdfName getSubtype() => PdfName.threeD;

  /// Sets `/3DD`, the 3D stream or 3D reference dictionary.
  Pdf3DAnnotation setArtwork(PdfObject artwork) {
    put(PdfName.intern('3DD'), artwork);
    return this;
  }

  /// Gets `/3DD` as written.
  Future<PdfObject?> getArtwork() async =>
      await pdfRepresentation().get(PdfName.intern('3DD'), true);

  /// Sets `/3DV`, the default initial view of the 3D artwork.
  Pdf3DAnnotation setDefaultView(PdfObject view) {
    put(PdfName.intern('3DV'), view);
    return this;
  }

  /// Gets `/3DV` as written.
  Future<PdfObject?> getDefaultView() async =>
      await pdfRepresentation().get(PdfName.intern('3DV'), true);

  /// Sets `/3DA`, the activation dictionary of Table 299.
  Pdf3DAnnotation setActivation(PdfDictionary activation) {
    put(PdfName.intern('3DA'), activation);
    return this;
  }

  /// Gets `/3DA`.
  Future<PdfDictionary?> getActivation() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('3DA'));

  /// Sets `/3DI`, whether the annotation intercepts mouse clicks.
  Pdf3DAnnotation setInteractive(bool interactive) {
    put(PdfName.intern('3DI'), PdfBoolean(interactive));
    return this;
  }

  /// Gets `/3DI`; the default is true per Table 298.
  Future<bool> isInteractive() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('3DI')))
          ?.getValue() ??
      true;

  /// Sets `/3DB`, the 3D view box in annotation coordinates.
  Pdf3DAnnotation setViewBox(List<double> viewBox) {
    if (viewBox.length != 4) {
      throw ArgumentError.value(
          viewBox, 'viewBox', '/3DB shall contain four numbers');
    }
    put(PdfName.intern('3DB'), PdfArray.fromDoubles(viewBox));
    return this;
  }

  /// Gets `/3DB`.
  Future<List<double>?> getViewBox() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('3DB'));

  /// Builds a minimal 3D stream (`/Type /3D`) carrying [artwork] bytes with
  /// the given `/Subtype` (`/U3D` or `/PRC`), as described in Table 300.
  static PdfStream createArtworkStream(PdfStream stream, PdfName subtype) {
    stream.put(PdfName.type, PdfName.threeD);
    stream.put(PdfName.subtype, subtype);
    return stream;
  }
}
