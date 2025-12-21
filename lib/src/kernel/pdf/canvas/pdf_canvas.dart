import 'dart:typed_data';
import 'package:itext/src/io/source/byte_utils.dart';
import 'package:itext/src/kernel/pdf/pdf_stream.dart';
import 'package:itext/src/kernel/pdf/pdf_resources.dart';
import 'package:itext/src/kernel/pdf/pdf_document.dart';
import 'package:itext/src/kernel/pdf/pdf_page.dart';

import 'package:itext/src/kernel/pdf/canvas/canvas_graphics_state.dart';
import 'package:itext/src/kernel/geom/matrix.dart';
import 'package:itext/src/kernel/font/pdf_font.dart';
import 'package:itext/src/kernel/pdf/pdf_string.dart';
import 'package:itext/src/kernel/pdf/pdf_name.dart';

/// PdfCanvas class represents an algorithm for writing data into content stream.
class PdfCanvas {
  // Constants for operators
  static final Uint8List B = ByteUtils.getIsoBytes("B\n");
  static final Uint8List b = ByteUtils.getIsoBytes("b\n");
  static final Uint8List BStar = ByteUtils.getIsoBytes("B*\n");
  static final Uint8List bStar = ByteUtils.getIsoBytes("b*\n");
  static final Uint8List BT = ByteUtils.getIsoBytes("BT\n");
  static final Uint8List cm = ByteUtils.getIsoBytes("cm\n");
  static final Uint8List ET = ByteUtils.getIsoBytes("ET\n");
  static final Uint8List f = ByteUtils.getIsoBytes("f\n");
  static final Uint8List fStar = ByteUtils.getIsoBytes("f*\n");
  static final Uint8List G = ByteUtils.getIsoBytes("G\n");
  static final Uint8List g = ByteUtils.getIsoBytes("g\n");
  static final Uint8List gs = ByteUtils.getIsoBytes("gs\n");
  static final Uint8List l = ByteUtils.getIsoBytes("l\n");
  static final Uint8List m = ByteUtils.getIsoBytes("m\n");
  static final Uint8List n = ByteUtils.getIsoBytes("n\n");
  static final Uint8List q = ByteUtils.getIsoBytes("q\n");
  static final Uint8List Q = ByteUtils.getIsoBytes("Q\n");
  static final Uint8List re = ByteUtils.getIsoBytes("re\n");
  static final Uint8List RG = ByteUtils.getIsoBytes("RG\n");
  static final Uint8List rg = ByteUtils.getIsoBytes("rg\n");
  static final Uint8List S = ByteUtils.getIsoBytes("S\n");
  static final Uint8List s = ByteUtils.getIsoBytes("s\n");
  static final Uint8List Td = ByteUtils.getIsoBytes("Td\n");
  static final Uint8List TD = ByteUtils.getIsoBytes("TD\n");
  static final Uint8List Tf = ByteUtils.getIsoBytes("Tf\n");
  static final Uint8List Tj = ByteUtils.getIsoBytes("Tj\n");
  static final Uint8List TL = ByteUtils.getIsoBytes("TL\n");
  static final Uint8List Tm = ByteUtils.getIsoBytes("Tm\n");
  static final Uint8List Tr = ByteUtils.getIsoBytes("Tr\n");
  static final Uint8List Ts = ByteUtils.getIsoBytes("Ts\n");
  static final Uint8List TStar = ByteUtils.getIsoBytes("T*\n");
  static final Uint8List Tw = ByteUtils.getIsoBytes("Tw\n");
  static final Uint8List Tz = ByteUtils.getIsoBytes("Tz\n");
  static final Uint8List w = ByteUtils.getIsoBytes("w\n");
  static final Uint8List W = ByteUtils.getIsoBytes("W\n");
  static final Uint8List WStar = ByteUtils.getIsoBytes("W*\n");

  List<CanvasGraphicsState> gsStack = [];
  CanvasGraphicsState currentGs = CanvasGraphicsState();
  PdfStream? contentStream;
  PdfResources? resources;
  PdfDocument? document;

