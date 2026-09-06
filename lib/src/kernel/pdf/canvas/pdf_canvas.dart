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

/// PdfCanvas class represents an algorithm for writing data into content stream.
class PdfCanvas {
  // Constants for operators
  static final Uint8List B = ByteUtils.getIsoBytes("B\n");
  static final Uint8List b_low = ByteUtils.getIsoBytes("b\n");
  static final Uint8List BDC = ByteUtils.getIsoBytes("BDC\n");
  static final Uint8List BI = ByteUtils.getIsoBytes("BI\n");
  static final Uint8List BMC = ByteUtils.getIsoBytes("BMC\n");
  static final Uint8List BStar = ByteUtils.getIsoBytes("B*\n");
  static final Uint8List bStar = ByteUtils.getIsoBytes("b*\n");
  static final Uint8List BT = ByteUtils.getIsoBytes("BT\n");
  static final Uint8List c_op = ByteUtils.getIsoBytes("c\n");
  static final Uint8List cm_op = ByteUtils.getIsoBytes("cm\n");
  static final Uint8List cs_op = ByteUtils.getIsoBytes("cs\n");
  static final Uint8List CS_op = ByteUtils.getIsoBytes("CS\n");
  static final Uint8List d_op = ByteUtils.getIsoBytes("d\n");
  static final Uint8List Do_op = ByteUtils.getIsoBytes("Do\n");
  static final Uint8List EI = ByteUtils.getIsoBytes("EI\n");
  static final Uint8List EMC = ByteUtils.getIsoBytes("EMC\n");
  static final Uint8List ET = ByteUtils.getIsoBytes("ET\n");
  static final Uint8List f_op = ByteUtils.getIsoBytes("f\n");
  static final Uint8List fStar = ByteUtils.getIsoBytes("f*\n");
  static final Uint8List G_op = ByteUtils.getIsoBytes("G\n");
  static final Uint8List g_op = ByteUtils.getIsoBytes("g\n");
  static final Uint8List gs_op = ByteUtils.getIsoBytes("gs\n");
  static final Uint8List h_op = ByteUtils.getIsoBytes("h\n");
  static final Uint8List i_op = ByteUtils.getIsoBytes("i\n");
  static final Uint8List ID = ByteUtils.getIsoBytes("ID\n");
  static final Uint8List j_op = ByteUtils.getIsoBytes("j\n");
  static final Uint8List J_op = ByteUtils.getIsoBytes("J\n");
  static final Uint8List k_op = ByteUtils.getIsoBytes("k\n");
  static final Uint8List K_op = ByteUtils.getIsoBytes("K\n");
  static final Uint8List l_op = ByteUtils.getIsoBytes("l\n");
  static final Uint8List m_op = ByteUtils.getIsoBytes("m\n");
  static final Uint8List M_op = ByteUtils.getIsoBytes("M\n");
  static final Uint8List n_op = ByteUtils.getIsoBytes("n\n");
  static final Uint8List q_op = ByteUtils.getIsoBytes("q\n");
  static final Uint8List Q_op = ByteUtils.getIsoBytes("Q\n");
  static final Uint8List re_op = ByteUtils.getIsoBytes("re\n");
  static final Uint8List RG_op = ByteUtils.getIsoBytes("RG\n");
  static final Uint8List rg_op = ByteUtils.getIsoBytes("rg\n");
  static final Uint8List ri_op = ByteUtils.getIsoBytes("ri\n");
  static final Uint8List S_op = ByteUtils.getIsoBytes("S\n");
  static final Uint8List s_op = ByteUtils.getIsoBytes("s\n");
  static final Uint8List scn = ByteUtils.getIsoBytes("scn\n");
  static final Uint8List SCN = ByteUtils.getIsoBytes("SCN\n");
  static final Uint8List sh_op = ByteUtils.getIsoBytes("sh\n");
  static final Uint8List Tc = ByteUtils.getIsoBytes("Tc\n");
  static final Uint8List Td = ByteUtils.getIsoBytes("Td\n");
  static final Uint8List TD = ByteUtils.getIsoBytes("TD\n");
  static final Uint8List Tf = ByteUtils.getIsoBytes("Tf\n");
  static final Uint8List TJ = ByteUtils.getIsoBytes("TJ\n");
  static final Uint8List Tj = ByteUtils.getIsoBytes("Tj\n");
  static final Uint8List TL = ByteUtils.getIsoBytes("TL\n");
  static final Uint8List Tm = ByteUtils.getIsoBytes("Tm\n");
  static final Uint8List Tr = ByteUtils.getIsoBytes("Tr\n");
  static final Uint8List Ts = ByteUtils.getIsoBytes("Ts\n");
  static final Uint8List TStar = ByteUtils.getIsoBytes("T*\n");
  static final Uint8List Tw = ByteUtils.getIsoBytes("Tw\n");
  static final Uint8List Tz = ByteUtils.getIsoBytes("Tz\n");
  static final Uint8List v_op = ByteUtils.getIsoBytes("v\n");
  static final Uint8List w_op = ByteUtils.getIsoBytes("w\n");
  static final Uint8List W_op = ByteUtils.getIsoBytes("W\n");
  static final Uint8List WStar = ByteUtils.getIsoBytes("W*\n");
  static final Uint8List y_op = ByteUtils.getIsoBytes("y\n");

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
  /// enclosed by the rectangle for which two opposite corners are specified.
  PdfCanvas arc(double x1, double y1, double x2, double y2, double startAng,
      double extent,
      [AffineTransform? transform]) {
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

  List<CanvasGraphicsState> gsStack = [];
  CanvasGraphicsState currentGs = CanvasGraphicsState();
  PdfStream? contentStream;
  PdfResources? resources;
  PdfDocument? document;
  int mcDepth = 0;
  bool drawingOnPage = false;

  CanvasGraphicsState getGraphicsState() => currentGs;

  PdfCanvas(
      PdfStream contentStream, PdfResources? resources, PdfDocument? document) {
    this.contentStream = _ensureStreamDataIsReadyToBeProcessed(contentStream);
    this.resources = resources;
    this.document = document;
  }

  PdfDocument? getDocument() => document;

  static Future<PdfCanvas> fromPage(PdfPage page) async {
    PdfStream? stream;
    final count = await page.getContentStreamCount();
    if (count > 0) {
      final obj = await page.getContentStream(count - 1);
      if (obj is PdfStream) {
        stream = obj;
      }
    }

    final doc = page.getPdfObject().getIndirectReference()?.getDocument();

    if (stream == null) {
      stream = PdfStream();
      if (doc != null) {
        stream.makeIndirect(doc);
      }
      page.getPdfObject().put(PdfName.contents, stream);
    }

    final canvas = PdfCanvas(stream, await page.getResources(), doc);
    canvas.drawingOnPage = true;
    return canvas;
  }

  static Future<PdfCanvas> fromFormXObject(
      PdfFormXObject xObj, PdfDocument document) async {
    return PdfCanvas(xObj.getPdfObject(), await xObj.getResources(), document);
  }

  PdfStream _ensureStreamDataIsReadyToBeProcessed(PdfStream stream) {
    return stream;
  }

  void release() {
    contentStream = null;
    resources = null;
    document = null;
  }

  PdfCanvas saveState() {
    gsStack.add(currentGs.copy());
    contentStream!.getOutputStream().writeBytes(q_op);
    return this;
  }

  PdfCanvas restoreState() {
    if (gsStack.isNotEmpty) {
      currentGs = gsStack.removeLast();
    }
    contentStream!.getOutputStream().writeBytes(Q_op);
    return this;
  }

  PdfCanvas concatMatrix(
      double a, double b, double c, double d, double e, double f) {
    currentGs
        .getCtm()
        .concatenate(AffineTransform.fromValues(a, b, c, d, e, f));
    contentStream!.getOutputStream()
      ..writeDouble(a)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(b)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(c)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(d)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(e)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(f)
      ..writeBytes(ByteUtils.getIsoBytes(" cm\n"));
    return this;
  }

  PdfCanvas beginText() {
    contentStream!.getOutputStream().writeBytes(BT);
    return this;
  }

  PdfCanvas endText() {
    contentStream!.getOutputStream().writeBytes(ET);
    return this;
  }

  PdfCanvas moveTo(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(ByteUtils.getIsoBytes(" m\n"));
    return this;
  }

  PdfCanvas lineTo(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(ByteUtils.getIsoBytes(" l\n"));
    return this;
  }

  PdfCanvas curveTo1(double x1, double y1, double x3, double y3) {
    contentStream!.getOutputStream()
      ..writeDouble(x1)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y1)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(x3)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y3)
      ..writeBytes(ByteUtils.getIsoBytes(" v\n"));
    return this;
  }

  PdfCanvas curveTo2(double x2, double y2, double x3, double y3) {
    contentStream!.getOutputStream()
      ..writeDouble(x2)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y2)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(x3)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y3)
      ..writeBytes(ByteUtils.getIsoBytes(" y\n"));
    return this;
  }

  PdfCanvas curveTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    contentStream!.getOutputStream()
      ..writeDouble(x1)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y1)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(x2)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y2)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(x3)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y3)
      ..writeBytes(ByteUtils.getIsoBytes(" c\n"));
    return this;
  }

  PdfCanvas circle(double x, double y, double r) {
    arc(x - r, y - r, x + r, y + r, 0, 360);
    return this;
  }

  PdfCanvas closePath() {
    contentStream!.getOutputStream().writeBytes(h_op);
    return this;
  }

  PdfCanvas stroke() {
    contentStream!.getOutputStream().writeBytes(S_op);
    return this;
  }

  PdfCanvas closePathStroke() {
    contentStream!.getOutputStream().writeBytes(s_op);
    return this;
  }

  PdfCanvas clip() {
    contentStream!.getOutputStream().writeBytes(W_op);
    contentStream!.getOutputStream().writeBytes(n_op);
    return this;
  }

  PdfCanvas eoClip() {
    contentStream!.getOutputStream().writeBytes(WStar);
    contentStream!.getOutputStream().writeBytes(n_op);
    return this;
  }

  PdfCanvas fill() {
    contentStream!.getOutputStream().writeBytes(f_op);
    return this;
  }

  PdfCanvas eoFill() {
    contentStream!.getOutputStream().writeBytes(fStar);
    return this;
  }

  PdfCanvas fillStroke() {
    contentStream!.getOutputStream().writeBytes(B);
    return this;
  }

  PdfCanvas closePathFillStroke() {
    contentStream!.getOutputStream().writeBytes(b_low);
    return this;
  }

  PdfCanvas eoFillStroke() {
    contentStream!.getOutputStream().writeBytes(BStar);
    return this;
  }

  PdfCanvas closePathEoFillStroke() {
    contentStream!.getOutputStream().writeBytes(bStar);
    return this;
  }

  PdfCanvas newPath() {
    contentStream!.getOutputStream().writeBytes(n_op);
    return this;
  }

  PdfCanvas rectangle(double x, double y, double w, double h) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(w)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(h)
      ..writeBytes(ByteUtils.getIsoBytes(" re\n"));
    return this;
  }

  PdfCanvas setCharacterSpacing(double charSpacing) {
    contentStream!.getOutputStream()
      ..writeDouble(charSpacing)
      ..writeBytes(ByteUtils.getIsoBytes(" Tc\n"));
    return this;
  }

  PdfCanvas setWordSpacing(double wordSpacing) {
    contentStream!.getOutputStream()
      ..writeDouble(wordSpacing)
      ..writeBytes(ByteUtils.getIsoBytes(" Tw\n"));
    return this;
  }

  PdfCanvas setHorizontalScaling(double horizontalScaling) {
    contentStream!.getOutputStream()
      ..writeDouble(horizontalScaling)
      ..writeBytes(ByteUtils.getIsoBytes(" Tz\n"));
    return this;
  }

  PdfCanvas setTextRise(double textRise) {
    contentStream!.getOutputStream()
      ..writeDouble(textRise)
      ..writeBytes(ByteUtils.getIsoBytes(" Ts\n"));
    return this;
  }

  PdfCanvas setTextRenderingMode(int textRenderingMode) {
    contentStream!.getOutputStream()
      ..writeInteger(textRenderingMode)
      ..writeBytes(ByteUtils.getIsoBytes(" Tr\n"));
    return this;
  }

  Future<PdfCanvas> setFontAndSize(PdfFont font, double size) async {
    currentGs.setFont(font);
    currentGs.setFontSize(size);
    PdfName fontName = await resources!.addFont(document!, font);
    contentStream!.getOutputStream()
      ..writeBytes(ByteUtils.getIsoBytes("/${fontName.getValue()}"))
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(size)
      ..writeBytes(ByteUtils.getIsoBytes(" Tf\n"));
    return this;
  }

  PdfCanvas moveText(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(ByteUtils.getIsoBytes(" Td\n"));
    return this;
  }

  PdfCanvas moveTextWithLeading(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(ByteUtils.getIsoBytes(" TD\n"));
    return this;
  }

  PdfCanvas setTextMatrix(
      double a, double b, double c, double d, double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(a)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(b)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(c)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(d)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(x)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(y)
      ..writeBytes(ByteUtils.getIsoBytes(" Tm\n"));
    return this;
  }

  PdfCanvas setTextMatrixSimple(double x, double y) {
    return setTextMatrix(1, 0, 0, 1, x, y);
  }

  PdfCanvas setLeading(double leading) {
    contentStream!.getOutputStream()
      ..writeDouble(leading)
      ..writeBytes(ByteUtils.getIsoBytes(" TL\n"));
    return this;
  }

  PdfCanvas newlineText() {
    contentStream!.getOutputStream().writeBytes(TStar);
    return this;
  }

  Future<PdfCanvas> newlineShowText(String text) async {
    final font = currentGs.getFont();
    if (font == null) {
      // Fallback for missing font
      contentStream!.getOutputStream()
          ..writeBytes(ByteUtils.getIsoBytes("(${text.replaceAll('(', '\\(').replaceAll(')', '\\)')})"))
          ..writeBytes(ByteUtils.getIsoBytes(" '\n"));
    } else {
      font.writeText(text, contentStream!.getOutputStream());
      contentStream!.getOutputStream().writeBytes(ByteUtils.getIsoBytes(" '\n"));
    }
    return this;
  }

  PdfCanvas showText(dynamic text) {
    final font = currentGs.getFont();
    final os = contentStream!.getOutputStream();
    if (text is String) {
      if (font == null) {
        os.writeBytes(ByteUtils.getIsoBytes(
            "(${text.replaceAll('(', '\\(').replaceAll(')', '\\)')})"));
      } else {
        font.writeText(text, os);
      }
      os.writeBytes(ByteUtils.getIsoBytes(" Tj\n"));
    } else if (text is GlyphLine) {
      if (font == null) {
        _showGlyphLine(text);
      } else {
        font.writeText(text, os);
      }
      os.writeBytes(ByteUtils.getIsoBytes(" Tj\n"));
    }
    return this;
  }

  void _showGlyphLine(GlyphLine text) {
    final os = contentStream!.getOutputStream();
    os.writeBytes(ByteUtils.getIsoBytes("("));
    for (int i = text.getStart(); i < text.getEnd(); i++) {
      final glyph = text.get(i);
      final unicode = glyph.getUnicode();
      if (unicode != -1) {
        // Simple character output for now (works for standard fonts)
        final char = String.fromCharCode(unicode);
        if (char == '(' || char == ')' || char == '\\') {
           os.writeBytes(ByteUtils.getIsoBytes("\\"));
        }
        os.writeBytes(ByteUtils.getIsoBytes(char));
      }
    }
    os.writeBytes(ByteUtils.getIsoBytes(") Tj\n"));
  }

  PdfCanvas showTextWithAdjustment(List<dynamic> items) {
    contentStream!.getOutputStream().writeBytes(ByteUtils.getIsoBytes("["));
    for (var item in items) {
      if (item is String) {
        contentStream!.getOutputStream()
          ..writeBytes(ByteUtils.getIsoBytes(
              "(${item.replaceAll('(', '\\(').replaceAll(')', '\\)')})"));
      } else if (item is double || item is int) {
        contentStream!.getOutputStream().writeDouble(item.toDouble());
      }
      contentStream!.getOutputStream().writeBytes(ByteUtils.getIsoBytes(" "));
    }
    contentStream!
        .getOutputStream()
        .writeBytes(ByteUtils.getIsoBytes("] TJ\n"));
    return this;
  }

  PdfCanvas newlineShowTextWithSpacing(
      double wordSpacing, double charSpacing, String text) {
    contentStream!.getOutputStream()
      ..writeDouble(wordSpacing)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(charSpacing)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeBytes(ByteUtils.getIsoBytes(
          "(${text.replaceAll('(', '\\(').replaceAll(')', '\\)')})"))
      ..writeBytes(ByteUtils.getIsoBytes(" \"\n"));
    return this;
  }

  PdfCanvas setLineWidth(double lineWidth) {
    contentStream!.getOutputStream()
      ..writeDouble(lineWidth)
      ..writeBytes(ByteUtils.getIsoBytes(" w\n"));
    return this;
  }

  PdfCanvas setLineCap(int lineCap) {
    contentStream!.getOutputStream()
      ..writeInteger(lineCap)
      ..writeBytes(ByteUtils.getIsoBytes(" J\n"));
    return this;
  }

  PdfCanvas setLineJoin(int lineJoin) {
    contentStream!.getOutputStream()
      ..writeInteger(lineJoin)
      ..writeBytes(ByteUtils.getIsoBytes(" j\n"));
    return this;
  }

  PdfCanvas setMiterLimit(double miterLimit) {
    contentStream!.getOutputStream()
      ..writeDouble(miterLimit)
      ..writeBytes(ByteUtils.getIsoBytes(" M\n"));
    return this;
  }

  PdfCanvas setDashPattern(PdfArray dashPattern, [double phase = 0]) {
    contentStream!.getOutputStream()
      ..writePdfObject(dashPattern)
      ..writeBytes(ByteUtils.getIsoBytes(" "))
      ..writeDouble(phase)
      ..writeBytes(ByteUtils.getIsoBytes(" d\n"));
    return this;
  }

  PdfCanvas setFlatness(double flatness) {
    contentStream!.getOutputStream()
      ..writeDouble(flatness)
      ..writeBytes(ByteUtils.getIsoBytes(" i\n"));
    return this;
  }

  PdfCanvas setFillColor(Color color) {
    return _setColor(color, true);
  }

  PdfCanvas setStrokeColor(Color color) {
    return _setColor(color, false);
  }

  PdfCanvas _setColor(Color color, bool fill) {
    if (color is DeviceRgb) {
      contentStream!.getOutputStream()
        ..writeDouble(color.getColorValue()[0])
        ..writeBytes(ByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[1])
        ..writeBytes(ByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[2])
        ..writeBytes(ByteUtils.getIsoBytes(fill ? " rg\n" : " RG\n"));
    } else if (color is DeviceGray) {
      contentStream!.getOutputStream()
        ..writeDouble(color.getColorValue()[0])
        ..writeBytes(ByteUtils.getIsoBytes(fill ? " g\n" : " G\n"));
    } else if (color is DeviceCmyk) {
      contentStream!.getOutputStream()
        ..writeDouble(color.getColorValue()[0])
        ..writeBytes(ByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[1])
        ..writeBytes(ByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[2])
        ..writeBytes(ByteUtils.getIsoBytes(" "))
        ..writeDouble(color.getColorValue()[3])
        ..writeBytes(ByteUtils.getIsoBytes(fill ? " k\n" : " K\n"));
    }
    return this;
  }

  PdfCanvas setRenderingIntent(PdfName intent) {
    contentStream!.getOutputStream()
      ..writePdfObject(intent)
      ..writeBytes(ByteUtils.getIsoBytes(" ri\n"));
    return this;
  }

  Future<PdfCanvas> setExtGState(PdfExtGState gs) async {
    PdfName name = await resources!.addExtGState(document!, gs.getPdfObject());
    contentStream!.getOutputStream()
      ..writeBytes(ByteUtils.getIsoBytes("/${name.getValue()}"))
      ..writeBytes(ByteUtils.getIsoBytes(" gs\n"));
    return this;
  }

  Future<PdfCanvas> shading(PdfShading shading) async {
    PdfName name =
        await resources!.addShading(document!, shading.getPdfObject());
    contentStream!.getOutputStream()
      ..writeBytes(ByteUtils.getIsoBytes("/${name.getValue()}"))
      ..writeBytes(ByteUtils.getIsoBytes(" sh\n"));
    return this;
  }

  Future<PdfCanvas> beginMarkedContent(PdfName tag,
      [PdfDictionary? properties]) async {
    if (properties == null) {
      contentStream!.getOutputStream()
        ..writeBytes(ByteUtils.getIsoBytes("/${tag.getValue()}"))
        ..writeBytes(ByteUtils.getIsoBytes(" BMC\n"));
    } else {
      PdfName name = await resources!.addProperties(document!, properties);
      contentStream!.getOutputStream()
        ..writeBytes(ByteUtils.getIsoBytes("/${tag.getValue()}"))
        ..writeBytes(ByteUtils.getIsoBytes(" "))
        ..writeBytes(ByteUtils.getIsoBytes("/${name.getValue()}"))
        ..writeBytes(ByteUtils.getIsoBytes(" BDC\n"));
    }
    mcDepth++;
    return this;
  }

  PdfCanvas endMarkedContent() {
    if (mcDepth > 0) {
      contentStream!.getOutputStream().writeBytes(EMC);
      mcDepth--;
    }
    return this;
  }

  Future<PdfCanvas> addImageAt(ImageData image, double x, double y,
      [bool inline = false]) async {
    return addImageWithTransformationMatrix(image, image.getWidth().toDouble(),
        0, 0, image.getHeight().toDouble(), x, y, inline);
  }

  Future<PdfCanvas> addImageWithTransformationMatrix(ImageData image, double a,
      double b, double c, double d, double e, double f,
      [bool inline = false]) async {
    if (inline) {
      // ... BI ... ID ... EI
    } else {
      PdfImageXObject imageXObject = PdfImageXObject(image);
      PdfName name =
          await resources!.addXObject(document!, imageXObject.getPdfObject());
      saveState();
      concatMatrix(a, b, c, d, e, f);
      contentStream!.getOutputStream()
        ..writeBytes(ByteUtils.getIsoBytes("/${name.getValue()}"))
        ..writeBytes(ByteUtils.getIsoBytes(" Do\n"));
      restoreState();
    }
    return this;
  }

  Future<PdfCanvas> addXObject(PdfXObject xObject, double x, double y) async {
    double a = 1.0;
    double d = 1.0;
    if (xObject is PdfImageXObject) {
      a = xObject.getWidth();
      d = xObject.getHeight();
    }
    return addXObjectWithTransformationMatrix(
        xObject.getPdfObject(), a, 0, 0, d, x, y);
  }

  Future<PdfCanvas> addXObjectWithTransformationMatrix(PdfStream xObject,
      double a, double b, double c, double d, double e, double f) async {
    PdfName name = await resources!.addXObject(document!, xObject);
    saveState();
    concatMatrix(a, b, c, d, e, f);
    contentStream!.getOutputStream()
      ..writeBytes(ByteUtils.getIsoBytes("/${name.getValue()}"))
      ..writeBytes(ByteUtils.getIsoBytes(" Do\n"));
    restoreState();
    return this;
  }

  PdfCanvas addInlineImage(PdfImageXObject imageXObject, double a, double b,
      double c, double d, double e, double f) {
    return this;
  }
}

class PdfSpecialCsPattern {}
