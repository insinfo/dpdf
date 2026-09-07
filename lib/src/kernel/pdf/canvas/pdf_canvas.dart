import 'dart:typed_data';
import 'package:dpdf/src/io/source/byte_utils.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_resources.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/canvas/canvas_graphics_state.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_shading.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_image_x_object.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_form_x_object.dart';
import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/kernel/colors/device_cmyk.dart';
import 'package:dpdf/src/io/font/otf/glyph_line.dart';
import 'package:dpdf/src/kernel/pdf/canvas/bezier.dart';
import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_x_object.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Writes PDF graphics and text operators into content streams.
class CraftPdfCanvas {
  // Constants for operators
  static final Uint8List B = CraftByteUtils.getIsoBytes("B\n");
  static final Uint8List b_low = CraftByteUtils.getIsoBytes("b\n");
  static final Uint8List BDC = CraftByteUtils.getIsoBytes("BDC\n");
  static final Uint8List BI = CraftByteUtils.getIsoBytes("BI\n");
  static final Uint8List BMC = CraftByteUtils.getIsoBytes("BMC\n");
  static final Uint8List BStar = CraftByteUtils.getIsoBytes("B*\n");
  static final Uint8List bStar = CraftByteUtils.getIsoBytes("b*\n");
  static final Uint8List BT = CraftByteUtils.getIsoBytes("BT\n");
  static final Uint8List c_op = CraftByteUtils.getIsoBytes("c\n");
  static final Uint8List cm_op = CraftByteUtils.getIsoBytes("cm\n");
  static final Uint8List cs_op = CraftByteUtils.getIsoBytes("cs\n");
  static final Uint8List CS_op = CraftByteUtils.getIsoBytes("CS\n");
  static final Uint8List d_op = CraftByteUtils.getIsoBytes("d\n");
  static final Uint8List Do_op = CraftByteUtils.getIsoBytes("Do\n");
  static final Uint8List EI = CraftByteUtils.getIsoBytes("EI\n");
  static final Uint8List EMC = CraftByteUtils.getIsoBytes("EMC\n");
  static final Uint8List ET = CraftByteUtils.getIsoBytes("ET\n");
  static final Uint8List f_op = CraftByteUtils.getIsoBytes("f\n");
  static final Uint8List fStar = CraftByteUtils.getIsoBytes("f*\n");
  static final Uint8List G_op = CraftByteUtils.getIsoBytes("G\n");
  static final Uint8List g_op = CraftByteUtils.getIsoBytes("g\n");
  static final Uint8List gs_op = CraftByteUtils.getIsoBytes("gs\n");
  static final Uint8List h_op = CraftByteUtils.getIsoBytes("h\n");
  static final Uint8List i_op = CraftByteUtils.getIsoBytes("i\n");
  static final Uint8List ID = CraftByteUtils.getIsoBytes("ID\n");
  static final Uint8List j_op = CraftByteUtils.getIsoBytes("j\n");
  static final Uint8List J_op = CraftByteUtils.getIsoBytes("J\n");
  static final Uint8List k_op = CraftByteUtils.getIsoBytes("k\n");
  static final Uint8List K_op = CraftByteUtils.getIsoBytes("K\n");
  static final Uint8List l_op = CraftByteUtils.getIsoBytes("l\n");
  static final Uint8List m_op = CraftByteUtils.getIsoBytes("m\n");
  static final Uint8List M_op = CraftByteUtils.getIsoBytes("M\n");
  static final Uint8List n_op = CraftByteUtils.getIsoBytes("n\n");
  static final Uint8List q_op = CraftByteUtils.getIsoBytes("q\n");
  static final Uint8List Q_op = CraftByteUtils.getIsoBytes("Q\n");
  static final Uint8List re_op = CraftByteUtils.getIsoBytes("re\n");
  static final Uint8List RG_op = CraftByteUtils.getIsoBytes("RG\n");
  static final Uint8List rg_op = CraftByteUtils.getIsoBytes("rg\n");
  static final Uint8List ri_op = CraftByteUtils.getIsoBytes("ri\n");
  static final Uint8List S_op = CraftByteUtils.getIsoBytes("S\n");
  static final Uint8List s_op = CraftByteUtils.getIsoBytes("s\n");
  static final Uint8List scn = CraftByteUtils.getIsoBytes("scn\n");
  static final Uint8List SCN = CraftByteUtils.getIsoBytes("SCN\n");
  static final Uint8List sh_op = CraftByteUtils.getIsoBytes("sh\n");
  static final Uint8List Tc = CraftByteUtils.getIsoBytes("Tc\n");
  static final Uint8List Td = CraftByteUtils.getIsoBytes("Td\n");
  static final Uint8List TD = CraftByteUtils.getIsoBytes("TD\n");
  static final Uint8List Tf = CraftByteUtils.getIsoBytes("Tf\n");
  static final Uint8List TJ = CraftByteUtils.getIsoBytes("TJ\n");
  static final Uint8List Tj = CraftByteUtils.getIsoBytes("Tj\n");
  static final Uint8List TL = CraftByteUtils.getIsoBytes("TL\n");
  static final Uint8List Tm = CraftByteUtils.getIsoBytes("Tm\n");
  static final Uint8List Tr = CraftByteUtils.getIsoBytes("Tr\n");
  static final Uint8List Ts = CraftByteUtils.getIsoBytes("Ts\n");
  static final Uint8List TStar = CraftByteUtils.getIsoBytes("T*\n");
  static final Uint8List Tw = CraftByteUtils.getIsoBytes("Tw\n");
  static final Uint8List Tz = CraftByteUtils.getIsoBytes("Tz\n");
  static final Uint8List v_op = CraftByteUtils.getIsoBytes("v\n");
  static final Uint8List w_op = CraftByteUtils.getIsoBytes("w\n");
  static final Uint8List W_op = CraftByteUtils.getIsoBytes("W\n");
  static final Uint8List WStar = CraftByteUtils.getIsoBytes("W*\n");
  static final Uint8List y_op = CraftByteUtils.getIsoBytes("y\n");

