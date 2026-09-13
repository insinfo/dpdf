import '../pdf_boolean.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';

import 'pdf_annotation_border.dart';
import 'pdf_markup_annotation.dart';

/// Redaction annotation.
///
/// See ISO 32000-1:2008, 12.5.6.23, Table 192.
class PdfRedactAnnotation extends PdfMarkupAnnotation {
  /// Quadding: left justified.
  static const int alignLeft = 0;

  /// Quadding: centered.
  static const int alignCenter = 1;

  /// Quadding: right justified.
  static const int alignRight = 2;

  PdfRedactAnnotation(super.pdfObject);

  PdfRedactAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.redact);
  }

  @override
  PdfName getSubtype() => PdfName.redact;

  /// Sets `/QuadPoints`, the `8 x n` array denoting the content region that
  /// is intended to be removed. When absent, `/Rect` denotes that region.
  PdfRedactAnnotation setQuadPoints(List<double> coordinates) {
    put(PdfName.intern('QuadPoints'), buildQuadPoints(coordinates));
    return this;
  }

  /// Gets `/QuadPoints`.
  Future<List<double>?> getQuadPoints() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('QuadPoints'));

  /// Sets `/IC`, the DeviceRGB interior colour filling the redacted region.
  /// Table 192 restricts this entry to three components.
  PdfRedactAnnotation setInteriorColor(List<double> rgb) {
    if (rgb.length != 3) {
      throw ArgumentError.value(rgb, 'rgb',
          'Redaction /IC shall hold three DeviceRGB components (Table 192)');
    }
    put(PdfName.intern('IC'), PdfAnnotationColor.toArray(rgb));
    return this;
  }

  /// Gets `/IC`.
  Future<List<double>?> getInteriorColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.intern('IC'));

  /// Sets `/RO`, the form XObject providing the overlay appearance. It takes
  /// precedence over `/IC`, `/OverlayText`, `/DA` and `/Q`.
  PdfRedactAnnotation setOverlayAppearance(PdfStream overlay) {
    put(PdfName.intern('RO'), overlay);
    return this;
  }

  /// Gets `/RO`.
  Future<PdfStream?> getOverlayAppearance() async =>
      await pdfRepresentation().streamEntry(PdfName.intern('RO'));

  /// Sets `/OverlayText` and, as Table 192 requires whenever `/OverlayText`
  /// is present, the `/DA` appearance string used to format it.
  PdfRedactAnnotation setOverlayText(String text, String defaultAppearance) {
    put(PdfName.intern('OverlayText'), PdfString(text));
    put(PdfName.da, PdfString(defaultAppearance));
    return this;
  }

  /// Gets `/OverlayText`.
  Future<String?> getOverlayText() async =>
      (await pdfRepresentation().stringEntry(PdfName.intern('OverlayText')))
          ?.decodeMappingText();

  /// Gets `/DA`.
  Future<String?> getDefaultAppearance() async =>
      (await pdfRepresentation().stringEntry(PdfName.da))?.getValue();

  /// Sets `/Repeat`, whether the overlay text is repeated to fill the region.
  PdfRedactAnnotation setRepeat(bool repeat) {
    put(PdfName.intern('Repeat'), PdfBoolean(repeat));
    return this;
  }

  /// Gets `/Repeat`; the default is false per Table 192.
  Future<bool> getRepeat() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Repeat')))
          ?.getValue() ??
      false;

  /// Sets `/Q`, the quadding code used to lay out the overlay text.
  PdfRedactAnnotation setJustification(int quadding) {
    if (quadding < alignLeft || quadding > alignRight) {
      throw ArgumentError.value(
          quadding, 'quadding', 'Redaction /Q shall be 0, 1 or 2');
    }
    put(PdfName.q, PdfNumber.fromInt(quadding));
    return this;
  }

  /// Gets `/Q`; the default is [alignLeft] per Table 192.
  Future<int> getJustification() async =>
      await pdfRepresentation().integerEntry(PdfName.q) ?? alignLeft;
}