  PdfCanvas(
      PdfStream contentStream, PdfResources? resources, PdfDocument? document) {
    this.contentStream = _ensureStreamDataIsReadyToBeProcessed(contentStream);
    this.resources = resources;
    this.document = document;
  }

  static Future<PdfCanvas> fromPage(PdfPage page) async {
    PdfStream? stream;
    final count = await page.getContentStreamCount();
    if (count > 0) {
      final obj = await page.getContentStream(count - 1);
      if (obj is PdfStream) {
        stream = obj;
      }
    }

    if (stream == null) {
      // TODO: Implement proper logic to add new stream to page
      throw UnimplementedError(
          "Creating new content stream for page is not yet implemented.");
    }

    final doc = page.getPdfObject().getIndirectReference()?.getDocument();
    return PdfCanvas(stream, await page.getResources(), doc);
  }

  PdfStream _ensureStreamDataIsReadyToBeProcessed(PdfStream stream) {
    return stream;
  }

  void release() {
    gsStack.clear();
    currentGs = CanvasGraphicsState();
    contentStream = null;
    resources = null;
    document = null;
  }

  PdfCanvas saveState() {
    gsStack.add(CanvasGraphicsState(currentGs));
    contentStream!.getOutputStream().writeBytes(q);
    return this;
  }

  PdfCanvas restoreState() {
    if (gsStack.isEmpty) {
      throw StateError("Unbalanced save/restore state operators.");
    }
    currentGs = gsStack.removeLast();
    contentStream!.getOutputStream().writeBytes(Q);
    return this;
  }

  PdfCanvas concatMatrix(
      double a, double b, double c, double d, double e, double f) {
    currentGs.ctm = Matrix.fromAffine(a, b, c, d, e, f).multiply(currentGs.ctm);
    contentStream!.getOutputStream()
      ..writeDouble(a)
      ..writeSpace()
      ..writeDouble(b)
      ..writeSpace()
      ..writeDouble(c)
      ..writeSpace()
      ..writeDouble(d)
      ..writeSpace()
      ..writeDouble(e)
      ..writeSpace()
      ..writeDouble(f)
      ..writeSpace()
      ..writeBytes(cm);
    return this;
  }

  PdfCanvas moveTo(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeSpace()
      ..writeDouble(y)
      ..writeSpace()
      ..writeBytes(m);
    return this;
  }

  PdfCanvas lineTo(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeSpace()
      ..writeDouble(y)
      ..writeSpace()
      ..writeBytes(l);
    return this;
  }

  PdfCanvas stroke() {
    contentStream!.getOutputStream().writeBytes(S);
    return this;
  }

  PdfCanvas closePathStroke() {
    contentStream!.getOutputStream().writeBytes(s);
    return this;
  }

  PdfCanvas fill() {
    contentStream!.getOutputStream().writeBytes(f);
    return this;
  }

  PdfCanvas fillStroke() {
    contentStream!.getOutputStream().writeBytes(B);
    return this;
  }

  PdfCanvas rectangle(double x, double y, double w, double h) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeSpace()
      ..writeDouble(y)
      ..writeSpace()
      ..writeDouble(w)
      ..writeSpace()
      ..writeDouble(h)
      ..writeSpace()
      ..writeBytes(re);
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

  Future<PdfCanvas> setFontAndSize(PdfFont font, double size) async {
    currentGs.fontSize = size;
    currentGs.font = font;

    if (resources != null && document != null) {
      PdfName fontName = await resources!.addFont(document!, font);
      contentStream!.getOutputStream()
        ..writePdfName(fontName)
        ..writeSpace()
        ..writeDouble(size)
        ..writeSpace()
        ..writeBytes(Tf);
    }
    return this;
  }

  PdfCanvas moveText(double x, double y) {
    contentStream!.getOutputStream()
      ..writeDouble(x)
      ..writeSpace()
      ..writeDouble(y)
      ..writeSpace()
      ..writeBytes(Td);
    return this;
  }

  PdfCanvas showText(String text) {
    // TODO: Check default color
    // CheckDefaultDeviceGrayBlackColor(GetColorKeyForText());
    contentStream!.getOutputStream()
      ..writePdfStringObject(PdfString(text))
      ..writeSpace()
      ..writeBytes(Tj);
    return this;
  }
}
