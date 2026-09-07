import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

/// Represents a PDF Extended Graphics State.
class PdfExtGState extends PdfObjectWrapper<PdfDictionary> {
  PdfExtGState([PdfDictionary? pdfObject])
      : super(pdfObject ?? PdfDictionary());

  @override
  bool requiresIndirectStorage() => true;

  Future<double?> getLineWidth() async =>
      await pdfRepresentation().decimalEntry(PdfName.lw);

  Future<int?> getLineCapStyle() async =>
      await pdfRepresentation().integerEntry(PdfName.lc);

  Future<int?> getLineJoinStyle() async =>
      await pdfRepresentation().integerEntry(PdfName.lj);

  Future<double?> getMiterLimit() async =>
      await pdfRepresentation().decimalEntry(PdfName.ml);

  Future<PdfArray?> getDashPattern() async =>
      await pdfRepresentation().arrayEntry(PdfName.d);

  Future<PdfName?> getRenderingIntent() async =>
      await pdfRepresentation().nameEntry(PdfName.ri);

  Future<bool?> getStrokeOverprintFlag() async =>
      await pdfRepresentation().flagEntry(PdfName.op);

  Future<bool?> getFillOverprintFlag() async =>
      await pdfRepresentation().flagEntry(PdfName.opUppercase);

  Future<int?> getOverprintMode() async =>
      await pdfRepresentation().integerEntry(PdfName.opm);

  Future<PdfArray?> resolveTypeface() async =>
      await pdfRepresentation().arrayEntry(PdfName.fontG);

  Future<PdfObject?> getBlackGenerationFunction() async =>
      await pdfRepresentation().get(PdfName.bg, true);

  Future<PdfObject?> getBlackGenerationFunction2() async =>
      await pdfRepresentation().get(PdfName.bg2, true);

  Future<PdfObject?> getUndercolorRemovalFunction() async =>
      await pdfRepresentation().get(PdfName.ucr, true);

  Future<PdfObject?> getUndercolorRemovalFunction2() async =>
      await pdfRepresentation().get(PdfName.ucr2, true);

  Future<PdfObject?> getTransferFunction() async =>
      await pdfRepresentation().get(PdfName.tr, true);

  Future<PdfObject?> getTransferFunction2() async =>
      await pdfRepresentation().get(PdfName.tr2, true);

  Future<PdfObject?> getHalftone() async =>
      await pdfRepresentation().get(PdfName.ht, true);

  Future<double?> getFlatnessTolerance() async =>
      await pdfRepresentation().decimalEntry(PdfName.fl);

  Future<double?> getSmoothnessTolerance() async =>
      await pdfRepresentation().decimalEntry(PdfName.sm);

  Future<bool?> getAutomaticStrokeAdjustmentFlag() async =>
      await pdfRepresentation().flagEntry(PdfName.sa);

  Future<PdfObject?> getBlendMode() async =>
      await pdfRepresentation().get(PdfName.bm, true);

  Future<PdfObject?> getSoftMask() async =>
      await pdfRepresentation().get(PdfName.smaskG, true);

  Future<double?> getStrokeOpacity() async =>
      await pdfRepresentation().decimalEntry(PdfName.caUppercase);

  Future<double?> getFillOpacity() async =>
      await pdfRepresentation().decimalEntry(PdfName.ca);

  Future<bool?> getAlphaSourceFlag() async =>
      await pdfRepresentation().flagEntry(PdfName.ais);

  Future<bool?> getTextKnockoutFlag() async =>
      await pdfRepresentation().flagEntry(PdfName.tk);

  PdfExtGState setFillOpacity(double opacity) {
    pdfRepresentation().put(PdfName.ca, PdfNumber(opacity));
    return this;
  }

  PdfExtGState setStrokeOpacity(double opacity) {
    pdfRepresentation().put(PdfName.caUppercase, PdfNumber(opacity));
    return this;
  }

  /// Defines a transparency-group soft mask for subsequent painting.
  PdfExtGState setSoftMask(PdfDictionary softMask) {
    pdfRepresentation().put(PdfName.smaskG, softMask);
    return this;
  }
}
