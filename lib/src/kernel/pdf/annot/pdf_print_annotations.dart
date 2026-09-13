import '../pdf_array.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

import 'pdf_annotation.dart';
import 'pdf_annotation_border.dart';

/// Printer's mark annotation.
///
/// See ISO 32000-1:2008, 12.5.6.20 and 14.11.3 "Printer's Marks". The
/// annotation carries no subtype specific table of its own; it relies on the
/// common entries of Table 164 plus the printer's mark form dictionary
/// entries of 14.11.3 (`/MN`).
class PdfPrinterMarkAnnotation extends PdfAnnotation {
  PdfPrinterMarkAnnotation(super.pdfObject);

  PdfPrinterMarkAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.printerMark);
  }

  @override
  PdfName getSubtype() => PdfName.printerMark;

  /// Sets `/MN`, the printer's mark name of 14.11.3, Table 328.
  PdfPrinterMarkAnnotation setMarkName(PdfName name) {
    put(PdfName.intern('MN'), name);
    return this;
  }

  /// Gets `/MN`.
  Future<PdfName?> getMarkName() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('MN'));
}

/// Trap network annotation.
///
/// See ISO 32000-1:2008, 12.5.6.21 and 14.11.6 "Trapping Support". A page
/// shall have at most one trap network annotation, and it shall always be the
/// last element of the page's `/Annots` array.
class PdfTrapNetworkAnnotation extends PdfAnnotation {
  PdfTrapNetworkAnnotation(super.pdfObject);

  PdfTrapNetworkAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.trapNet);
  }

  @override
  PdfName getSubtype() => PdfName.trapNet;

  /// Sets `/LastModified`, the date the page was last modified (Table 326).
  PdfTrapNetworkAnnotation setLastModified(PdfDate date) {
    put(PdfName.intern('LastModified'), PdfString(date.getValue()));
    return this;
  }

  /// Gets `/LastModified` as written.
  Future<PdfString?> getLastModified() async =>
      await pdfRepresentation().stringEntry(PdfName.intern('LastModified'));

  /// Sets `/Version`, the objects that define the page's appearance.
  PdfTrapNetworkAnnotation setVersion(PdfArray version) {
    put(PdfName.version, version);
    return this;
  }

  /// Gets `/Version`.
  Future<PdfArray?> getVersion() async =>
      await pdfRepresentation().arrayEntry(PdfName.version);

  /// Sets `/AnnotStates`, the appearance states of the annotations listed by
  /// `/Version` (Table 326).
  PdfTrapNetworkAnnotation setAnnotationStates(PdfArray states) {
    put(PdfName.intern('AnnotStates'), states);
    return this;
  }

  /// Gets `/AnnotStates`.
  Future<PdfArray?> getAnnotationStates() async =>
      await pdfRepresentation().arrayEntry(PdfName.intern('AnnotStates'));

  /// Sets `/FontFauxing`, the fonts that may be substituted (Table 326).
  PdfTrapNetworkAnnotation setFontFauxing(PdfArray fonts) {
    put(PdfName.intern('FontFauxing'), fonts);
    return this;
  }

  /// Gets `/FontFauxing`.
  Future<PdfArray?> getFontFauxing() async =>
      await pdfRepresentation().arrayEntry(PdfName.intern('FontFauxing'));
}

/// Fixed print dictionary of a watermark annotation.
///
/// See ISO 32000-1:2008, 12.5.6.22, Table 191.
class PdfFixedPrint extends PdfObjectWrapper<PdfDictionary> {
  PdfFixedPrint(super.pdfObject);

  /// Creates a fixed print dictionary with the required `/Type /FixedPrint`.
  PdfFixedPrint.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.intern('FixedPrint'));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/Matrix`, the six-number transformation applied to the annotation
  /// rectangle before rendering. Default: the identity matrix.
  PdfFixedPrint setMatrix(List<double> matrix) {
    if (matrix.length != 6) {
      throw ArgumentError.value(
          matrix, 'matrix', 'Fixed print /Matrix shall contain six numbers');
    }
    pdfRepresentation().put(PdfName.matrix, PdfArray.fromDoubles(matrix));
    return this;
  }

  /// Gets `/Matrix`; the default is the identity matrix per Table 191.
  Future<List<double>> getMatrix() async =>
      await readNumberArray(pdfRepresentation(), PdfName.matrix) ??
      const [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];

  /// Sets `/H`, the horizontal translation as a fraction of the media width.
  PdfFixedPrint setHorizontalTranslation(double fraction) {
    pdfRepresentation().put(PdfName.intern('H'), PdfNumber(fraction));
    return this;
  }

  /// Gets `/H`; the default is 0 per Table 191.
  Future<double> getHorizontalTranslation() async =>
      (await pdfRepresentation().numberEntry(PdfName.intern('H')))
          ?.getValue() ??
      0.0;

  /// Sets `/V`, the vertical translation as a fraction of the media height.
  PdfFixedPrint setVerticalTranslation(double fraction) {
    pdfRepresentation().put(PdfName.v, PdfNumber(fraction));
    return this;
  }

  /// Gets `/V`; the default is 0 per Table 191.
  Future<double> getVerticalTranslation() async =>
      (await pdfRepresentation().numberEntry(PdfName.v))?.getValue() ?? 0.0;
}

/// Watermark annotation.
///
/// See ISO 32000-1:2008, 12.5.6.22, Table 190.
class PdfWatermarkAnnotation extends PdfAnnotation {
  PdfWatermarkAnnotation(super.pdfObject);

  PdfWatermarkAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.watermark);
  }

  @override
  PdfName getSubtype() => PdfName.watermark;

  /// Sets `/FixedPrint`, describing how the annotation is drawn relative to
  /// the target media dimensions.
  PdfWatermarkAnnotation setFixedPrint(PdfFixedPrint fixedPrint) {
    put(PdfName.intern('FixedPrint'), fixedPrint.pdfRepresentation());
    return this;
  }

  /// Gets `/FixedPrint`.
  Future<PdfFixedPrint?> getFixedPrint() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('FixedPrint'));
    return dictionary == null ? null : PdfFixedPrint(dictionary);
  }
}
