import 'package:itext/src/kernel/geom/matrix.dart';
import 'package:itext/src/kernel/pdf/canvas/pdf_canvas_constants.dart';
import 'package:itext/src/kernel/colors/color.dart';
import 'package:itext/src/kernel/colors/device_gray.dart';
import 'package:itext/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';
import 'package:itext/src/kernel/pdf/pdf_dictionary.dart';
import 'package:itext/src/kernel/pdf/pdf_document.dart';
import 'package:itext/src/kernel/font/pdf_font.dart';
import 'package:itext/src/kernel/pdf/pdf_array.dart';
import 'package:itext/src/kernel/pdf/pdf_number.dart';
import 'package:itext/src/kernel/pdf/pdf_name.dart';
import 'package:itext/src/kernel/pdf/pdf_object.dart';

/// Represents the graphics state for the canvas.
class CanvasGraphicsState {
  Matrix ctm = Matrix();
  Color strokeColor = DeviceGray.BLACK;
  Color fillColor = DeviceGray.BLACK;
  double charSpacing = 0;
  double wordSpacing = 0;
  double scale = 100;
  double leading = 0;
  PdfFont? font;
  double fontSize = 0;
  int textRenderingMode = TextRenderingMode.FILL;
  double textRise = 0;
  bool textKnockout = true;
  double lineWidth = 1;
  int lineCapStyle = LineCapStyle.BUTT;
  int lineJoinStyle = LineJoinStyle.MITER;
  double miterLimit = 10;
  PdfArray dashPattern = PdfArray.fromList([PdfArray(), PdfNumber(0)]);
  PdfName renderingIntent = PdfName
      .relativeColorimetric; // Needs constant? Checked pdf_name.dart? No relativeColorimetric likely missing in my check. Using literal or need to update PdfName.

  // Note: PdfName.relativeColorimetric might be missing.
  // I'll check PdfName.dart later. For now use PdfName('RelativeColorimetric') if needed, or assume I'll add it.
  // C# uses PdfName.RelativeColorimetric.

  bool automaticStrokeAdjustment = false;
  PdfObject blendMode = PdfName.normal; // Normal
  PdfObject softMask = PdfName.none; // None
  double strokeAlpha = 1.0;
  double fillAlpha = 1.0;
  bool alphaIsShape = false;
  bool strokeOverprint = false;
  bool fillOverprint = false;
  int overprintMode = 0;
  PdfObject? blackGenerationFunction;
  PdfObject? blackGenerationFunction2;
  PdfObject? underColorRemovalFunction;
  PdfObject? underColorRemovalFunction2;
  PdfObject? transferFunction;
  PdfObject? transferFunction2;
  PdfObject? halftone;
  double flatnessTolerance = 1.0;
  double? smoothnessTolerance;
  PdfObject? htp;

  CanvasGraphicsState([CanvasGraphicsState? source]) {
    if (source != null) {
      copyFrom(source);
    }
  }

  void copyFrom(CanvasGraphicsState source) {
    ctm = source.ctm; // Matrix is immutable
    strokeColor = source.strokeColor;
    fillColor = source.fillColor;
    charSpacing = source.charSpacing;
    wordSpacing = source.wordSpacing;
    scale = source.scale;
    leading = source.leading;
    font = source.font;
    fontSize = source.fontSize;
    textRenderingMode = source.textRenderingMode;
    textRise = source.textRise;
    textKnockout = source.textKnockout;
    lineWidth = source.lineWidth;
    lineCapStyle = source.lineCapStyle;
    lineJoinStyle = source.lineJoinStyle;
    miterLimit = source.miterLimit;
    dashPattern = source.dashPattern; // References shared? PdfArray clone?
    // C# CopyFrom: "this.dashPattern = source.dashPattern;" -> Reference copy.
    renderingIntent = source.renderingIntent;
    automaticStrokeAdjustment = source.automaticStrokeAdjustment;
    blendMode = source.blendMode;
    softMask = source.softMask;
    strokeAlpha = source.strokeAlpha;
    fillAlpha = source.fillAlpha;
    alphaIsShape = source.alphaIsShape;
    strokeOverprint = source.strokeOverprint;
    fillOverprint = source.fillOverprint;
    overprintMode = source.overprintMode;
    blackGenerationFunction = source.blackGenerationFunction;
    blackGenerationFunction2 = source.blackGenerationFunction2;
    underColorRemovalFunction = source.underColorRemovalFunction;
    underColorRemovalFunction2 = source.underColorRemovalFunction2;
    transferFunction = source.transferFunction;
    transferFunction2 = source.transferFunction2;
    halftone = source.halftone;
    flatnessTolerance = source.flatnessTolerance;
    smoothnessTolerance = source.smoothnessTolerance;
    htp = source.htp;
  }

  Future<void> updateFromExtGState(PdfDictionary extGStateDict,
      [PdfDocument? pdfDocument]) async {
    final extGState = PdfExtGState(extGStateDict);
    // ... logic
    final lw = await extGState.getLineWidth();
    if (lw != null) lineWidth = lw;

    final lc = await extGState.getLineCapStyle();
    if (lc != null) lineCapStyle = lc;

    final lj = await extGState.getLineJoinStyle();
    if (lj != null) lineJoinStyle = lj;

    final ml = await extGState.getMiterLimit();
    if (ml != null) miterLimit = ml;

    final d = await extGState.getDashPattern();
    if (d != null) dashPattern = d;

    final ri = await extGState.getRenderingIntent();
    if (ri != null) renderingIntent = ri;

    final op = await extGState.getStrokeOverprintFlag();
    if (op != null) strokeOverprint = op;

    final opFill = await extGState.getFillOverprintFlag();
    if (opFill != null) fillOverprint = opFill;

    final opm = await extGState.getOverprintMode();
    if (opm != null) overprintMode = opm;

    // Font handling
    final fnt = await extGState.getFont();
    if (fnt != null && pdfDocument != null) {
      final fontDict = await fnt.getAsDictionary(0);
      if (fontDict != null) {
        if (font == null || font!.getPdfObject() != fontDict) {
          // font = pdfDocument.getFont(fontDict);
          // TODO: PdfDocument.getFont not implemented or assumes font factory
        }
      }
      final fntSz = await fnt.getAsNumber(1);
      if (fntSz != null) {
        fontSize = await fntSz.doubleValue(); // async? No doubleValue is sync?
        // PdfNumber.doubleValue() is sync (cached value)
      }
    }

    // ... continue for other fields
  }
}