  static final PdfDeviceCsGray gray = PdfDeviceCsGray();
  static final PdfDeviceCsRgb rgb = PdfDeviceCsRgb();
  static final PdfDeviceCsCmyk cmyk = PdfDeviceCsCmyk();
  static final PdfSpecialCsPattern pattern = PdfSpecialCsPattern();
  static const double IDENTITY_MATRIX_EPS = 1e-4;

  /// Calculates the Bezier curve points for an arc.
  static List<Float64List> bezierArc(double x1, double y1, double x2, double y2,
      double startAng, double extent) {
    return Bezier.bezierArc(x1, y1, x2, y2, startAng, extent);
  }

  /// Draw an arc on the passed canvas,
  /// inside the bounds determined by two opposite corners.
  CraftPdfCanvas arc(double x1, double y1, double x2, double y2,
      double startAng, double extent,
      [CraftAffineTransform? transform]) {
    List<Float64List> ar = bezierArc(x1, y1, x2, y2, startAng, extent);
    if (ar.isNotEmpty) {
      for (Float64List pt in ar) {
        if (transform != null) {
          transform.transform(pt, 0, pt, 0, (pt.length ~/ 2));
        }
        curveTo(pt[2], pt[3], pt[4], pt[5], pt[6], pt[7]);
      }
    }
    return this;
  }

  List<CraftCanvasGraphicsState> gsStack = [];
  CraftCanvasGraphicsState currentGs = CraftCanvasGraphicsState();
  CraftPdfStream? contentStream;
  CraftPdfResources? resources;
  CraftPdfDocument? document;
  int mcDepth = 0;
  bool drawingOnPage = false;

  CraftCanvasGraphicsState getGraphicsState() => currentGs;

  CraftPdfCanvas(CraftPdfStream contentStream, CraftPdfResources? resources,
      CraftPdfDocument? document) {
    this.contentStream = _ensureStreamDataIsReadyToBeProcessed(contentStream);
    this.resources = resources;
    this.document = document;
  }

  CraftPdfDocument? getDocument() => document;

  static Future<CraftPdfCanvas> fromPage(CraftPdfPage page) async {
    CraftPdfStream? stream;
    final count = await page.contentSegmentCount();
    if (count > 0) {
      final obj = await page.contentSegmentAt(count - 1);
      if (obj is CraftPdfStream) {
        stream = obj;
      }
    }

    final doc = page.pdfRepresentation().indirectHandle()?.getDocument();

    if (stream == null) {
      stream = CraftPdfStream();
      if (doc != null) {
        stream.attachToDocument(doc);
      }
      page.pdfRepresentation().put(CraftPdfName.contents, stream);
    }

    final canvas = CraftPdfCanvas(stream, await page.resourceDirectory(), doc);
    canvas.drawingOnPage = true;
    return canvas;
  }

