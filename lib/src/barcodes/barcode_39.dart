import 'dart:typed_data';
import 'dart:math' as math;

import '../kernel/colors/color.dart';
import '../kernel/font/pdf_font.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_document.dart';

import 'barcode_1d.dart';

/// This class represents the barcode Code 39.
///
/// Code 39 is a variable length, discrete barcode symbology defined in ISO/IEC 16388:2007.
///
/// The Code 39 specification defines 43 characters, consisting of uppercase letters (A through Z), numeric digits (0
/// through 9) and a number of special characters (-, ., $, /, +, %, and space). An additional character (denoted '*') is
/// used for both start and stop delimiters. Each character is composed of nine elements: five bars and four spaces.
class Barcode39 extends Barcode1D {
  /// The bars to generate the code.
  static const List<List<int>> BARS = [
    [0, 0, 0, 1, 1, 0, 1, 0, 0],
    [1, 0, 0, 1, 0, 0, 0, 0, 1],
    [0, 0, 1, 1, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 0, 0, 0, 0, 0],
    [0, 0, 0, 1, 1, 0, 0, 0, 1],
    [1, 0, 0, 1, 1, 0, 0, 0, 0],
    [0, 0, 1, 1, 1, 0, 0, 0, 0],
    [0, 0, 0, 1, 0, 0, 1, 0, 1],
    [1, 0, 0, 1, 0, 0, 1, 0, 0],
    [0, 0, 1, 1, 0, 0, 1, 0, 0],
    [1, 0, 0, 0, 0, 1, 0, 0, 1],
    [0, 0, 1, 0, 0, 1, 0, 0, 1],
    [1, 0, 1, 0, 0, 1, 0, 0, 0],
    [0, 0, 0, 0, 1, 1, 0, 0, 1],
    [1, 0, 0, 0, 1, 1, 0, 0, 0],
    [0, 0, 1, 0, 1, 1, 0, 0, 0],
    [0, 0, 0, 0, 0, 1, 1, 0, 1],
    [1, 0, 0, 0, 0, 1, 1, 0, 0],
    [0, 0, 1, 0, 0, 1, 1, 0, 0],
    [0, 0, 0, 0, 1, 1, 1, 0, 0],
    [1, 0, 0, 0, 0, 0, 0, 1, 1],
    [0, 0, 1, 0, 0, 0, 0, 1, 1],
    [1, 0, 1, 0, 0, 0, 0, 1, 0],
    [0, 0, 0, 0, 1, 0, 0, 1, 1],
    [1, 0, 0, 0, 1, 0, 0, 1, 0],
    [0, 0, 1, 0, 1, 0, 0, 1, 0],
    [0, 0, 0, 0, 0, 0, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 1, 1, 0],
    [0, 0, 1, 0, 0, 0, 1, 1, 0],
    [0, 0, 0, 0, 1, 0, 1, 1, 0],
    [1, 1, 0, 0, 0, 0, 0, 0, 1],
    [0, 1, 1, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 0, 0, 0, 0, 0, 0],
    [0, 1, 0, 0, 1, 0, 0, 0, 1],
    [1, 1, 0, 0, 1, 0, 0, 0, 0],
    [0, 1, 1, 0, 1, 0, 0, 0, 0],
    [0, 1, 0, 0, 0, 0, 1, 0, 1],
    [1, 1, 0, 0, 0, 0, 1, 0, 0],
    [0, 1, 1, 0, 0, 0, 1, 0, 0],
    [0, 1, 0, 1, 0, 1, 0, 0, 0],
    [0, 1, 0, 1, 0, 0, 0, 1, 0],
    [0, 1, 0, 0, 0, 1, 0, 1, 0],
    [0, 0, 0, 1, 0, 1, 0, 1, 0],
    [0, 1, 0, 0, 1, 0, 1, 0, 0]
  ];

  /// The index chars to [BARS], symbol * use only start and stop characters,
  /// the * character will not appear in the input data.
  static const String CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. \$/+%*";

  /// The character combinations to make the code 39 extended.
  static const String EXTENDED = "%U" +
      "\$A\$B\$C\$D\$E\$F\$G\$H\$I\$J\$K\$L\$M\$N\$O\$P\$Q\$R\$S\$T\$U\$V\$W\$X\$Y\$Z" +
      "%A%B%C%D%E  /A/B/C/D/E/F/G/H/I/J/K/L - ./O" +
      " 0 1 2 3 4 5 6 7 8 9/Z%F%G%H%I%J%V" +
      " A B C D E F G H I J K L M N O P Q R S T U V W X Y Z" +
      "%K%L%M%N%O%W" +
      "+A+B+C+D+E+F+G+H+I+J+K+L+M+N+O+P+Q+R+S+T+U+V+W+X+Y+Z" +
      "%P%Q%R%S%T";

  /// Creates a new [Barcode39].
  ///
  /// To generate the font the [PdfDocument.getDefaultFont] will be implicitly called.
  /// If you want to use this barcode in PDF/A documents, please consider using
  /// [Barcode39](PdfDocument document, PdfFont font).
  factory Barcode39(PdfDocument document, [PdfFont? font]) {
    final resolvedFont = font ?? document.getDefaultFont();
    if (resolvedFont == null) {
      throw ArgumentError(
          'Could not create default font for barcode. Please provide a font explicitly.');
    }
    return Barcode39._internal(document, resolvedFont);
  }

  Barcode39._internal(PdfDocument document, PdfFont font) : super(document) {
    this.x = 0.8;
    this.n = 2;
    this.font = font;
    this.size = 8;
    this.baseline = size;
    this.barHeight = size * 3;
    this.generateChecksum = false;
    this.checksumText = false;
    this.startStopText = true;
    this.extended = false;
  }

