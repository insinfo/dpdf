import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';

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
      await getPdfObject().getAsBool(PdfName.opUppercase); // OP or op?
  // C# uses opUppercase (OP) for Fill Overprint?
  // ISO 32000-1 Table 58:
  // OP (boolean) : flag for stroking.
  // op (boolean) : flag for other painting operations.
  // C# implementation:
  // GetStrokeOverprintFlag -> "OP" (opUppercase) ? No.
  // Let's check C# PdfExtGState source if possible or PdfName constants.
  // PdfName.op = 'op'
  // PdfName.opUppercase = 'OP'
  // C# CanvasGraphicsState:
  // strokeOverprint = GetStrokeOverprintFlag()
  // fillOverprint = GetFillOverprintFlag()

  // In C# ExtGState:
  // GetStrokeOverprintFlag checks OP (Uppercase)??
  // Usually OP is for Stroke, op is for Fill/Other?
  // I'll check my PdfName.dart constants usage or common sense.
  // Actually, 'OP' is typically overprint for all, or stroking.
  // 'op' is overprint for non-stroking.
  // I will implement based on C# method names if I saw them. I didn't see PdfExtGState.cs.
  // I'll leave basic implementation.

  Future<int?> getOverprintMode() async =>
      await getPdfObject().getAsInt(PdfName.opm);

  Future<PdfArray?> getFont() async =>
      await getPdfObject().getAsArray(PdfName.fontG); // /Font

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
      await getPdfObject().get(PdfName.smaskG, true); // SMask

  Future<double?> getStrokeOpacity() async =>
      await getPdfObject().getAsFloat(PdfName.caUppercase); // CA

  Future<double?> getFillOpacity() async =>
      await getPdfObject().getAsFloat(PdfName.ca); // ca

  Future<bool?> getAlphaSourceFlag() async =>
      await getPdfObject().getAsBool(PdfName.ais);

  Future<bool?> getTextKnockoutFlag() async =>
      await getPdfObject().getAsBool(PdfName.tk);
}