  static Future<CraftPdfCanvas> fromFormXObject(
      CraftPdfFormXObject xObj, CraftPdfDocument document) async {
    return CraftPdfCanvas(
        xObj.pdfRepresentation(), await xObj.resourceDirectory(), document);
  }

  CraftPdfStream _ensureStreamDataIsReadyToBeProcessed(CraftPdfStream stream) {
    return stream;
  }

  void release() {
    contentStream = null;
    resources = null;
    document = null;
  }

  CraftPdfCanvas saveState() {
    gsStack.add(currentGs.copy());
    contentStream!.getOutputStream().writeBytes(q_op);
    return this;
  }

  CraftPdfCanvas restoreState() {
    if (gsStack.isNotEmpty) {
      currentGs = gsStack.removeLast();
    }
    contentStream!.getOutputStream().writeBytes(Q_op);
    return this;
  }

  CraftPdfCanvas concatMatrix(
      double a, double b, double c, double d, double e, double f) {
    currentGs
        .getCtm()
        .concatenate(CraftAffineTransform.fromValues(a, b, c, d, e, f));
    contentStream!.getOutputStream()
      ..writeDouble(a)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(b)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(c)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(d)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(e)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(f)
      ..writeBytes(CraftByteUtils.getIsoBytes(" cm\n"));
    return this;
  }

  CraftPdfCanvas beginText() {
    contentStream!.getOutputStream().writeBytes(BT);
    return this;
  }

  CraftPdfCanvas endText() {
    contentStream!.getOutputStream().writeBytes(ET);
    return this;
  }

  CraftPdfCanvas moveTo(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(CraftByteUtils.getIsoBytes(" m\n"));
    return this;
  }

  CraftPdfCanvas lineTo(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(CraftByteUtils.getIsoBytes(" l\n"));
    return this;
  }