  /// Creates the bars.
  ///
  /// [text] - the text to create the bars. This text does not include the start and
  /// stop characters
  /// Returns the bars
  static Uint8List getBarsCode39(String text) {
    text = "*" + text + "*";
    Uint8List bars = Uint8List(text.length * 10 - 1);
    for (int k = 0; k < text.length; ++k) {
      String ch = text[k];
      int idx = CHARS.indexOf(ch);
      if (ch == '*' && k != 0 && k != (text.length - 1)) {
        throw ArgumentError("The character $ch is illegal in code 39");
      }
      if (idx < 0) {
        throw ArgumentError("The character ${text[k]} is illegal in code 39");
      }
      List.copyRange(bars, k * 10, BARS[idx]);
    }
    return bars;
  }

  /// Converts the extended text into a normal, escaped text,
  /// ready to generate bars.
  ///
  /// [text] - the extended text
  /// Returns the escaped text
  static String getCode39Ex(String text) {
    StringBuffer out = StringBuffer();
    for (int k = 0; k < text.length; ++k) {
      int c = text.codeUnitAt(k);
      if (c > 127) {
        throw ArgumentError("The character ${text[k]} is illegal in code 39");
      }
      String c1 = EXTENDED[c * 2];
      String c2 = EXTENDED[c * 2 + 1];
      if (c1 != ' ') {
        out.write(c1);
      }
      out.write(c2);
    }
    return out.toString();
  }

  /// Calculates the checksum.
  ///
  /// [text] - the text
  /// Returns the checksum
  static String getChecksum(String text) {
    int chk = 0;
    for (int k = 0; k < text.length; ++k) {
      int idx = CHARS.indexOf(text[k]);
      String ch = text[k];
      if (ch == '*' && k != 0 && k != (text.length - 1)) {
        throw ArgumentError("The character $ch is illegal in code 39");
      }
      if (idx < 0) {
        throw ArgumentError("The character ${text[k]} is illegal in code 39");
      }
      chk += idx;
    }
    return CHARS[chk % 43];
  }

  @override
  Rectangle getBarcodeSize() {
    double fontX = 0;
    double fontY = 0;
    String fCode = code;
    if (extended) {
      fCode = getCode39Ex(code);
    }
    if (font != null) {
      if (baseline > 0) {
        fontY = baseline - getDescender();
      } else {
        fontY = -baseline + size;
      }
      String fullCode = code;
      if (generateChecksum && checksumText) {
        fullCode += getChecksum(fCode);
      }
      if (startStopText) {
        fullCode = "*" + fullCode + "*";
      }
      fontX = font!.getWidthPoint(altText != null ? altText! : fullCode, size);
    }
    int len = fCode.length + 2;
    if (generateChecksum) {
      ++len;
    }
    double fullWidth = len * (6 * x + 3 * x * n) + (len - 1) * x;
    fullWidth = math.max(fullWidth, fontX);
    double fullHeight = barHeight + fontY;
    return Rectangle(0, 0, fullWidth, fullHeight);
  }

  @override
  Future<Rectangle> placeBarcode(
      PdfCanvas canvas, Color? barColor, Color? textColor) async {
    String fullCode = code;
    double fontX = 0;
    String bCode = code;
    if (extended) {
      bCode = getCode39Ex(code);
    }
    if (font != null) {
      if (generateChecksum && checksumText) {
        fullCode += getChecksum(bCode);
      }
      if (startStopText) {
        fullCode = "*" + fullCode + "*";
      }
      fullCode = altText != null ? altText! : fullCode;
      fontX = font!.getWidthPoint(fullCode, size);
    }
    if (generateChecksum) {
      bCode += getChecksum(bCode);
    }
    int len = bCode.length + 2;
    double fullWidth = len * (6 * x + 3 * x * n) + (len - 1) * x;
    double barStartX = 0;
    double textStartX = 0;
    switch (textAlignment) {
      case Barcode1D.ALIGN_LEFT:
        {
          break;
        }

      case Barcode1D.ALIGN_RIGHT:
        {
          if (fontX > fullWidth) {
            barStartX = fontX - fullWidth;
          } else {
            textStartX = fullWidth - fontX;
          }
          break;
        }

      default:
        {
          if (fontX > fullWidth) {
            barStartX = (fontX - fullWidth) / 2;
          } else {
            textStartX = (fullWidth - fontX) / 2;
          }
          break;
        }
    }
    double barStartY = 0;
    double textStartY = 0;
    if (font != null) {
      if (baseline <= 0) {
        textStartY = barHeight - baseline;
      } else {
        textStartY = -getDescender();
        barStartY = textStartY + baseline;
      }
    }
    Uint8List bars = getBarsCode39(bCode);
    bool print = true;
    if (barColor != null) {
      canvas.setFillColor(barColor);
    }
    for (int k = 0; k < bars.length; ++k) {
      double w = (bars[k] == 0 ? x : x * n);
      if (print) {
        canvas.rectangle(barStartX, barStartY, w - inkSpreading, barHeight);
      }
      print = !print;
      barStartX += w;
    }
    canvas.fill();
    if (font != null) {
      if (textColor != null) {
        canvas.setFillColor(textColor);
      }
      canvas.beginText();
      await canvas.setFontAndSize(font!, size);
      canvas.setTextMatrixSimple(textStartX, textStartY);
      canvas.showText(fullCode);
      canvas.endText();
    }
    return getBarcodeSize();
  }
}
