import 'linear_symbol_painter.dart';
import 'dart:typed_data';

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
class CraftBarcode39 extends CraftBarcode1D {
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
  factory CraftBarcode39(CraftPdfDocument document, [CraftPdfFont? font]) {
    final resolvedFont = font ?? document.defaultTypeface();
    if (resolvedFont == null) {
      throw ArgumentError(
          'Could not create default font for barcode. Please provide a font explicitly.');
    }
    return CraftBarcode39._internal(document, resolvedFont);
  }

  CraftBarcode39._internal(CraftPdfDocument document, CraftPdfFont font)
      : super(document) {
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

  (List<double>, String) _visualData() {
    final encoded = extended ? getCode39Ex(code) : code;
    final check = generateChecksum ? getChecksum(encoded) : '';
    var label = code + (checksumText ? check : '');
    if (startStopText) label = '*$label*';
    return (
      getBarsCode39(encoded + check)
          .map((run) => x * (run == 0 ? 1 : n))
          .toList(),
      altText ?? label
    );
  }

  @override
  CraftRectangle getBarcodeSize() {
    final (runs, label) = _visualData();
    return measureLinearSymbol(this, runs, label);
  }

  @override
  Future<CraftRectangle> placeBarcode(CraftPdfCanvas canvas,
      CraftColor? barColor, CraftColor? textColor) async {
    final (runs, label) = _visualData();
    await drawLinearSymbol(this, canvas, runs, label, barColor, textColor);
    return measureLinearSymbol(this, runs, label);
  }
}