  CraftPdfCanvas curveTo1(double x1, double y1, double x3, double y3) {
    contentStream!.getOutputStream()
      ..writeDouble(x1)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y1)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(x3)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y3)
      ..writeBytes(CraftByteUtils.getIsoBytes(" v\n"));
    return this;
  }

  CraftPdfCanvas curveTo2(double x2, double y2, double x3, double y3) {
    contentStream!.getOutputStream()
      ..writeDouble(x2)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y2)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(x3)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y3)
      ..writeBytes(CraftByteUtils.getIsoBytes(" y\n"));
    return this;
  }

  CraftPdfCanvas curveTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    contentStream!.getOutputStream()
      ..writeDouble(x1)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y1)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(x2)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y2)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(x3)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y3)
      ..writeBytes(CraftByteUtils.getIsoBytes(" c\n"));
    return this;
  }

  CraftPdfCanvas circle(double x, double y, double r) {
    arc(x - r, y - r, x + r, y + r, 0, 360);
    return this;
  }

  CraftPdfCanvas closePath() {
    contentStream!.getOutputStream().writeBytes(h_op);
    return this;
  }

  CraftPdfCanvas stroke() {
    contentStream!.getOutputStream().writeBytes(S_op);
    return this;
  }

  CraftPdfCanvas closePathStroke() {
    contentStream!.getOutputStream().writeBytes(s_op);
    return this;
  }

  CraftPdfCanvas clip() {
    contentStream!.getOutputStream().writeBytes(W_op);
    contentStream!.getOutputStream().writeBytes(n_op);
    return this;
  }

  CraftPdfCanvas eoClip() {
    contentStream!.getOutputStream().writeBytes(WStar);
    contentStream!.getOutputStream().writeBytes(n_op);
    return this;
  }

  CraftPdfCanvas fill() {
    contentStream!.getOutputStream().writeBytes(f_op);
    return this;
  }

  CraftPdfCanvas eoFill() {
    contentStream!.getOutputStream().writeBytes(fStar);
    return this;
  }

  CraftPdfCanvas fillStroke() {
    contentStream!.getOutputStream().writeBytes(B);
    return this;
  }

  CraftPdfCanvas closePathFillStroke() {
    contentStream!.getOutputStream().writeBytes(b_low);
    return this;
  }

  CraftPdfCanvas eoFillStroke() {
    contentStream!.getOutputStream().writeBytes(BStar);
    return this;
  }

  CraftPdfCanvas closePathEoFillStroke() {
    contentStream!.getOutputStream().writeBytes(bStar);
    return this;
  }

  CraftPdfCanvas newPath() {
    contentStream!.getOutputStream().writeBytes(n_op);
    return this;
  }

  CraftPdfCanvas rectangle(double x, double y, double w, double h) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(w)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(h)
      ..writeBytes(CraftByteUtils.getIsoBytes(" re\n"));
    return this;
  }

  CraftPdfCanvas setCharacterSpacing(double charSpacing) {
    contentStream!.getOutputStream()
      ..writeDouble(charSpacing)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Tc\n"));
    return this;
  }

  CraftPdfCanvas setWordSpacing(double wordSpacing) {
    contentStream!.getOutputStream()
      ..writeDouble(wordSpacing)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Tw\n"));
    return this;
  }

  CraftPdfCanvas setHorizontalScaling(double horizontalScaling) {
    contentStream!.getOutputStream()
      ..writeDouble(horizontalScaling)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Tz\n"));
    return this;
  }

  CraftPdfCanvas setTextRise(double textRise) {
    contentStream!.getOutputStream()
      ..writeDouble(textRise)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Ts\n"));
    return this;
  }

  CraftPdfCanvas setTextRenderingMode(int textRenderingMode) {
    contentStream!.getOutputStream()
      ..writeInteger(textRenderingMode)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Tr\n"));
    return this;
  }

  Future<CraftPdfCanvas> setFontAndSize(CraftPdfFont font, double size) async {
    currentGs.setFont(font);
    currentGs.setFontSize(size);
    CraftPdfName fontName = await resources!.registerTypeface(document!, font);
    contentStream!.getOutputStream()
      ..writeBytes(CraftByteUtils.getIsoBytes("/${fontName.getValue()}"))
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(size)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Tf\n"));
    return this;
  }

  CraftPdfCanvas moveText(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Td\n"));
    return this;
  }

  CraftPdfCanvas moveTextWithLeading(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(CraftByteUtils.getIsoBytes(" TD\n"));
    return this;
  }

  CraftPdfCanvas setTextMatrix(
      double a, double b, double c, double d, double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(a)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(b)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(c)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(d)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(x)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(CraftByteUtils.getIsoBytes(" Tm\n"));
    return this;
  }

  CraftPdfCanvas setTextMatrixSimple(double x, double y) {
    return setTextMatrix(1, 0, 0, 1, x, y);
  }

  CraftPdfCanvas setLeading(double leading) {
    contentStream!.getOutputStream()
      ..writeDouble(leading)
      ..writeBytes(CraftByteUtils.getIsoBytes(" TL\n"));
    return this;
  }

  CraftPdfCanvas newlineText() {
    contentStream!.getOutputStream().writeBytes(TStar);
    return this;
  }

  Future<CraftPdfCanvas> newlineShowText(String text) async {
    final font = currentGs.resolveTypeface();
    if (font == null) {
      // Fallback for missing font
      contentStream!.getOutputStream()
        ..writeBytes(CraftByteUtils.getIsoBytes(
            "(${text.replaceAll('(', '\\(').replaceAll(')', '\\)')})"))
        ..writeBytes(CraftByteUtils.getIsoBytes(" '\n"));
    } else {
      font.writeText(text, contentStream!.getOutputStream());
      contentStream!
          .getOutputStream()
          .writeBytes(CraftByteUtils.getIsoBytes(" '\n"));
    }
    return this;
  }

  CraftPdfCanvas showText(dynamic text) {
    final font = currentGs.resolveTypeface();
    final os = contentStream!.getOutputStream();
    if (text is String) {
      if (font == null) {
        os.writeBytes(CraftByteUtils.getIsoBytes(
            "(${text.replaceAll('(', '\\(').replaceAll(')', '\\)')})"));
      } else {
        font.writeText(text, os);
      }
      os.writeBytes(CraftByteUtils.getIsoBytes(" Tj\n"));
    } else if (text is CraftGlyphLine) {
      if (font == null) {
        _showGlyphLine(text);
      } else {
        font.writeText(text, os);
      }
      os.writeBytes(CraftByteUtils.getIsoBytes(" Tj\n"));
    }
    return this;
  }

  void _showGlyphLine(CraftGlyphLine text) {
    final os = contentStream!.getOutputStream();
    os.writeBytes(CraftByteUtils.getIsoBytes("("));
    for (int i = text.getStart(); i < text.getEnd(); i++) {
      final glyph = text.get(i);
      final unicode = glyph.getUnicode();
      if (unicode != -1) {
        // Simple character output for now (works for standard fonts)
        final char = String.fromCharCode(unicode);
        if (char == '(' || char == ')' || char == '\\') {
          os.writeBytes(CraftByteUtils.getIsoBytes("\\"));
        }
        os.writeBytes(CraftByteUtils.getIsoBytes(char));
      }
    }
    os.writeBytes(CraftByteUtils.getIsoBytes(") Tj\n"));
  }

  CraftPdfCanvas showTextWithAdjustment(List<dynamic> items) {
    contentStream!
        .getOutputStream()
        .writeBytes(CraftByteUtils.getIsoBytes("["));
    for (var item in items) {
      if (item is String) {
        contentStream!.getOutputStream()
          ..writeBytes(CraftByteUtils.getIsoBytes(
              "(${item.replaceAll('(', '\\(').replaceAll(')', '\\)')})"));
      } else if (item is double || item is int) {
        contentStream!.getOutputStream().writeDouble(item.toDouble());
      }
      contentStream!
          .getOutputStream()
          .writeBytes(CraftByteUtils.getIsoBytes(" "));
    }
    contentStream!
        .getOutputStream()
        .writeBytes(CraftByteUtils.getIsoBytes("] TJ\n"));
    return this;
  }

  CraftPdfCanvas newlineShowTextWithSpacing(
      double wordSpacing, double charSpacing, String text) {
    contentStream!.getOutputStream()
      ..writeDouble(wordSpacing)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(charSpacing)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeBytes(CraftByteUtils.getIsoBytes(
          "(${text.replaceAll('(', '\\(').replaceAll(')', '\\)')})"))
      ..writeBytes(CraftByteUtils.getIsoBytes(" \"\n"));
    return this;
  }

  CraftPdfCanvas setLineWidth(double lineWidth) {
    contentStream!.getOutputStream()
      ..writeDouble(lineWidth)
      ..writeBytes(CraftByteUtils.getIsoBytes(" w\n"));
    return this;
  }

  CraftPdfCanvas setLineCap(int lineCap) {
    contentStream!.getOutputStream()
      ..writeInteger(lineCap)
      ..writeBytes(CraftByteUtils.getIsoBytes(" J\n"));
    return this;
  }

  CraftPdfCanvas setLineJoin(int lineJoin) {
    contentStream!.getOutputStream()
      ..writeInteger(lineJoin)
      ..writeBytes(CraftByteUtils.getIsoBytes(" j\n"));
    return this;
  }

  CraftPdfCanvas setMiterLimit(double miterLimit) {
    contentStream!.getOutputStream()
      ..writeDouble(miterLimit)
      ..writeBytes(CraftByteUtils.getIsoBytes(" M\n"));
    return this;
  }

  CraftPdfCanvas setDashPattern(CraftPdfArray dashPattern, [double phase = 0]) {
    contentStream!.getOutputStream()
      ..writePdfObject(dashPattern)
      ..writeBytes(CraftByteUtils.getIsoBytes(" "))
      ..writeDouble(phase)
      ..writeBytes(CraftByteUtils.getIsoBytes(" d\n"));
    return this;
  }

  CraftPdfCanvas setFlatness(double flatness) {
    contentStream!.getOutputStream()
      ..writeDouble(flatness)
      ..writeBytes(CraftByteUtils.getIsoBytes(" i\n"));
    return this;
  }

  CraftPdfCanvas setFillColor(CraftColor color) {
    return _setColor(color, true);
  }

  CraftPdfCanvas setStrokeColor(CraftColor color) {
    return _setColor(color, false);
  }

  CraftPdfCanvas _setColor(CraftColor color, bool fill) {
    if (color is CraftDeviceRgb) {
      contentStream!.getOutputStream()
        ..writeDouble(color.getColorValue()[0])
        ..writeBytes(CraftByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[1])
        ..writeBytes(CraftByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[2])
        ..writeBytes(CraftByteUtils.getIsoBytes(fill ? " rg\n" : " RG\n"));
    } else if (color is CraftDeviceGray) {
      contentStream!.getOutputStream()
        ..writeDouble(color.getColorValue()[0])
        ..writeBytes(CraftByteUtils.getIsoBytes(fill ? " g\n" : " G\n"));
    } else if (color is CraftDeviceCmyk) {
      contentStream!.getOutputStream()
        ..writeDouble(color.getColorValue()[0])
        ..writeBytes(CraftByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[1])
        ..writeBytes(CraftByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[2])
        ..writeBytes(CraftByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[3])
        ..writeBytes(CraftByteUtils.getIsoBytes(fill ? " k\n" : " K\n"));
    }
    return this;
  }

  CraftPdfCanvas setRenderingIntent(CraftPdfName intent) {
    contentStream!.getOutputStream()
      ..writePdfObject(intent)
      ..writeBytes(CraftByteUtils.getIsoBytes(" ri\n"));
    return this;
  }

  Future<CraftPdfCanvas> setExtGState(CraftPdfExtGState gs) async {
    CraftPdfName name =
        await resources!.addExtGState(document!, gs.pdfRepresentation());
    contentStream!.getOutputStream()
      ..writeBytes(CraftByteUtils.getIsoBytes("/${name.getValue()}"))
      ..writeBytes(CraftByteUtils.getIsoBytes(" gs\n"));
    return this;
  }

  Future<CraftPdfCanvas> shading(CraftPdfShading shading) async {
    CraftPdfName name =
        await resources!.addShading(document!, shading.pdfRepresentation());
    contentStream!.getOutputStream()
      ..writeBytes(CraftByteUtils.getIsoBytes("/${name.getValue()}"))
      ..writeBytes(CraftByteUtils.getIsoBytes(" sh\n"));
    return this;
  }

  Future<CraftPdfCanvas> beginMarkedContent(CraftPdfName tag,
      [CraftPdfDictionary? properties]) async {
    if (properties == null) {
      contentStream!.getOutputStream()
        ..writeBytes(CraftByteUtils.getIsoBytes("/${tag.getValue()}"))
        ..writeBytes(CraftByteUtils.getIsoBytes(" BMC\n"));
    } else {
      CraftPdfName name = await resources!.addProperties(document!, properties);
      contentStream!.getOutputStream()
        ..writeBytes(CraftByteUtils.getIsoBytes("/${tag.getValue()}"))
        ..writeBytes(CraftByteUtils.getIsoBytes(" "))
        ..writeBytes(CraftByteUtils.getIsoBytes("/${name.getValue()}"))
        ..writeBytes(CraftByteUtils.getIsoBytes(" BDC\n"));
    }
    mcDepth++;
    return this;
  }

  CraftPdfCanvas endMarkedContent() {
    if (mcDepth > 0) {
      contentStream!.getOutputStream().writeBytes(EMC);
      mcDepth--;
    }
    return this;
  }

  Future<CraftPdfCanvas> addImageAt(CraftImageData image, double x, double y,
      [bool inline = false]) async {
    return addImageWithTransformationMatrix(image, image.getWidth().toDouble(),
        0, 0, image.getHeight().toDouble(), x, y, inline);
  }

  Future<CraftPdfCanvas> addImageWithTransformationMatrix(CraftImageData image,
      double a, double b, double c, double d, double e, double f,
      [bool inline = false]) async {
    if (inline) {
      // ... BI ... ID ... EI
    } else {
      CraftPdfImageXObject imageXObject = CraftPdfImageXObject(image);
      CraftPdfName name = await resources!
          .addXObject(document!, imageXObject.pdfRepresentation());
      saveState();
      concatMatrix(a, b, c, d, e, f);
      contentStream!.getOutputStream()
        ..writeBytes(CraftByteUtils.getIsoBytes("/${name.getValue()}"))
        ..writeBytes(CraftByteUtils.getIsoBytes(" Do\n"));
      restoreState();
    }
    return this;
  }

  Future<CraftPdfCanvas> addXObject(
      CraftPdfXObject xObject, double x, double y) async {
    double a = 1.0;
    double d = 1.0;
    if (xObject is CraftPdfImageXObject) {
      a = xObject.getWidth();
      d = xObject.getHeight();
    }
    return addXObjectWithTransformationMatrix(
        xObject.pdfRepresentation(), a, 0, 0, d, x, y);
  }

  Future<CraftPdfCanvas> addXObjectWithTransformationMatrix(
      CraftPdfStream xObject,
      double a,
      double b,
      double c,
      double d,
      double e,
      double f) async {
    CraftPdfName name = await resources!.addXObject(document!, xObject);
    saveState();
    concatMatrix(a, b, c, d, e, f);
    contentStream!.getOutputStream()
      ..writeBytes(CraftByteUtils.getIsoBytes("/${name.getValue()}"))
      ..writeBytes(CraftByteUtils.getIsoBytes(" Do\n"));
    restoreState();
    return this;
  }

  CraftPdfCanvas addInlineImage(CraftPdfImageXObject imageXObject, double a,
      double b, double c, double d, double e, double f) {
    return this;
  }
}

class PdfSpecialCsPattern {}
