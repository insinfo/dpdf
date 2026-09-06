import 'package:pdfcraft/src/kernel/pdf/pdf_object.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_array.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_number.dart';

/// Represents a PDF Extended Graphics State.
class CraftPdfExtGState extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfExtGState([CraftPdfDictionary? pdfObject])
      : super(pdfObject ?? CraftPdfDictionary());

  @override
  bool requiresIndirectStorage() => true;

  Future<double?> getLineWidth() async =>
      await pdfRepresentation().decimalEntry(CraftPdfName.lw);

  Future<int?> getLineCapStyle() async =>
      await pdfRepresentation().integerEntry(CraftPdfName.lc);

  Future<int?> getLineJoinStyle() async =>
      await pdfRepresentation().integerEntry(CraftPdfName.lj);

  Future<double?> getMiterLimit() async =>
      await pdfRepresentation().decimalEntry(CraftPdfName.ml);

  Future<CraftPdfArray?> getDashPattern() async =>
      await pdfRepresentation().arrayEntry(CraftPdfName.d);

  Future<CraftPdfName?> getRenderingIntent() async =>
      await pdfRepresentation().nameEntry(CraftPdfName.ri);

  Future<bool?> getStrokeOverprintFlag() async =>
      await pdfRepresentation().flagEntry(CraftPdfName.op);

  Future<bool?> getFillOverprintFlag() async =>
      await pdfRepresentation().flagEntry(CraftPdfName.opUppercase);

  Future<int?> getOverprintMode() async =>
      await pdfRepresentation().integerEntry(CraftPdfName.opm);

  Future<CraftPdfArray?> resolveTypeface() async =>
      await pdfRepresentation().arrayEntry(CraftPdfName.fontG);

  Future<CraftPdfObject?> getBlackGenerationFunction() async =>
      await pdfRepresentation().get(CraftPdfName.bg, true);

  Future<CraftPdfObject?> getBlackGenerationFunction2() async =>
      await pdfRepresentation().get(CraftPdfName.bg2, true);

  Future<CraftPdfObject?> getUndercolorRemovalFunction() async =>
      await pdfRepresentation().get(CraftPdfName.ucr, true);

  Future<CraftPdfObject?> getUndercolorRemovalFunction2() async =>
      await pdfRepresentation().get(CraftPdfName.ucr2, true);

  Future<CraftPdfObject?> getTransferFunction() async =>
      await pdfRepresentation().get(CraftPdfName.tr, true);

  Future<CraftPdfObject?> getTransferFunction2() async =>
      await pdfRepresentation().get(CraftPdfName.tr2, true);

  Future<CraftPdfObject?> getHalftone() async =>
      await pdfRepresentation().get(CraftPdfName.ht, true);

  Future<double?> getFlatnessTolerance() async =>
      await pdfRepresentation().decimalEntry(CraftPdfName.fl);

  Future<double?> getSmoothnessTolerance() async =>
      await pdfRepresentation().decimalEntry(CraftPdfName.sm);

  Future<bool?> getAutomaticStrokeAdjustmentFlag() async =>
      await pdfRepresentation().flagEntry(CraftPdfName.sa);

  Future<CraftPdfObject?> getBlendMode() async =>
      await pdfRepresentation().get(CraftPdfName.bm, true);

  Future<CraftPdfObject?> getSoftMask() async =>
      await pdfRepresentation().get(CraftPdfName.smaskG, true);

  Future<double?> getStrokeOpacity() async =>
      await pdfRepresentation().decimalEntry(CraftPdfName.caUppercase);

  Future<double?> getFillOpacity() async =>
      await pdfRepresentation().decimalEntry(CraftPdfName.ca);

  Future<bool?> getAlphaSourceFlag() async =>
      await pdfRepresentation().flagEntry(CraftPdfName.ais);

  Future<bool?> getTextKnockoutFlag() async =>
      await pdfRepresentation().flagEntry(CraftPdfName.tk);

  CraftPdfExtGState setFillOpacity(double opacity) {
    pdfRepresentation().put(CraftPdfName.ca, CraftPdfNumber(opacity));
    return this;
  }

  CraftPdfExtGState setStrokeOpacity(double opacity) {
    pdfRepresentation().put(CraftPdfName.caUppercase, CraftPdfNumber(opacity));
    return this;
  }
}
