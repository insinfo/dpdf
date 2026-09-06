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
  bool isWrappedObjectMustBeIndirect() => true;

  Future<double?> getLineWidth() async =>
      await getPdfObject().getAsFloat(PdfName.lw);

  Future<int?> getLineCapStyle() async =>
      await getPdfObject().getAsInt(PdfName.lc);

  Future<int?> getLineJoinStyle() async =>
      await getPdfObject().getAsInt(PdfName.lj);

  Future<double?> getMiterLimit() async =>
      await getPdfObject().getAsFloat(PdfName.ml);

  Future<PdfArray?> getDashPattern() async =>
      await getPdfObject().getAsArray(PdfName.d);

  Future<PdfName?> getRenderingIntent() async =>
      await getPdfObject().getAsName(PdfName.ri);

  Future<bool?> getStrokeOverprintFlag() async =>
      await getPdfObject().getAsBool(PdfName.op);

  Future<bool?> getFillOverprintFlag() async =>
      await getPdfObject().getAsBool(PdfName.opUppercase);

  Future<int?> getOverprintMode() async =>
      await getPdfObject().getAsInt(PdfName.opm);

  Future<PdfArray?> getFont() async =>
      await getPdfObject().getAsArray(PdfName.fontG);

  Future<PdfObject?> getBlackGenerationFunction() async =>
      await getPdfObject().get(PdfName.bg, true);

  Future<PdfObject?> getBlackGenerationFunction2() async =>
      await getPdfObject().get(PdfName.bg2, true);

  Future<PdfObject?> getUndercolorRemovalFunction() async =>
      await getPdfObject().get(PdfName.ucr, true);

  Future<PdfObject?> getUndercolorRemovalFunction2() async =>
      await getPdfObject().get(PdfName.ucr2, true);

  Future<PdfObject?> getTransferFunction() async =>
      await getPdfObject().get(PdfName.tr, true);

  Future<PdfObject?> getTransferFunction2() async =>
      await getPdfObject().get(PdfName.tr2, true);

  Future<PdfObject?> getHalftone() async =>
      await getPdfObject().get(PdfName.ht, true);

  Future<double?> getFlatnessTolerance() async =>
      await getPdfObject().getAsFloat(PdfName.fl);

  Future<double?> getSmoothnessTolerance() async =>
      await getPdfObject().getAsFloat(PdfName.sm);

  Future<bool?> getAutomaticStrokeAdjustmentFlag() async =>
      await getPdfObject().getAsBool(PdfName.sa);

  Future<PdfObject?> getBlendMode() async =>
      await getPdfObject().get(PdfName.bm, true);

  Future<PdfObject?> getSoftMask() async =>
      await getPdfObject().get(PdfName.smaskG, true);

  Future<double?> getStrokeOpacity() async =>
      await getPdfObject().getAsFloat(PdfName.caUppercase);

  Future<double?> getFillOpacity() async =>
      await getPdfObject().getAsFloat(PdfName.ca);

  Future<bool?> getAlphaSourceFlag() async =>
      await getPdfObject().getAsBool(PdfName.ais);

  Future<bool?> getTextKnockoutFlag() async =>
      await getPdfObject().getAsBool(PdfName.tk);

  PdfExtGState setFillOpacity(double opacity) {
    getPdfObject().put(PdfName.ca, PdfNumber(opacity));
    return this;
  }

  PdfExtGState setStrokeOpacity(double opacity) {
    getPdfObject().put(PdfName.caUppercase, PdfNumber(opacity));
    return this;
  }
}
